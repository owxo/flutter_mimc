#ifndef FLUTTER_MIMC_BRIDGE_H_
#define FLUTTER_MIMC_BRIDGE_H_

#include <stdint.h>

#if defined(_WIN32)
#if defined(FLUTTER_MIMC_SHARED_LIBRARY)
#define FLUTTER_MIMC_EXPORT __declspec(dllexport)
#else
#define FLUTTER_MIMC_EXPORT __declspec(dllimport)
#endif
#else
#define FLUTTER_MIMC_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum flutter_mimc_result {
  FLUTTER_MIMC_OK = 0,
  FLUTTER_MIMC_INVALID_ARGUMENT = 1,
  FLUTTER_MIMC_NOT_INITIALIZED = 2,
  FLUTTER_MIMC_BUFFER_TOO_SMALL = 3,
  FLUTTER_MIMC_SDK_UNAVAILABLE = 1001,
  FLUTTER_MIMC_INTERNAL_ERROR = 1002,
};

enum flutter_mimc_capability {
  FLUTTER_MIMC_CAP_MESSAGE = 1 << 0,
  FLUTTER_MIMC_CAP_GROUP_MESSAGE = 1 << 1,
  FLUTTER_MIMC_CAP_ONLINE_MESSAGE = 1 << 2,
  FLUTTER_MIMC_CAP_UNLIMITED_GROUP = 1 << 3,
  FLUTTER_MIMC_CAP_OFFLINE_PULL = 1 << 4,
  FLUTTER_MIMC_CAP_REALTIME_STREAM = 1 << 5,
  FLUTTER_MIMC_CAP_REALTIME_CHANNEL = 1 << 6,
};

FLUTTER_MIMC_EXPORT const char* flutter_mimc_native_version(void);
FLUTTER_MIMC_EXPORT const char* flutter_mimc_last_error(void);
FLUTTER_MIMC_EXPORT uint8_t flutter_mimc_is_sdk_linked(void);
FLUTTER_MIMC_EXPORT uint64_t flutter_mimc_get_capabilities(void);

FLUTTER_MIMC_EXPORT int32_t flutter_mimc_initialize(
    int64_t app_id,
    const char* app_account,
    const char* resource,
    const char* cache_directory,
    const char* token,
    uint8_t debug);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_update_token(const char* token);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_login(void);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_logout(void);
FLUTTER_MIMC_EXPORT uint8_t flutter_mimc_is_online(void);

FLUTTER_MIMC_EXPORT int32_t flutter_mimc_send_message(
    const char* to_account,
    const uint8_t* payload,
    int32_t payload_length,
    const char* biz_type,
    uint8_t store,
    char* packet_id,
    int32_t packet_id_capacity);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_send_group_message(
    int64_t topic_id,
    const uint8_t* payload,
    int32_t payload_length,
    const char* biz_type,
    uint8_t store,
    char* packet_id,
    int32_t packet_id_capacity);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_send_online_message(
    const char* to_account,
    const uint8_t* payload,
    int32_t payload_length,
    const char* biz_type,
    uint8_t store,
    char* packet_id,
    int32_t packet_id_capacity);

FLUTTER_MIMC_EXPORT int32_t flutter_mimc_set_rts_incoming_call_policy(
    uint8_t accepted,
    const char* description);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_configure_rts_stream(
    int32_t data_type,
    int32_t strategy,
    int32_t ack_wait_time_ms,
    uint8_t encrypt);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_configure_rts_buffers(
    int32_t send_size,
    int32_t receive_size);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_get_rts_buffer_state(
    int32_t* send_size,
    int32_t* receive_size,
    float* send_usage_rate,
    float* receive_usage_rate);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_clear_rts_buffers(void);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_dial_rts_call(
    const char* to_account,
    const char* to_resource,
    const uint8_t* app_content,
    int32_t app_content_length,
    int64_t* call_id);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_close_rts_call(
    int64_t call_id,
    const char* reason);
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_send_rts_data(
    int64_t call_id,
    const uint8_t* payload,
    int32_t payload_length,
    int32_t data_type,
    int32_t priority,
    uint8_t can_be_dropped,
    uint32_t resend_count,
    int32_t channel_type,
    const char* context,
    int32_t* data_id);

// Returns 0 when no event is queued, a positive byte count when an event was
// copied, or the required capacity as a negative number when the buffer is too
// small. Events are UTF-8 JSON maps matching MimcEvent.fromMap.
FLUTTER_MIMC_EXPORT int32_t flutter_mimc_poll_event(
    char* event_json,
    int32_t event_json_capacity);

FLUTTER_MIMC_EXPORT void flutter_mimc_dispose(void);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_MIMC_BRIDGE_H_
