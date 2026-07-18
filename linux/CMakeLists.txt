cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "flutter_mimc")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src"
                 "${CMAKE_CURRENT_BINARY_DIR}/shared")

file(GLOB FLUTTER_MIMC_SDK_LIBRARIES
  "${CMAKE_CURRENT_SOURCE_DIR}/vendor/*.so"
  "${CMAKE_CURRENT_SOURCE_DIR}/vendor/*.so.*"
)

set(flutter_mimc_bundled_libraries
  $<TARGET_FILE:flutter_mimc>
  ${FLUTTER_MIMC_SDK_LIBRARIES}
  PARENT_SCOPE
)
