cmake_minimum_required(VERSION 3.20)
project(cesium_native_bridge VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS deployment version")
endif()

option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(CESIUM_DISABLE_CURL "Disable libcurl (use cesium-native's STB fallback)" OFF)

set(CESIUM_NATIVE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/cesium-native")

add_subdirectory(${CESIUM_NATIVE_DIR} ${CMAKE_BINARY_DIR}/cesium-native)

add_library(cesium_native_bridge SHARED
  src/bridge.cpp
  src/camera_marshal.cpp
  src/tile_data_marshal.cpp
  src/resource_manager.cpp
  src/error_propagator.cpp
)

target_include_directories(cesium_native_bridge
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CESIUM_NATIVE_DIR}/Cesium3DTilesSelection/include
    ${CESIUM_NATIVE_DIR}/CesiumGeospatial/include
    ${CESIUM_NATIVE_DIR}/CesiumGeometry/include
    ${CESIUM_NATIVE_DIR}/CesiumUtility/include
    ${CESIUM_NATIVE_DIR}/CesiumAsync/include
    ${CESIUM_NATIVE_DIR}/CesiumCurl/include
    ${CESIUM_NATIVE_DIR}/CesiumIonClient/include
    ${CESIUM_NATIVE_DIR}/CesiumGltf/include
    ${CESIUM_NATIVE_DIR}/CesiumGltfWriter/include
)

target_link_libraries(cesium_native_bridge PRIVATE
  Cesium3DTilesSelection
  CesiumGeospatial
  CesiumGeometry
  CesiumUtility
  CesiumAsync
  CesiumCurl
  CesiumIonClient
  CesiumGltf
  CesiumGltfWriter
)

if(APPLE)
  set_target_properties(cesium_native_bridge PROPERTIES
    SUFFIX ".dylib"
    INSTALL_RPATH "@executable_path/../Frameworks"
    MACOSX_RPATH ON
  )
elseif(WIN32)
  set_target_properties(cesium_native_bridge PROPERTIES
    SUFFIX ".dll"
  )
else()
  set_target_properties(cesium_native_bridge PROPERTIES
    SUFFIX ".so"
  )
endif()

install(TARGETS cesium_native_bridge
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
)
install(DIRECTORY include/ DESTINATION include)
