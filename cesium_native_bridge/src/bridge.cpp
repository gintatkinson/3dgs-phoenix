#include "bridge.h"

#include <CesiumGeospatial/Ellipsoid.h>
#include <CesiumGeospatial/Cartographic.h>

#include <glm/vec3.hpp>
#include <glm/trigonometric.hpp>

#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace {

struct BridgeState {
  bridge_error_callback_t errorCallback = nullptr;
  void* errorUserData = nullptr;
  std::string lastError;
};

std::unordered_map<bridge_handle_t, std::shared_ptr<BridgeState>> g_states;
std::mutex g_statesMutex;
bridge_handle_t g_nextHandle = 1;

} // namespace

bridge_handle_t bridge_initialize(
    const bridge_tileset_config_t* config,
    bridge_error_callback_t on_error,
    void* user_data) {

  if (!config) return BRIDGE_ERR_INIT;

  try {
    std::lock_guard<std::mutex> lock(g_statesMutex);
    bridge_handle_t handle = g_nextHandle++;

    auto state = std::make_unique<BridgeState>();
    state->errorCallback = on_error;
    state->errorUserData = user_data;

    g_states[handle] = std::move(state);
    return handle;
  } catch (const std::exception&) {
    return BRIDGE_ERR_MEMORY;
  } catch (...) {
    return BRIDGE_ERR_FATAL;
  }
}

void bridge_shutdown(bridge_handle_t handle) {
  std::shared_ptr<BridgeState> state;
  {
    std::lock_guard<std::mutex> lock(g_statesMutex);
    auto it = g_states.find(handle);
    if (it != g_states.end()) {
      state = it->second;
      g_states.erase(it);
    }
  }
}

int32_t bridge_is_ready(bridge_handle_t handle) {
  std::lock_guard<std::mutex> lock(g_statesMutex);
  return g_states.count(handle) ? 1 : 0;
}

int32_t bridge_get_last_error(bridge_handle_t handle, char* out, int32_t size) {
  if (!out || size <= 0) return BRIDGE_ERR_MEMORY;
  std::lock_guard<std::mutex> lock(g_statesMutex);
  auto it = g_states.find(handle);
  const char* src = (it == g_states.end()) ? "Invalid handle" : it->second->lastError.c_str();
  std::strncpy(out, src, static_cast<size_t>(size) - 1);
  out[size - 1] = '\0';
  return BRIDGE_OK;
}

int32_t bridge_update_camera(bridge_handle_t handle, const bridge_camera_t* camera) {
  if (!camera) return BRIDGE_ERR_CAMERA;
  return BRIDGE_OK;
}

int32_t bridge_register_camera_callback(
    bridge_handle_t,
    bridge_camera_changed_callback_t,
    void*) {
  return BRIDGE_OK;
}

int32_t bridge_get_visible_tile_count(bridge_handle_t, int32_t* out_count) {
  if (!out_count) return BRIDGE_ERR_TILE;
  *out_count = 0;
  return BRIDGE_OK;
}

int32_t bridge_get_visible_tile_id(bridge_handle_t, int32_t, char** out_tile_id) {
  if (!out_tile_id) return BRIDGE_ERR_TILE;
  *out_tile_id = nullptr;
  return BRIDGE_ERR_TILE;
}

int32_t bridge_request_tile_data(
    bridge_handle_t,
    const char*,
    bridge_tile_ready_callback_t,
    void*) {
  return BRIDGE_ERR_TILE;
}

void bridge_free_string(char* str) {
  free(str);
}

int32_t bridge_cartographic_to_ecef(
    double lat_deg,
    double lng_deg,
    double alt_m,
    double* out_x,
    double* out_y,
    double* out_z) {
  if (!out_x || !out_y || !out_z) return BRIDGE_ERR_CAMERA;

  try {
    const CesiumGeospatial::Ellipsoid& ellipsoid = CesiumGeospatial::Ellipsoid::WGS84;
    const CesiumGeospatial::Cartographic carto = CesiumGeospatial::Cartographic::fromDegrees(lng_deg, lat_deg, alt_m);
    const glm::dvec3 ecef = ellipsoid.cartographicToCartesian(carto);

    if (glm::any(glm::isnan(ecef)) || glm::any(glm::isinf(ecef))) {
      return BRIDGE_ERR_CAMERA;
    }

    *out_x = ecef.x;
    *out_y = ecef.y;
    *out_z = ecef.z;
    return BRIDGE_OK;
  } catch (const std::exception&) {
    return BRIDGE_ERR_CAMERA;
  }
}

int32_t bridge_ecef_to_cartographic(
    double x,
    double y,
    double z,
    double* out_lat_deg,
    double* out_lng_deg,
    double* out_alt_m) {
  if (!out_lat_deg || !out_lng_deg || !out_alt_m) return BRIDGE_ERR_CAMERA;

  try {
    const CesiumGeospatial::Ellipsoid& ellipsoid = CesiumGeospatial::Ellipsoid::WGS84;
    std::optional<CesiumGeospatial::Cartographic> carto = ellipsoid.cartesianToCartographic(glm::dvec3(x, y, z));

    if (!carto) {
      return BRIDGE_ERR_CAMERA;
    }

    *out_lat_deg = glm::degrees(carto->latitude);
    *out_lng_deg = glm::degrees(carto->longitude);
    *out_alt_m = carto->height;
    return BRIDGE_OK;
  } catch (const std::exception&) {
    return BRIDGE_ERR_CAMERA;
  }
}
