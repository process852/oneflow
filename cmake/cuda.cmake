if(BUILD_CUDA)
  if(DEFINED CUDA_TOOLKIT_ROOT_DIR)
    message(WARNING "CUDA_TOOLKIT_ROOT_DIR is deprecated, use CUDAToolkit_ROOT instead")
    set(CUDAToolkit_ROOT ${CUDA_TOOLKIT_ROOT_DIR})
  endif(DEFINED CUDA_TOOLKIT_ROOT_DIR)
  find_package(CUDAToolkit REQUIRED)
  message(STATUS "CUDAToolkit_FOUND: ${CUDAToolkit_FOUND}")
  message(STATUS "CUDAToolkit_VERSION: ${CUDAToolkit_VERSION}")
  message(STATUS "CUDAToolkit_VERSION_MAJOR: ${CUDAToolkit_VERSION_MAJOR}")
  message(STATUS "CUDAToolkit_VERSION_MINOR: ${CUDAToolkit_VERSION_MINOR}")
  message(STATUS "CUDAToolkit_VERSION_PATCH: ${CUDAToolkit_VERSION_PATCH}")
  message(STATUS "CUDAToolkit_BIN_DIR: ${CUDAToolkit_BIN_DIR}")
  message(STATUS "CUDAToolkit_INCLUDE_DIRS: ${CUDAToolkit_INCLUDE_DIRS}")
  message(STATUS "CUDAToolkit_LIBRARY_DIR: ${CUDAToolkit_LIBRARY_DIR}")
  message(STATUS "CUDAToolkit_LIBRARY_ROOT: ${CUDAToolkit_LIBRARY_ROOT}")
  message(STATUS "CUDAToolkit_TARGET_DIR: ${CUDAToolkit_TARGET_DIR}")
  message(STATUS "CUDAToolkit_NVCC_EXECUTABLE: ${CUDAToolkit_NVCC_EXECUTABLE}")
  if(CUDA_NVCC_GENCODES)
    message(FATAL_ERROR "CUDA_NVCC_GENCODES is deprecated, use CMAKE_CUDA_ARCHITECTURES instead")
  endif()
  add_definitions(-DWITH_CUDA)
  # NOTE: For some unknown reason, CUDAToolkit_VERSION may become empty when running cmake again
  set(CUDA_VERSION ${CUDAToolkit_VERSION} CACHE STRING "")
  if(NOT CUDA_VERSION)
    message(FATAL_ERROR "CUDA_VERSION empty")
  endif()
  message(STATUS "CUDA_VERSION: ${CUDA_VERSION}")
  if(CUDA_VERSION VERSION_GREATER_EQUAL "11.0")
    set(CUDA_STATIC OFF CACHE BOOL "")
  else()
    set(CUDA_STATIC ON CACHE BOOL "")
  endif()

  if((NOT CUDA_STATIC) OR BUILD_SHARED_LIBS)
    set(OF_CUDA_LINK_DYNAMIC_LIBRARY ON)
  else()
    set(OF_CUDA_LINK_DYNAMIC_LIBRARY OFF)
  endif()

  if(OF_CUDA_LINK_DYNAMIC_LIBRARY)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cublas)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::curand)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cusolver)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cufft)
    if(CUDA_VERSION VERSION_GREATER_EQUAL "10.1")
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cublasLt)
    endif()
    if(CUDA_VERSION VERSION_GREATER_EQUAL "10.2")
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::nvjpeg)
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::nppc)
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::nppig)
    endif()
  else()
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cublas_static)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::curand_static)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cufft_static)
    list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cusolver_static)
    if(CUDA_VERSION VERSION_GREATER_EQUAL "10.1")
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::cublasLt_static)
    endif()
    if(CUDA_VERSION VERSION_GREATER_EQUAL "10.2")
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::nvjpeg_static)
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::nppig_static)
      # Must put nppc_static after nppig_static in CUDA 10.2
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::nppc_static)
      list(APPEND VENDOR_CUDA_LIBRARIES CUDA::culibos)
    endif()
  endif()
  message(STATUS "VENDOR_CUDA_LIBRARIES: ${VENDOR_CUDA_LIBRARIES}")
  # add a cache entry if want to use a ccache/sccache wrapped nvcc
  set(CMAKE_CUDA_COMPILER ${CUDAToolkit_NVCC_EXECUTABLE} CACHE STRING "")
  message(STATUS "CMAKE_CUDA_COMPILER: ${CMAKE_CUDA_COMPILER}")
  set(CMAKE_CUDA_STANDARD 17)
  find_package(CUDNN REQUIRED)

  # NOTE: if you want to use source PTX with a version different from produced PTX/binary, you should add flags
  if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    list(APPEND CMAKE_CUDA_ARCHITECTURES 60-real)

    # Tesla P40/P4, Quadro Pxxx/Pxxxx, GeForce GTX 10xx, TITAN X/Xp
    list(APPEND CMAKE_CUDA_ARCHITECTURES 61-real)

    # V100, TITAN V
    list(APPEND CMAKE_CUDA_ARCHITECTURES 70-real)

    if(CUDA_VERSION VERSION_GREATER_EQUAL "10.0")
      # T4, Quadro RTX xxxx, Txxxx, Geforce RTX 20xx, TITAN RTX
      list(APPEND CMAKE_CUDA_ARCHITECTURES 75-real)
    endif()

    if(CUDA_VERSION VERSION_GREATER_EQUAL "11.0")
      # A100
      list(APPEND CMAKE_CUDA_ARCHITECTURES 80-real)
    endif()

    if(CUDA_VERSION VERSION_GREATER_EQUAL "11.1")
      # GeForce RTX 30xx
      list(APPEND CMAKE_CUDA_ARCHITECTURES 86-real)
    endif()

    if(CUDA_VERSION VERSION_GREATER_EQUAL "11.8")
      # GeForce RTX 40xx
      list(APPEND CMAKE_CUDA_ARCHITECTURES 89-real)
      # NVIDIA H100
      list(APPEND CMAKE_CUDA_ARCHITECTURES 90-real)
    endif()
  endif()

  foreach(CUDA_ARCH ${CMAKE_CUDA_ARCHITECTURES})
    if(CUDA_ARCH MATCHES "^([0-9]+)\\-real$")
      list(APPEND CUDA_REAL_ARCHS_LIST ${CMAKE_MATCH_1})
    elseif(CUDA_ARCH MATCHES "^([0-9]+)$")
      list(APPEND CUDA_REAL_ARCHS_LIST ${CMAKE_MATCH_1})
    endif()
  endforeach()

  enable_language(CUDA)
  include_directories(${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES})
  message(STATUS "CMAKE_CUDA_ARCHITECTURES: ${CMAKE_CUDA_ARCHITECTURES}")
  set(CUDA_SEPARABLE_COMPILATION OFF)

  if("${CMAKE_CUDA_COMPILER_ID}" STREQUAL "NVIDIA")
    if(CMAKE_CUDA_COMPILER_VERSION VERSION_GREATER_EQUAL "11.2")
      set(CUDA_NVCC_THREADS_NUMBER "4" CACHE STRING "")
      list(APPEND CUDA_NVCC_FLAGS -t ${CUDA_NVCC_THREADS_NUMBER})
    endif()
    list(APPEND CUDA_NVCC_FLAGS "-Xcompiler=-fno-strict-aliasing")
    message(STATUS "CUDA_NVCC_FLAGS: " ${CUDA_NVCC_FLAGS})
    list(JOIN CUDA_NVCC_FLAGS " " CMAKE_CUDA_FLAGS)
  endif()
endif()
