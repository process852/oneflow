#include <google/protobuf/text_format.h>
#include "oneflow/core/common/buffer_manager.h"
#include "oneflow/core/common/protobuf.h"
#include "oneflow/core/register/ofblob.h"
#include "oneflow/core/job/job_set.pb.h"
#include "oneflow/core/job/oneflow.h"
#include "oneflow/core/job/foreign_job_instance.h"
#include "oneflow/core/job/environment_objects_scope.h"
#include "oneflow/core/job/machine_context.h"
#include "oneflow/core/job/oneflow.h"
#include "oneflow/core/job/runtime_job_descs.h"
#include "oneflow/core/control/cluster_control.pb.h"
#include "oneflow/core/control/ctrl_client.h"
#include "oneflow/core/job/runtime_buffer_managers_scope.h"
#include "oneflow/core/control/cluster_control.h"
#include "oneflow/core/job/job_set_compile_ctx.h"
#include "oneflow/core/job/job_build_and_infer_ctx_mgr.h"

namespace oneflow {

Maybe<bool> IsOpTypeCaseCpuSupportOnly(int64_t op_type_case) {
  using namespace oneflow;
  using OnlyCpuSupport = OnlyCpuSupportPredicator;
  OF_CHECK(IsClassRegistered<OnlyCpuSupport>(op_type_case)) << ": op_type_case = " << op_type_case;
  return static_cast<bool>(*std::unique_ptr<OnlyCpuSupport>(NewObj<OnlyCpuSupport>(op_type_case)));
}

Maybe<void> InitBySerializedConfigProto(const std::string& config_proto_str) {
  using namespace oneflow;
  ConfigProto config_proto;
  OF_CHECK(google::protobuf::TextFormat::ParseFromString(config_proto_str, &config_proto))
      << "InitBySerializedConfigProto(): failed to parse config_proto: " << config_proto_str;
  OF_CHECK_ISNULL(Global<EnvironmentObjectsScope>::Get());
  // Global<T>::New is not allowed to be called here
  // because glog is not constructed yet and LOG(INFO) has bad bahavior
  Global<EnvironmentObjectsScope>::SetAllocated(new EnvironmentObjectsScope());
  Global<EnvironmentObjectsScope>::Get()->Init(config_proto);
  LOG(INFO) << "NewGlobal " << typeid(EnvironmentObjectsScope).name();
  if (Global<MachineCtx>::Get()->IsThisMachineMaster()) {
    Global<CtrlClient>::Get()->PushKV("master_config_proto", config_proto);
  } else {
    ConfigProto master_config_proto;
    Global<CtrlClient>::Get()->PullKV("master_config_proto", &master_config_proto);
    OF_CHECK(PbMd().Equals(config_proto, master_config_proto))
        << "InitBySerializedConfigProto(): config_proto not equals master_config_proto";

    while (ClusterControl::WorkerReceiveHalt() == false) {
      JobSet job_set;
      Global<CtrlClient>::Get()->PullKV("session_job_set", &job_set);
      { Oneflow oneflow(job_set); }
    }
    ClusterControl::WorkerSendHaltAck();
    Global<EnvironmentObjectsScope>::Delete();
    exit(0);
  }
  return Maybe<void>::Ok();
}

Maybe<void> InitGlobalOneflow() {
  using namespace oneflow;
  OF_CHECK(Global<MachineCtx>::Get()->IsThisMachineMaster());
  ClusterControl::MasterSendSessionStart();
  const JobSet& job_set = Global<JobBuildAndInferCtxMgr>::Get()->job_set();
  if (job_set.job().empty()) { return Error::JobSetEmpty() << "no function defined"; }
  OF_CHECK_ISNULL(Global<Oneflow>::Get());
  Global<CtrlClient>::Get()->PushKV("session_job_set", job_set);
  Global<RuntimeBufferManagersScope>::New();
  Global<JobSetCompileCtx>::New();
  Global<Oneflow>::New(job_set);
  return Maybe<void>::Ok();
}

Maybe<std::string> GetSerializedInterUserJobInfo() {
  using namespace oneflow;
  OF_CHECK(Global<MachineCtx>::Get()->IsThisMachineMaster());
  OF_CHECK_NOTNULL(Global<Oneflow>::Get());
  OF_CHECK_NOTNULL(Global<InterUserJobInfo>::Get());
  std::string ret;
  google::protobuf::TextFormat::PrintToString(*Global<InterUserJobInfo>::Get(), &ret);
  return ret;
}

Maybe<void> LaunchJob(const std::shared_ptr<oneflow::ForeignJobInstance>& cb) {
  using namespace oneflow;
  OF_CHECK(Global<MachineCtx>::Get()->IsThisMachineMaster());
  OF_CHECK_NOTNULL(Global<Oneflow>::Get());
  const auto& job_name = cb->job_name();
  auto* buffer_mgr = Global<BufferMgr<std::shared_ptr<ForeignJobInstance>>>::Get();
  int64_t job_id = Global<JobName2JobId>::Get()->at(job_name);
  if (IsPullJob(job_name, *Global<InterUserJobInfo>::Get())) {
    buffer_mgr->Get(GetForeignOutputBufferName(job_name))->Send(cb);
  }
  if (IsPushJob(job_name, *Global<InterUserJobInfo>::Get())) {
    buffer_mgr->Get(GetForeignInputBufferName(job_name))->Send(cb);
  }
  buffer_mgr->Get(GetCallbackNotifierBufferName(job_name))->Send(cb);
  Global<BufferMgr<int64_t>>::Get()->Get(kBufferNameGlobalWaitJobId)->Send(job_id);
  return Maybe<void>::Ok();
}

Maybe<void> DestroyGlobalOneflow() {
  using namespace oneflow;
  OF_CHECK(Global<MachineCtx>::Get()->IsThisMachineMaster());
  OF_CHECK_NOTNULL(Global<Oneflow>::Get());
  Global<Oneflow>::Delete();
  Global<JobSetCompileCtx>::Delete();
  Global<RuntimeBufferManagersScope>::Delete();
  return Maybe<void>::Ok();
}

Maybe<void> DestroyGlobalEnvironment() {
  using namespace oneflow;
  if (Global<EnvironmentObjectsScope>::Get() == nullptr) { return Maybe<void>::Ok(); }
  OF_CHECK(Global<MachineCtx>::Get()->IsThisMachineMaster());
  ClusterControl::MasterSendHaltAndWaitAck();
  Global<EnvironmentObjectsScope>::Delete();
  return Maybe<void>::Ok();
}

Maybe<long long> GetDeviceType4DeviceTag(const std::string& device_tag) {
  return *JUST(DeviceType4DeviceTag(device_tag));
}

namespace {

struct GlobalChecker final {
  GlobalChecker() = default;
  ~GlobalChecker() {
    if (Global<Oneflow>::Get() != nullptr) { LOG(FATAL) << "global oneflow is not destroyed yet"; }
    if (Global<EnvironmentObjectsScope>::Get() != nullptr) {
      LOG(FATAL) << "global environment is not destroyed yet";
    }
  }
};

GlobalChecker checker;

}  // namespace

}  // namespace oneflow
