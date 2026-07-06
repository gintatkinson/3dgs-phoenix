#ifndef CESIUM_NATIVE_BRIDGE_H
#define CESIUM_NATIVE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* --- Status codes --- */
#define BRIDGE_OK                0
#define BRIDGE_ERR_INIT          -1
#define BRIDGE_ERR_CAMERA        -2
#define BRIDGE_ERR_TILE          -3
#define BRIDGE_ERR_MEMORY        -4
#define BRIDGE_ERR_PICK          -5
#define BRIDGE_ERR_NOT_READY     -6
#define BRIDGE_ERR_FATAL         -100

/* --- Opaque handle --- */
typedef int32_t bridge_handle_t;

/* --- Camera state (degrees; altitude in meters) --- */
typedef struct {
  double latitude;
  double longitude;
  double altitude;
  double heading;
  double pitch;
  double roll;
} bridge_camera_t;

/* --- Tileset configuration --- */
typedef struct {
  const char* tileset_url;
  int32_t max_simultaneous_tile_loads;
  int32_t max_cached_bytes;
} bridge_tileset_config_t;

/* --- Callback types --- */
typedef void (*bridge_error_callback_t)(int32_t error_code, const char* message, void* user_data);
typedef void (*bridge_tile_ready_callback_t)(const char* tile_id, const uint8_t* data, int32_t size, void* user_data);
typedef void (*bridge_camera_changed_callback_t)(double lat, double lng, double alt, double pitch, double heading, void* user_data);

/* --- Lifecycle --- */
bridge_handle_t bridge_initialize(
    const bridge_tileset_config_t* config,
    bridge_error_callback_t on_error,
    void* user_data);

void bridge_shutdown(bridge_handle_t handle);

int32_t bridge_is_ready(bridge_handle_t handle);

int32_t bridge_get_last_error(bridge_handle_t handle, char* out, int32_t size);

/* --- Camera --- */
int32_t bridge_update_camera(bridge_handle_t handle, const bridge_camera_t* camera);

int32_t bridge_register_camera_callback(
    bridge_handle_t handle,
    bridge_camera_changed_callback_t callback,
    void* user_data);

/* --- Tile retrieval --- */
int32_t bridge_get_visible_tile_count(bridge_handle_t handle, int32_t* out_count);

int32_t bridge_get_visible_tile_id(bridge_handle_t handle, int32_t index, char** out_tile_id);

int32_t bridge_request_tile_data(
    bridge_handle_t handle,
    const char* tile_id,
    bridge_tile_ready_callback_t callback,
    void* user_data);

void bridge_free_string(char* str);

/* --- Coordinate transforms (pure math, no handle needed) --- */
int32_t bridge_cartographic_to_ecef(
    double lat_deg,
    double lng_deg,
    double alt_m,
    double* out_x,
    double* out_y,
    double* out_z);

int32_t bridge_ecef_to_cartographic(
    double x,
    double y,
    double z,
    double* out_lat_deg,
    double* out_lng_deg,
    double* out_alt_m);

#ifdef __cplusplus
}
#endif

#endif /* CESIUM_NATIVE_BRIDGE_H */
