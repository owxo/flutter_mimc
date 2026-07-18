#include "../../src/mimc_sdk_c_api.h"

#include <cstdio>
#include <cstring>

namespace {

mimc_sdk_fetch_token_t g_fetch_token = nullptr;
mimc_sdk_free_args_t g_free_args = nullptr;
void* g_token_args = nullptr;
mimc_sdk_online_status_handler_t g_status_handler{};
mimc_sdk_message_handler_t g_message_handler{};
mimc_sdk_rtscall_event_handler_t g_rts_handler{};
bool g_online = false;
int g_send_buffer_size = 1024;
int g_receive_buffer_size = 2048;

void CopyPacketId(const char* value, char* output, int output_length) {
  if (output != nullptr && output_length > 0) {
    std::snprintf(output, static_cast<size_t>(output_length), "%s", value);
  }
}

}  // namespace

extern "C" {

void mimc_init(mimc_sdk_user_t* user,
               int64_t,
               const char*,
               const char*,
               bool,
               const char*) {
  user->value = user;
}

void mimc_fini(mimc_sdk_user_t* user) {
  if (g_free_args != nullptr) {
    g_free_args(g_token_args);
  }
  user->value = nullptr;
}

void mimc_register_token_fetcher(mimc_sdk_user_t*,
                                 void* args,
                                 mimc_sdk_fetch_token_t fetch_token,
                                 mimc_sdk_free_args_t free_args) {
  g_token_args = args;
  g_fetch_token = fetch_token;
  g_free_args = free_args;
}

void mimc_register_online_status_handler(
    mimc_sdk_user_t*,
    const mimc_sdk_online_status_handler_t* handler) {
  g_status_handler = *handler;
}

void mimc_register_message_handler(mimc_sdk_user_t*,
                                   const mimc_sdk_message_handler_t* handler) {
  g_message_handler = *handler;
}

void mimc_rtc_register_rtscall_event_handler(
    mimc_sdk_user_t*,
    const mimc_sdk_rtscall_event_handler_t* handler) {
  g_rts_handler = *handler;
}

bool mimc_login(mimc_sdk_user_t*) {
  char token[2048]{};
  g_fetch_token(g_token_args, token, sizeof(token));
  if (token[0] == '\0') {
    return false;
  }
  g_online = true;
  g_status_handler.status_change(MIMC_SDK_ONLINE, "login", "", "ok");
  return true;
}

bool mimc_logout(mimc_sdk_user_t*) {
  g_online = false;
  g_status_handler.status_change(MIMC_SDK_OFFLINE, "logout", "", "ok");
  return true;
}

bool mimc_isonline(mimc_sdk_user_t*) { return g_online; }

void mimc_send_message(mimc_sdk_user_t*,
                       const char* to_account,
                       const char* payload,
                       int payload_length,
                       const char* biz_type,
                       bool,
                       char* result,
                       int result_length) {
  CopyPacketId("direct-1", result, result_length);
  mimc_sdk_message_t message{"direct-1", 7,  "alice", "desktop", to_account,
                             "",         payload, payload_length, biz_type, 99};
  g_message_handler.handle_message(&message, 1);
  g_message_handler.handle_server_ack("direct-1", 7, 99, "ok");
}

void mimc_send_group_message(mimc_sdk_user_t*,
                             int64_t topic_id,
                             const char* payload,
                             int payload_length,
                             const char* biz_type,
                             bool,
                             char* result,
                             int result_length) {
  CopyPacketId("group-1", result, result_length);
  mimc_sdk_group_message_t message{"group-1", 8,       100, "alice", "desktop",
                                   static_cast<uint64_t>(topic_id), payload,
                                   payload_length, biz_type};
  g_message_handler.handle_group_message(&message, 1);
}

void mimc_send_online_message(mimc_sdk_user_t*,
                              const char*,
                              const char*,
                              int,
                              const char*,
                              bool,
                              char* result,
                              int result_length) {
  CopyPacketId("online-1", result, result_length);
}

void mimc_enable_p2p(mimc_sdk_user_t*, bool) {}

void mimc_rtc_init_audiostream_config(mimc_sdk_user_t*,
                                      const mimc_sdk_stream_config_t*) {}

void mimc_rtc_init_videostream_config(mimc_sdk_user_t*,
                                      const mimc_sdk_stream_config_t*) {}

void mimc_rtc_set_sendbuffer_size(mimc_sdk_user_t*, int size) {
  g_send_buffer_size = size;
}

void mimc_rtc_set_recvbuffer_size(mimc_sdk_user_t*, int size) {
  g_receive_buffer_size = size;
}

int mimc_rtc_get_sendbuffer_size(mimc_sdk_user_t*) {
  return g_send_buffer_size;
}

int mimc_rtc_get_recvbuffer_size(mimc_sdk_user_t*) {
  return g_receive_buffer_size;
}

float mimc_rtc_get_sendbuffer_usagerate(mimc_sdk_user_t*) { return 0.25F; }

float mimc_rtc_get_recvbuffer_usagerate(mimc_sdk_user_t*) { return 0.5F; }

void mimc_rtc_clear_sendbuffer(mimc_sdk_user_t*) {}

void mimc_rtc_clear_recvbuffer(mimc_sdk_user_t*) {}

uint64_t mimc_rtc_dial_call(mimc_sdk_user_t*,
                            const char*,
                            const char* app_content,
                            int app_content_length,
                            const char*) {
  g_rts_handler.on_launched(43, "bob", app_content, app_content_length,
                            "phone");
  g_rts_handler.on_answered(42, true, "accepted");
  g_rts_handler.on_p2p_result(42, 0, 1, 2);
  return 42;
}

void mimc_rtc_close_call(mimc_sdk_user_t*, uint64_t call_id, const char* reason) {
  g_rts_handler.on_closed(call_id, reason);
}

int mimc_rtc_send_data(mimc_sdk_user_t*,
                       uint64_t call_id,
                       const char* data,
                       int data_length,
                       mimc_sdk_data_type_t data_type,
                       mimc_sdk_channel_type_t channel_type,
                       const char* context,
                       int context_length,
                       bool,
                       mimc_sdk_data_priority_t,
                       unsigned int) {
  g_rts_handler.on_data(call_id, "bob", "phone", data, data_length, data_type,
                        channel_type);
  g_rts_handler.on_send_data_success(call_id, 7, context, context_length);
  return 7;
}

}  // extern "C"
