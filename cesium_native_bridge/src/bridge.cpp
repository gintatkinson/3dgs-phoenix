#include "bridge.h"

#include <Cesium3DTilesSelection/ViewState.h>
#include <Cesium3DTilesSelection/ViewUpdateResult.h>
#include <Cesium3DTilesSelection/Tile.h>
#include <Cesium3DTilesSelection/TileID.h>
#include <Cesium3DTilesSelection/TileContent.h>
#include <Cesium3DTilesSelection/Tileset.h>
#include <CesiumAsync/AsyncSystem.h>
#include <CesiumAsync/IAssetAccessor.h>
#include <CesiumAsync/ITaskProcessor.h>
#include <CesiumCurl/CurlAssetAccessor.h>
#include <CesiumGeospatial/Ellipsoid.h>
#include <CesiumGeospatial/Cartographic.h>
#include <CesiumGltf/Model.h>
#include <CesiumGltfWriter/GltfWriter.h>

#include <glm/vec3.hpp>
#include <glm/vec4.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/trigonometric.hpp>

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

class SyncTaskProcessor : public CesiumAsync::ITaskProcessor {
public:
  void startTask(std::function<void()> f) override { f(); }
};

struct BridgeState {
  std::shared_ptr<CesiumCurl::CurlAssetAccessor> curlAssetAccessor;
  std::shared_ptr<SyncTaskProcessor> taskProcessor;
  std::optional<CesiumAsync::AsyncSystem> asyncSystem;
  std::shared_ptr<Cesium3DTilesSelection::Tileset> tileset;
  bridge_error_callback_t errorCallback = nullptr;
  void* errorUserData = nullptr;
  std::string lastError;
  int32_t lastVisibleTileCount = 0;
  std::vector<Cesium3DTilesSelection::Tile::ConstPointer> lastTilesToRenderThisFrame;
  std::optional<Cesium3DTilesSelection::ViewState> lastViewState;
};

std::unordered_map<bridge_handle_t, std::shared_ptr<BridgeState>> g_states;
std::mutex g_statesMutex;
bridge_handle_t g_nextHandle = 1;

void reportError(BridgeState* state, int32_t code, const std::string& msg) {
  if (state) {
    state->lastError = msg;
    if (state->errorCallback) {
      state->errorCallback(code, msg.c_str(), state->errorUserData);
    }
  }
}

} // namespace

bridge_handle_t bridge_initialize(
    const bridge_tileset_config_t* config,
    bridge_error_callback_t on_error,
    void* user_data) {

  if (!config) return BRIDGE_ERR_INIT;

  try {
    std::lock_guard<std::mutex> lock(g_statesMutex);
    if (g_nextHandle == INT32_MAX) return BRIDGE_ERR_MEMORY;
    bridge_handle_t handle = g_nextHandle++;

    auto state = std::make_shared<BridgeState>();
    state->errorCallback = on_error;
    state->errorUserData = user_data;

    // Only create Tileset if tileset_url is provided (allows test initialization with nullptr)
    if (config->tileset_url && config->tileset_url[0] != '\0') {
      CesiumCurl::CurlAssetAccessorOptions curlOptions;
      
      // Look up CESIUM_ION_TOKEN from the environment
      const char* env_token = std::getenv("CESIUM_ION_TOKEN");
      if (env_token && env_token[0] != '\0') {
        curlOptions.requestHeaders.emplace_back(
            "Authorization",
            std::string("Bearer ") + env_token);
      }

      state->curlAssetAccessor =
          std::make_shared<CesiumCurl::CurlAssetAccessor>(curlOptions);

      state->taskProcessor = std::make_shared<SyncTaskProcessor>();
      state->asyncSystem = CesiumAsync::AsyncSystem(state->taskProcessor);

      Cesium3DTilesSelection::TilesetOptions tilesetOptions;
      tilesetOptions.maximumCachedBytes =
          static_cast<int64_t>(config->max_cached_bytes);
      tilesetOptions.maximumSimultaneousTileLoads =
          static_cast<uint32_t>(config->max_simultaneous_tile_loads);

      Cesium3DTilesSelection::TilesetExternals externals{
        state->curlAssetAccessor,
        nullptr,
        *state->asyncSystem
      };

      // Check if tileset_url is a numeric asset ID (Cesium Ion asset ID)
      bool isIonAsset = true;
      int64_t ionAssetId = 1; // default to Cesium World Terrain (1)
      
      std::string urlStr(config->tileset_url);
      if (urlStr.rfind("http://", 0) == 0 || urlStr.rfind("https://", 0) == 0) {
        isIonAsset = false;
      } else {
        try {
          ionAssetId = std::stoll(urlStr);
        } catch (...) {
          isIonAsset = false;
        }
      }

      if (isIonAsset) {
        std::string tokenStr = env_token ? env_token : "";
        state->tileset = std::make_shared<Cesium3DTilesSelection::Tileset>(
            externals,
            ionAssetId,
            tokenStr,
            tilesetOptions,
            "https://api.cesium.com/"
        );
      } else {
        state->tileset = std::make_shared<Cesium3DTilesSelection::Tileset>(
            externals,
            urlStr,
            tilesetOptions
        );
      }
    }

    g_states[handle] = std::move(state);
    return handle;
  } catch (const std::exception& e) {
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
  if (state && state->tileset && state->asyncSystem) {
    CesiumAsync::SharedFuture<void> destructionEvent =
        state->tileset->getAsyncDestructionCompleteEvent();
    state->tileset.reset();
    int maxWaits = 10000;
    while (!destructionEvent.isReady() && maxWaits > 0) {
      state->asyncSystem->dispatchMainThreadTasks();
      --maxWaits;
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

  if (std::isnan(camera->latitude) || std::isnan(camera->longitude) ||
      std::isnan(camera->altitude) ||
      camera->latitude < -90.0 || camera->latitude > 90.0) {
    return BRIDGE_ERR_CAMERA;
  }

  std::shared_ptr<BridgeState> state;
  {
    std::lock_guard<std::mutex> lock(g_statesMutex);
    auto it = g_states.find(handle);
    if (it == g_states.end()) return BRIDGE_ERR_INIT;
    state = it->second;
  }

  if (!state->tileset) return BRIDGE_ERR_INIT;

  try {
    const CesiumGeospatial::Ellipsoid& ellipsoid = CesiumGeospatial::Ellipsoid::WGS84;
    const CesiumGeospatial::Cartographic carto =
        CesiumGeospatial::Cartographic::fromDegrees(
            camera->longitude, camera->latitude, camera->altitude);
    const glm::dvec3 position = ellipsoid.cartographicToCartesian(carto);

    double lat_rad = glm::radians(camera->latitude);
    double lng_rad = glm::radians(camera->longitude);
    double heading_rad = glm::radians(camera->heading);
    double pitch_rad = glm::radians(camera->pitch);
    double roll_rad = glm::radians(camera->roll);

    glm::dvec3 up_ecef = ellipsoid.geodeticSurfaceNormal(position);
    glm::dvec3 east_ecef = glm::normalize(glm::dvec3(-std::sin(lng_rad), std::cos(lng_rad), 0.0));
    glm::dvec3 north_ecef = glm::normalize(glm::cross(up_ecef, east_ecef));

    glm::dquat q_heading = glm::angleAxis(-heading_rad, up_ecef);
    glm::dvec3 east_rotated = q_heading * east_ecef;
    glm::dquat q_pitch = glm::angleAxis(pitch_rad, east_rotated);

    glm::dquat q_hp = q_pitch * q_heading;
    glm::dvec3 direction = q_hp * north_ecef;
    glm::dvec3 up = q_hp * up_ecef;

    glm::dquat q_roll = glm::angleAxis(roll_rad, direction);
    up = glm::normalize(q_roll * up);

    double hFov = glm::radians(60.0);
    double vFov = glm::radians(45.0);
    glm::dvec2 viewportSize(1920.0, 1080.0);

    state->lastViewState.emplace(
        position, direction, up, viewportSize, hFov, vFov, ellipsoid);

    std::vector<Cesium3DTilesSelection::ViewState> frustums;
    frustums.push_back(state->lastViewState.value());

    const auto& viewResult = state->tileset->updateViewGroup(
        state->tileset->getDefaultViewGroup(), frustums);
    state->tileset->loadTiles();
    state->lastVisibleTileCount = static_cast<int32_t>(
        viewResult.tilesToRenderThisFrame.size());
    state->lastTilesToRenderThisFrame = viewResult.tilesToRenderThisFrame;

    return BRIDGE_OK;
  } catch (const std::exception& e) {
    reportError(state.get(), BRIDGE_ERR_CAMERA, e.what());
    return BRIDGE_ERR_CAMERA;
  } catch (...) {
    reportError(state.get(), BRIDGE_ERR_CAMERA, "Unknown camera error");
    return BRIDGE_ERR_CAMERA;
  }
}

int32_t bridge_register_camera_callback(
    bridge_handle_t,
    bridge_camera_changed_callback_t,
    void*) {
  return BRIDGE_OK;
}

int32_t bridge_get_visible_tile_count(bridge_handle_t handle, int32_t* out_count) {
  if (!out_count) return BRIDGE_ERR_TILE;
  std::lock_guard<std::mutex> lock(g_statesMutex);
  auto it = g_states.find(handle);
  if (it == g_states.end()) {
    *out_count = 0;
    return BRIDGE_ERR_TILE;
  }
  *out_count = it->second->lastVisibleTileCount;
  return BRIDGE_OK;
}

int32_t bridge_get_visible_tile_id(bridge_handle_t handle, int32_t index, char** out_tile_id) {
  if (!out_tile_id) return BRIDGE_ERR_TILE;
  std::lock_guard<std::mutex> lock(g_statesMutex);
  auto it = g_states.find(handle);
  if (it == g_states.end()) {
    *out_tile_id = nullptr;
    return BRIDGE_ERR_TILE;
  }
  auto& state = *it->second;
  if (index < 0 || index >= static_cast<int32_t>(state.lastTilesToRenderThisFrame.size())) {
    *out_tile_id = nullptr;
    return BRIDGE_ERR_TILE;
  }
  std::string id = Cesium3DTilesSelection::TileIdUtilities::createTileIdString(
      state.lastTilesToRenderThisFrame[index]->getTileID());
  *out_tile_id = strdup(id.c_str());
  return BRIDGE_OK;
}

int32_t bridge_request_tile_data(
    bridge_handle_t handle,
    const char* tile_id,
    bridge_tile_ready_callback_t callback,
    void* user_data) {

  if (!tile_id || !callback) {
    return BRIDGE_ERR_TILE;
  }

  std::lock_guard<std::mutex> lock(g_statesMutex);
  auto it = g_states.find(handle);
  if (it == g_states.end() || !it->second->tileset) {
    return BRIDGE_ERR_TILE;
  }

  auto& state = *it->second;
  std::string targetId(tile_id);

  const Cesium3DTilesSelection::Tile* foundTile = nullptr;
  for (auto& tilePtr : state.lastTilesToRenderThisFrame) {
    std::string id = Cesium3DTilesSelection::TileIdUtilities::createTileIdString(
        tilePtr->getTileID());
    if (id == targetId) {
      foundTile = tilePtr.get();
      break;
    }
  }

  if (!foundTile) {
    return BRIDGE_ERR_TILE;
  }

  const Cesium3DTilesSelection::TileContent& content = foundTile->getContent();
  if (!content.isRenderContent()) {
    return BRIDGE_ERR_TILE;
  }

  const Cesium3DTilesSelection::TileRenderContent* pRenderContent =
      content.getRenderContent();
  if (!pRenderContent) {
    return BRIDGE_ERR_TILE;
  }

  const CesiumGltf::Model& model = pRenderContent->getModel();

  CesiumGltfWriter::GltfWriter writer;
  CesiumGltfWriter::GltfWriterResult result =
      writer.writeGltf(model, CesiumGltfWriter::GltfWriterOptions());

  callback(
      tile_id,
      reinterpret_cast<const uint8_t*>(result.gltfBytes.data()),
      static_cast<int32_t>(result.gltfBytes.size()),
      user_data);

  return BRIDGE_OK;
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

  if (std::isnan(lat_deg) || std::isnan(lng_deg) || std::isnan(alt_m) ||
      std::isinf(lat_deg) || std::isinf(lng_deg) || std::isinf(alt_m) ||
      lat_deg < -90.0 || lat_deg > 90.0) {
    return BRIDGE_ERR_CAMERA;
  }

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
  } catch (...) {
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

  if (std::isnan(x) || std::isnan(y) || std::isnan(z) ||
      std::isinf(x) || std::isinf(y) || std::isinf(z)) {
    return BRIDGE_ERR_CAMERA;
  }

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
  } catch (...) {
    return BRIDGE_ERR_CAMERA;
  }
}
