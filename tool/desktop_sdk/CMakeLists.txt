cmake_minimum_required(VERSION 3.16)

project(mimc_sdk_desktop LANGUAGES C CXX)

if(NOT DEFINED MIMC_SDK_SOURCE)
  message(FATAL_ERROR "Set MIMC_SDK_SOURCE to a Xiaomi mimc-cpp-sdk checkout")
endif()

get_filename_component(MIMC_SDK_SOURCE "${MIMC_SDK_SOURCE}" ABSOLUTE)
if(NOT EXISTS "${MIMC_SDK_SOURCE}/include/mimc/user_c.h")
  message(FATAL_ERROR "MIMC_SDK_SOURCE does not contain include/mimc/user_c.h")
endif()

file(GLOB MIMC_SOURCES CONFIGURE_DEPENDS
  "${MIMC_SDK_SOURCE}/src/*.c"
  "${MIMC_SDK_SOURCE}/src/*.cc"
  "${MIMC_SDK_SOURCE}/src/*.cpp"
)
file(GLOB XMD_SOURCES CONFIGURE_DEPENDS
  "${MIMC_SDK_SOURCE}/msg-libs/xmdtransceiver/src/*.c"
  "${MIMC_SDK_SOURCE}/msg-libs/xmdtransceiver/src/*.cpp"
)
# Xiaomi normally builds MIMC and XMD as separate libraries, each with its own
# zlib adler32 copy. They become duplicate symbols in this single distributable
# desktop library, so retain the MIMC copy only.
list(FILTER XMD_SOURCES EXCLUDE REGEX "/adler32\\.c$")
file(GLOB JSON_C_SOURCES CONFIGURE_DEPENDS
  "${MIMC_SDK_SOURCE}/third-party/json-c/json-c/*.c"
)

# The generated MIMC messages only require protobuf-lite. Keep the exact
# source subset from Xiaomi's own iOS build instead of linking an incompatible
# modern protobuf runtime.
set(PROTOBUF_LITE_SOURCES
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/stubs/atomicops_internals_x86_gcc.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/stubs/atomicops_internals_x86_msvc.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/stubs/common.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/stubs/once.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/stubs/stringprintf.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/extension_set.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/generated_message_util.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/message_lite.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/repeated_field.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/wire_format_lite.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/io/coded_stream.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/io/zero_copy_stream.cc"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src/google/protobuf/io/zero_copy_stream_impl_lite.cc"
)

add_library(mimc_sdk SHARED
  ${MIMC_SOURCES}
  ${XMD_SOURCES}
  ${JSON_C_SOURCES}
  ${PROTOBUF_LITE_SOURCES}
  "${CMAKE_CURRENT_SOURCE_DIR}/portable_crypto.cpp"
)

target_compile_features(mimc_sdk PRIVATE cxx_std_11)
target_include_directories(mimc_sdk PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${MIMC_SDK_SOURCE}/include"
  "${MIMC_SDK_SOURCE}/msg-libs/xmdtransceiver/include"
  "${MIMC_SDK_SOURCE}/third-party/json-c"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0"
  "${MIMC_SDK_SOURCE}/third-party/protobuf-2_5_0/src"
)

find_package(CURL REQUIRED)
target_link_libraries(mimc_sdk PRIVATE CURL::libcurl)
if(WIN32)
  find_package(PThreads4W REQUIRED)
  target_link_libraries(mimc_sdk PRIVATE PThreads4W::PThreads4W)
else()
  find_package(Threads REQUIRED)
  target_link_libraries(mimc_sdk PRIVATE Threads::Threads)
endif()

target_compile_definitions(mimc_sdk PRIVATE
  _GLIBCXX_USE_NANOSLEEP
)
if(APPLE)
  target_compile_definitions(mimc_sdk PRIVATE _IOS_MIMC_USE_)
  set_target_properties(mimc_sdk PROPERTIES
    BUILD_WITH_INSTALL_RPATH YES
    INSTALL_NAME_DIR "@rpath"
    MACOSX_RPATH YES
    OSX_ARCHITECTURES "${CMAKE_OSX_ARCHITECTURES}"
  )
endif()
if(WIN32)
  target_compile_definitions(mimc_sdk PRIVATE
    WIN_USE_DLL
    MIMCAPI_EXPORTS
    _CRT_SECURE_NO_WARNINGS
  )
  target_link_libraries(mimc_sdk PRIVATE ws2_32 iphlpapi)
  set_target_properties(mimc_sdk PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS YES)
endif()

if(MSVC)
  target_compile_options(mimc_sdk PRIVATE /EHsc /W3)
else()
  target_compile_options(mimc_sdk PRIVATE
    -fno-exceptions
    -Wno-deprecated-declarations
    -Wno-unused-local-typedefs
    -Wno-sign-compare
  )
endif()

set_target_properties(mimc_sdk PROPERTIES
  OUTPUT_NAME "mimc_sdk"
  POSITION_INDEPENDENT_CODE YES
)

install(TARGETS mimc_sdk
  RUNTIME DESTINATION .
  LIBRARY DESTINATION .
  ARCHIVE DESTINATION .
)
