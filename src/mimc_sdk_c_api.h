#ifndef FLUTTER_MIMC_SDK_C_API_H_
#define FLUTTER_MIMC_SDK_C_API_H_

// ABI subset of Xiaomi mimc-cpp-sdk/include/mimc/user_c.h.
// Keeping this local declaration means the Flutter bridge can load an SDK
// shared library at runtime without forcing the SDK's legacy build system on
// every Flutter application.

#include <stdbool.h>
#include <stdint.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { MIMC_SDK_OFFLINE, MIMC_SDK_ONLINE } mimc_sdk_online_status_t;
typedef enum { MIMC_SDK_STREAM_FEC, MIMC_SDK_STREAM_ACK }
    mimc_sdk_stream_type_t;
typedef enum { MIMC_SDK_AUDIO, MIMC_SDK_VIDEO, MIMC_SDK_FILE }
    mimc_sdk_data_type_t;
typedef enum {
  MIMC_SDK_RELAY,
  MIMC_SDK_P2P_INTRANET,
  MIMC_SDK_P2P_INTERNET,
  MIMC_SDK_CHANNEL_AUTO,
} mimc_sdk_channel_type_t;
typedef enum { MIMC_SDK_P0, MIMC_SDK_P1, MIMC_SDK_P2 }
    mimc_sdk_data_priority_t;

typedef struct {
  void* value;
  void* token_fetcher;
  void* online_status_handler;
  void* rtscall_event_handler;
  void* message_handler;
} mimc_sdk_user_t;

typedef struct {
  mimc_sdk_stream_type_t type;
  unsigned int ackstream_waittime_ms;
  bool is_encrypt;
} mimc_sdk_stream_config_t;

typedef struct {
  bool accepted;
  const char* desc;
} mimc_sdk_launched_response_t;

typedef struct {
  const char* packetid;
  int64_t sequence;
  const char* from_account;
  const char* from_resource;
  const char* to_account;
  const char* to_resource;
  const char* payload;
  int payload_len;
  const char* biz_type;
  time_t timestamp;
} mimc_sdk_message_t;

typedef struct {
  const char* packetid;
  int64_t sequence;
  time_t timestamp;
  const char* from_account;
  const char* from_resource;
  uint64_t topicid;
  const char* payload;
  int payload_len;
  const char* biz_type;
} mimc_sdk_group_message_t;

typedef struct {
  void (*status_change)(mimc_sdk_online_status_t online_status,
                        const char* type,
                        const char* reason,
                        const char* desc);
} mimc_sdk_online_status_handler_t;

typedef struct {
  mimc_sdk_launched_response_t (*on_launched)(uint64_t call_id,
                                               const char* from_account,
                                               const char* app_content,
                                               int app_content_length,
                                               const char* from_resource);
  void (*on_answered)(uint64_t call_id, bool accepted, const char* description);
  void (*on_closed)(uint64_t call_id, const char* description);
  void (*on_data)(uint64_t call_id,
                  const char* from_account,
                  const char* resource,
                  const char* data,
                  int data_length,
                  mimc_sdk_data_type_t data_type,
                  mimc_sdk_channel_type_t channel_type);
  void (*on_send_data_success)(uint64_t call_id,
                               int data_id,
                               const char* context,
                               int context_length);
  void (*on_send_data_failure)(uint64_t call_id,
                               int data_id,
                               const char* context,
                               int context_length);
  void (*on_p2p_result)(uint64_t call_id,
                        int result,
                        int self_nat_type,
                        int peer_nat_type);
} mimc_sdk_rtscall_event_handler_t;

typedef struct {
  void (*handle_message)(const mimc_sdk_message_t* packets,
                         uint64_t packets_length);
  void (*handle_group_message)(const mimc_sdk_group_message_t* packets,
                               uint64_t packets_length);
  void (*handle_server_ack)(const char* packet_id,
                            int64_t sequence,
                            time_t timestamp,
                            const char* description);
  void (*handle_send_msg_timeout)(const mimc_sdk_message_t* message);
  void (*handle_send_group_msg_timeout)(
      const mimc_sdk_group_message_t* message);
  void (*handle_online_message)(const mimc_sdk_message_t* message);
} mimc_sdk_message_handler_t;

typedef void (*mimc_sdk_fetch_token_t)(void* args,
                                        char* output,
                                        int output_length);
typedef void (*mimc_sdk_free_args_t)(void* args);

void mimc_init(mimc_sdk_user_t* user,
               int64_t app_id,
               const char* app_account,
               const char* resource,
               bool save_cache,
               const char* cache_path);
void mimc_fini(mimc_sdk_user_t* user);
void mimc_register_token_fetcher(mimc_sdk_user_t* user,
                                 void* args,
                                 mimc_sdk_fetch_token_t fetch_token,
                                 mimc_sdk_free_args_t free_args);
void mimc_register_online_status_handler(
    mimc_sdk_user_t* user,
    const mimc_sdk_online_status_handler_t* handler);
void mimc_register_message_handler(mimc_sdk_user_t* user,
                                   const mimc_sdk_message_handler_t* handler);
void mimc_rtc_register_rtscall_event_handler(
    mimc_sdk_user_t* user,
    const mimc_sdk_rtscall_event_handler_t* handler);
bool mimc_login(mimc_sdk_user_t* user);
bool mimc_logout(mimc_sdk_user_t* user);
bool mimc_isonline(mimc_sdk_user_t* user);
void mimc_send_message(mimc_sdk_user_t* user,
                       const char* to_account,
                       const char* payload,
                       int payload_length,
                       const char* biz_type,
                       bool store,
                       char* result,
                       int result_length);
void mimc_send_group_message(mimc_sdk_user_t* user,
                             int64_t topic_id,
                             const char* payload,
                             int payload_length,
                             const char* biz_type,
                             bool store,
                             char* result,
                             int result_length);
void mimc_send_online_message(mimc_sdk_user_t* user,
                              const char* to_account,
                              const char* payload,
                              int payload_length,
                              const char* biz_type,
                              bool store,
                              char* result,
                              int result_length);
void mimc_enable_p2p(mimc_sdk_user_t* user, bool enable);
void mimc_rtc_init_audiostream_config(
    mimc_sdk_user_t* user,
    const mimc_sdk_stream_config_t* stream_config);
void mimc_rtc_init_videostream_config(
    mimc_sdk_user_t* user,
    const mimc_sdk_stream_config_t* stream_config);
void mimc_rtc_set_sendbuffer_size(mimc_sdk_user_t* user, int size);
void mimc_rtc_set_recvbuffer_size(mimc_sdk_user_t* user, int size);
int mimc_rtc_get_sendbuffer_size(mimc_sdk_user_t* user);
int mimc_rtc_get_recvbuffer_size(mimc_sdk_user_t* user);
float mimc_rtc_get_sendbuffer_usagerate(mimc_sdk_user_t* user);
float mimc_rtc_get_recvbuffer_usagerate(mimc_sdk_user_t* user);
void mimc_rtc_clear_sendbuffer(mimc_sdk_user_t* user);
void mimc_rtc_clear_recvbuffer(mimc_sdk_user_t* user);
uint64_t mimc_rtc_dial_call(mimc_sdk_user_t* user,
                            const char* to_account,
                            const char* app_content,
                            int app_content_length,
                            const char* to_resource);
void mimc_rtc_close_call(mimc_sdk_user_t* user,
                         uint64_t call_id,
                         const char* reason);
int mimc_rtc_send_data(mimc_sdk_user_t* user,
                       uint64_t call_id,
                       const char* data,
                       int data_length,
                       mimc_sdk_data_type_t data_type,
                       mimc_sdk_channel_type_t channel_type,
                       const char* context,
                       int context_length,
                       bool can_be_dropped,
                       mimc_sdk_data_priority_t priority,
                       unsigned int resend_count);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_MIMC_SDK_C_API_H_
