cmake_minimum_required(VERSION 3.10)

project(flutter_mimc_native VERSION 2.0.0 LANGUAGES CXX)

add_library(flutter_mimc SHARED
  flutter_mimc_bridge.cpp
  mimc_sdk_c_api.h
)

target_compile_features(flutter_mimc PRIVATE cxx_std_17)
target_compile_definitions(flutter_mimc PRIVATE FLUTTER_MIMC_SHARED_LIBRARY)

set_target_properties(flutter_mimc PROPERTIES
  PUBLIC_HEADER flutter_mimc_bridge.h
  OUTPUT_NAME "flutter_mimc"
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
)

# Flutter installs the bridge and the dynamically loaded Xiaomi SDK side by
# side in bundle/lib. Give dlopen("libmimc_sdk.so") a caller-relative search
# path instead of relying on the process working directory or LD_LIBRARY_PATH.
if(UNIX AND NOT APPLE)
  set_target_properties(flutter_mimc PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
  )
endif()

if(MSVC)
  target_compile_options(flutter_mimc PRIVATE /W4 /permissive-)
else()
  target_compile_options(flutter_mimc PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(CMAKE_DL_LIBS)
  target_link_libraries(flutter_mimc PRIVATE ${CMAKE_DL_LIBS})
endif()

# flutter_mimc_bridge loads the official C API dynamically. Set the
# FLUTTER_MIMC_CPP_SDK_LIBRARY environment variable at runtime, or bundle the
# SDK as libmimc_sdk.so / libmimc_sdk.dylib / mimc_sdk.dll beside this library.
