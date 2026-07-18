#include "../../src/flutter_mimc_bridge.h"

#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>

namespace {

std::string Poll() {
  char event[4096]{};
  const int length = flutter_mimc_poll_event(event, sizeof(event));
  assert(length > 0);
  return std::string(event, static_cast<size_t>(length));
}

}  // namespace

int main() {
  assert(flutter_mimc_is_sdk_linked() == 1);
  const uint64_t capabilities = flutter_mimc_get_capabilities();
  assert((capabilities & FLUTTER_MIMC_CAP_MESSAGE) != 0);
  assert((capabilities & FLUTTER_MIMC_CAP_GROUP_MESSAGE) != 0);
  assert((capabilities & FLUTTER_MIMC_CAP_ONLINE_MESSAGE) != 0);
  assert((capabilities & FLUTTER_MIMC_CAP_REALTIME_STREAM) != 0);
  assert((capabilities & FLUTTER_MIMC_CAP_OFFLINE_PULL) == 0);
  assert((capabilities & FLUTTER_MIMC_CAP_REALTIME_CHANNEL) == 0);

  const std::string oversized_token(2048, 'x');
  assert(flutter_mimc_initialize(123, "alice", "desktop", "",
                                 oversized_token.c_str(), 1) ==
         FLUTTER_MIMC_INVALID_ARGUMENT);
  assert(std::string(flutter_mimc_last_error()).find("2047-byte") !=
         std::string::npos);
  assert(flutter_mimc_initialize(123, "alice", "desktop", "",
                                R"({"code":200})", 1) == FLUTTER_MIMC_OK);
  assert(flutter_mimc_update_token(oversized_token.c_str()) ==
         FLUTTER_MIMC_INVALID_ARGUMENT);
  assert(flutter_mimc_update_token(R"({"code":200,"refreshed":true})") ==
         FLUTTER_MIMC_OK);
  assert(flutter_mimc_login() == FLUTTER_MIMC_OK);
  assert(Poll().find("connecting") != std::string::npos);
  assert(Poll().find("online") != std::string::npos);
  assert(flutter_mimc_is_online() == 1);

  const uint8_t payload[] = {0, 255};
  char packet_id[128]{};
  assert(flutter_mimc_send_message("bob", payload, 2, "test", 1, packet_id,
                                  sizeof(packet_id)) == FLUTTER_MIMC_OK);
  assert(std::strcmp(packet_id, "direct-1") == 0);
  assert(Poll().find("\"payload\":[0,255]") != std::string::npos);
  assert(Poll().find("serverAck") != std::string::npos);

  assert(flutter_mimc_set_rts_incoming_call_policy(1, "ready") ==
         FLUTTER_MIMC_OK);
  assert(flutter_mimc_configure_rts_stream(0, 0, 200, 1) ==
         FLUTTER_MIMC_OK);
  assert(flutter_mimc_configure_rts_buffers(4096, 8192) == FLUTTER_MIMC_OK);
  int32_t send_size = 0;
  int32_t receive_size = 0;
  float send_usage = 0;
  float receive_usage = 0;
  assert(flutter_mimc_get_rts_buffer_state(
             &send_size, &receive_size, &send_usage, &receive_usage) ==
         FLUTTER_MIMC_OK);
  assert(send_size == 4096 && receive_size == 8192);
  assert(send_usage == 0.25F && receive_usage == 0.5F);

  int64_t call_id = 0;
  const uint8_t app_content[] = {1, 2};
  assert(flutter_mimc_dial_rts_call("bob", "phone", app_content, 2,
                                   &call_id) == FLUTTER_MIMC_OK);
  assert(call_id == 42);
  const std::string incoming = Poll();
  assert(incoming.find("rtsCallIncoming") != std::string::npos);
  assert(incoming.find("\"appContent\":[1,2]") != std::string::npos);
  assert(incoming.find("\"accepted\":true") != std::string::npos);
  assert(Poll().find("rtsCallAnswered") != std::string::npos);
  assert(Poll().find("rtsP2pResult") != std::string::npos);

  int32_t data_id = -1;
  const uint8_t rts_payload[] = {3, 0, 255};
  assert(flutter_mimc_send_rts_data(call_id, rts_payload, 3, 1, 0, 1, 2, 0,
                                   "frame-1", &data_id) == FLUTTER_MIMC_OK);
  assert(data_id == 7);
  const std::string data_event = Poll();
  assert(data_event.find("rtsData") != std::string::npos);
  assert(data_event.find("\"payload\":[3,0,255]") != std::string::npos);
  assert(data_event.find("\"dataType\":\"video\"") != std::string::npos);
  assert(Poll().find("\"context\":\"frame-1\"") != std::string::npos);
  assert(flutter_mimc_close_rts_call(call_id, "done") == FLUTTER_MIMC_OK);
  assert(Poll().find("rtsCallClosed") != std::string::npos);
  assert(flutter_mimc_clear_rts_buffers() == FLUTTER_MIMC_OK);

  assert(flutter_mimc_logout() == FLUTTER_MIMC_OK);
  assert(Poll().find("offline") != std::string::npos);
  flutter_mimc_dispose();
  assert(flutter_mimc_is_online() == 0);
  std::cout << "native bridge test passed\n";
  return 0;
}
