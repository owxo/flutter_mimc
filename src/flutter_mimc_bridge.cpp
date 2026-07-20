#include "flutter_mimc_bridge.h"

#include "mimc_sdk_c_api.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace {

struct MimcSdkApi {
  decltype(&mimc_init) init = nullptr;
  decltype(&mimc_fini) fini = nullptr;
  decltype(&mimc_register_token_fetcher) register_token_fetcher = nullptr;
  decltype(&mimc_register_online_status_handler)
      register_online_status_handler = nullptr;
  decltype(&mimc_register_message_handler) register_message_handler = nullptr;
  decltype(&mimc_rtc_register_rtscall_event_handler)
      register_rtscall_event_handler = nullptr;
  decltype(&mimc_login) login = nullptr;
  decltype(&mimc_logout) logout = nullptr;
  decltype(&mimc_isonline) is_online = nullptr;
  decltype(&mimc_send_message) send_message = nullptr;
  decltype(&mimc_send_group_message) send_group_message = nullptr;
  decltype(&mimc_send_online_message) send_online_message = nullptr;
  decltype(&mimc_enable_p2p) enable_p2p = nullptr;
  decltype(&mimc_rtc_init_audiostream_config) init_audio_stream = nullptr;
  decltype(&mimc_rtc_init_videostream_config) init_video_stream = nullptr;
  decltype(&mimc_rtc_set_sendbuffer_size) set_send_buffer_size = nullptr;
  decltype(&mimc_rtc_set_recvbuffer_size) set_receive_buffer_size = nullptr;
  decltype(&mimc_rtc_get_sendbuffer_size) get_send_buffer_size = nullptr;
  decltype(&mimc_rtc_get_recvbuffer_size) get_receive_buffer_size = nullptr;
  decltype(&mimc_rtc_get_sendbuffer_usagerate) get_send_buffer_usage = nullptr;
  decltype(&mimc_rtc_get_recvbuffer_usagerate) get_receive_buffer_usage = nullptr;
  decltype(&mimc_rtc_clear_sendbuffer) clear_send_buffer = nullptr;
  decltype(&mimc_rtc_clear_recvbuffer) clear_receive_buffer = nullptr;
  decltype(&mimc_rtc_dial_call) dial_call = nullptr;
  decltype(&mimc_rtc_close_call) close_call = nullptr;
  decltype(&mimc_rtc_send_data) send_rts_data = nullptr;
};

std::mutex g_state_mutex;
std::mutex g_sdk_call_mutex;
std::mutex g_loader_mutex;
std::deque<std::string> g_events;
std::string g_last_error;
std::string g_token;
std::atomic<bool> g_initialized{false};
std::atomic<bool> g_online{false};
std::atomic<bool> g_accept_incoming_rts_calls{false};
std::string g_incoming_rts_description = "Rejected by application policy";
mimc_sdk_user_t g_user{};
MimcSdkApi g_sdk;
bool g_sdk_loaded = false;

#if defined(_WIN32)
HMODULE g_sdk_library = nullptr;
#else
void* g_sdk_library = nullptr;
#endif

int32_t Fail(int32_t code, const std::string& message) {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  g_last_error = message;
  return code;
}

void ClearError() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  g_last_error.clear();
}

bool IsEmpty(const char* value) { return value == nullptr || value[0] == '\0'; }

// Xiaomi's C adapter allocates a fixed 2 KiB token buffer in TokenFetcher.
// Reject longer responses instead of letting the SDK silently truncate JSON.
constexpr size_t kMaximumSdkTokenBytes = 2047;

bool IsTokenTooLong(const char* token) {
  return token != nullptr && std::strlen(token) > kMaximumSdkTokenBytes;
}

const char* Safe(const char* value) { return value == nullptr ? "" : value; }

std::string JsonString(const std::string& value) {
  std::ostringstream output;
  output << '"';
  for (const unsigned char character : value) {
    switch (character) {
      case '"':
        output << "\\\"";
        break;
      case '\\':
        output << "\\\\";
        break;
      case '\b':
        output << "\\b";
        break;
      case '\f':
        output << "\\f";
        break;
      case '\n':
        output << "\\n";
        break;
      case '\r':
        output << "\\r";
        break;
      case '\t':
        output << "\\t";
        break;
      default:
        if (character < 0x20) {
          output << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                 << static_cast<int>(character) << std::dec;
        } else {
          output << character;
        }
    }
  }
  output << '"';
  return output.str();
}

std::string JsonString(const char* value) {
  return JsonString(std::string(Safe(value)));
}

std::string JsonPayload(const char* payload, int length) {
  std::ostringstream output;
  output << '[';
  if (payload != nullptr && length > 0) {
    for (int index = 0; index < length; ++index) {
      if (index != 0) {
        output << ',';
      }
      output << static_cast<unsigned int>(
          static_cast<unsigned char>(payload[index]));
    }
  }
  output << ']';
  return output.str();
}

void PushEvent(std::string event) {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  g_events.push_back(std::move(event));
}

std::string MessageJson(const mimc_sdk_message_t& message,
                        const char* channel) {
  std::ostringstream output;
  output << "{\"packetId\":" << JsonString(message.packetid)
         << ",\"sequence\":" << message.sequence
         << ",\"timestamp\":" << static_cast<int64_t>(message.timestamp)
         << ",\"fromAccount\":" << JsonString(message.from_account)
         << ",\"fromResource\":" << JsonString(message.from_resource)
         << ",\"toAccount\":" << JsonString(message.to_account)
         << ",\"toResource\":" << JsonString(message.to_resource)
         << ",\"payload\":" << JsonPayload(message.payload, message.payload_len)
         << ",\"bizType\":" << JsonString(message.biz_type)
         << ",\"channel\":" << JsonString(channel) << '}';
  return output.str();
}

std::string GroupMessageJson(const mimc_sdk_group_message_t& message) {
  std::ostringstream output;
  output << "{\"packetId\":" << JsonString(message.packetid)
         << ",\"sequence\":" << message.sequence
         << ",\"timestamp\":" << static_cast<int64_t>(message.timestamp)
         << ",\"fromAccount\":" << JsonString(message.from_account)
         << ",\"fromResource\":" << JsonString(message.from_resource)
         << ",\"topicId\":" << message.topicid
         << ",\"payload\":" << JsonPayload(message.payload, message.payload_len)
         << ",\"bizType\":" << JsonString(message.biz_type)
         << ",\"channel\":\"group\"}";
  return output.str();
}

void FetchToken(void*, char* output, int output_length) {
  if (output == nullptr || output_length <= 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_state_mutex);
  std::snprintf(output, static_cast<size_t>(output_length), "%s",
                g_token.c_str());
}

void FreeTokenArgs(void*) {}

void StatusChanged(mimc_sdk_online_status_t status,
                   const char* type,
                   const char* reason,
                   const char* description) {
  const bool online = status == MIMC_SDK_ONLINE;
  g_online.store(online);
  std::ostringstream event;
  event << "{\"type\":\"connectionChanged\",\"data\":{\"state\":"
        << JsonString(online ? "online" : "offline")
        << ",\"reason\":" << JsonString(reason)
        << ",\"description\":" << JsonString(description)
        << ",\"sdkType\":" << JsonString(type) << "}}";
  PushEvent(event.str());

  std::string failure = std::string(Safe(type)) + ' ' + Safe(reason) + ' ' +
                        Safe(description);
  for (char& character : failure) {
    if (character >= 'A' && character <= 'Z') {
      character = static_cast<char>(character - 'A' + 'a');
    }
  }
  if (failure.find("token") != std::string::npos) {
    PushEvent("{\"type\":\"tokenRefreshRequired\",\"data\":{}}");
  }
}

void HandleMessages(const mimc_sdk_message_t* packets, uint64_t length) {
  if (packets == nullptr) {
    return;
  }
  for (uint64_t index = 0; index < length; ++index) {
    PushEvent("{\"type\":\"message\",\"data\":" +
              MessageJson(packets[index], "direct") + '}');
  }
}

void HandleGroupMessages(const mimc_sdk_group_message_t* packets,
                         uint64_t length) {
  if (packets == nullptr) {
    return;
  }
  for (uint64_t index = 0; index < length; ++index) {
    PushEvent("{\"type\":\"groupMessage\",\"data\":" +
              GroupMessageJson(packets[index]) + '}');
  }
}

void HandleServerAck(const char* packet_id,
                     int64_t sequence,
                     time_t timestamp,
                     const char* description) {
  std::ostringstream event;
  event << "{\"type\":\"serverAck\",\"data\":{\"packetId\":"
        << JsonString(packet_id) << ",\"sequence\":" << sequence
        << ",\"timestamp\":" << static_cast<int64_t>(timestamp)
        << ",\"description\":" << JsonString(description) << "}}";
  PushEvent(event.str());
}

void HandleSendTimeout(const mimc_sdk_message_t* message) {
  if (message != nullptr) {
    PushEvent("{\"type\":\"sendMessageTimeout\",\"data\":" +
              MessageJson(*message, "direct") + '}');
  }
}

void HandleGroupSendTimeout(const mimc_sdk_group_message_t* message) {
  if (message != nullptr) {
    PushEvent("{\"type\":\"sendGroupMessageTimeout\",\"data\":" +
              GroupMessageJson(*message) + '}');
  }
}

void HandleOnlineMessage(const mimc_sdk_message_t* message) {
  if (message != nullptr) {
    PushEvent("{\"type\":\"onlineMessage\",\"data\":" +
              MessageJson(*message, "online") + '}');
  }
}

const char* RtsDataTypeName(mimc_sdk_data_type_t type) {
  return type == MIMC_SDK_VIDEO ? "video" : "audio";
}

const char* RtsChannelTypeName(mimc_sdk_channel_type_t type) {
  switch (type) {
    case MIMC_SDK_RELAY:
      return "relay";
    case MIMC_SDK_P2P_INTERNET:
      return "p2pInternet";
    case MIMC_SDK_P2P_INTRANET:
      return "p2pIntranet";
    case MIMC_SDK_CHANNEL_AUTO:
      return "automatic";
  }
  return "automatic";
}

mimc_sdk_launched_response_t HandleRtsLaunched(uint64_t call_id,
                                                const char* from_account,
                                                const char* app_content,
                                                int app_content_length,
                                                const char* from_resource) {
  const bool accepted = g_accept_incoming_rts_calls.load();
  static thread_local std::string response_description;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    response_description = g_incoming_rts_description;
  }
  std::ostringstream event;
  event << "{\"type\":\"rtsCallIncoming\",\"data\":{\"callId\":" << call_id
        << ",\"fromAccount\":" << JsonString(from_account)
        << ",\"fromResource\":" << JsonString(from_resource)
        << ",\"appContent\":" << JsonPayload(app_content, app_content_length)
        << ",\"accepted\":" << (accepted ? "true" : "false") << "}}";
  PushEvent(event.str());
  return {accepted, response_description.c_str()};
}

void HandleRtsAnswered(uint64_t call_id,
                       bool accepted,
                       const char* description) {
  std::ostringstream event;
  event << "{\"type\":\"rtsCallAnswered\",\"data\":{\"callId\":" << call_id
        << ",\"accepted\":" << (accepted ? "true" : "false")
        << ",\"description\":" << JsonString(description) << "}}";
  PushEvent(event.str());
}

void HandleRtsClosed(uint64_t call_id, const char* description) {
  std::ostringstream event;
  event << "{\"type\":\"rtsCallClosed\",\"data\":{\"callId\":" << call_id
        << ",\"description\":" << JsonString(description) << "}}";
  PushEvent(event.str());
}

void HandleRtsData(uint64_t call_id,
                   const char* from_account,
                   const char* resource,
                   const char* data,
                   int data_length,
                   mimc_sdk_data_type_t data_type,
                   mimc_sdk_channel_type_t channel_type) {
  std::ostringstream event;
  event << "{\"type\":\"rtsData\",\"data\":{\"callId\":" << call_id
        << ",\"fromAccount\":" << JsonString(from_account)
        << ",\"fromResource\":" << JsonString(resource)
        << ",\"payload\":" << JsonPayload(data, data_length)
        << ",\"dataType\":" << JsonString(RtsDataTypeName(data_type))
        << ",\"channelType\":" << JsonString(RtsChannelTypeName(channel_type))
        << "}}";
  PushEvent(event.str());
}

std::string RtsContext(const char* context, int context_length) {
  if (context == nullptr || context_length <= 0) return {};
  return std::string(context, static_cast<size_t>(context_length));
}

void PushRtsSendResult(uint64_t call_id,
                       int data_id,
                       bool success,
                       const char* context,
                       int context_length) {
  std::ostringstream event;
  event << "{\"type\":\"rtsSendData\",\"data\":{\"callId\":" << call_id
        << ",\"dataId\":" << data_id
        << ",\"success\":" << (success ? "true" : "false")
        << ",\"context\":" << JsonString(RtsContext(context, context_length))
        << "}}";
  PushEvent(event.str());
}

void HandleRtsSendSuccess(uint64_t call_id,
                          int data_id,
                          const char* context,
                          int context_length) {
  PushRtsSendResult(call_id, data_id, true, context, context_length);
}

void HandleRtsSendFailure(uint64_t call_id,
                          int data_id,
                          const char* context,
                          int context_length) {
  PushRtsSendResult(call_id, data_id, false, context, context_length);
}

void HandleRtsP2pResult(uint64_t call_id,
                        int result,
                        int self_nat_type,
                        int peer_nat_type) {
  std::ostringstream event;
  event << "{\"type\":\"rtsP2pResult\",\"data\":{\"callId\":" << call_id
        << ",\"result\":" << result << ",\"selfNatType\":" << self_nat_type
        << ",\"peerNatType\":" << peer_nat_type << "}}";
  PushEvent(event.str());
}

const mimc_sdk_online_status_handler_t kOnlineStatusHandler = {
    &StatusChanged,
};

const mimc_sdk_message_handler_t kMessageHandler = {
    &HandleMessages,         &HandleGroupMessages, &HandleServerAck,
    &HandleSendTimeout,      &HandleGroupSendTimeout,
    &HandleOnlineMessage,
};

const mimc_sdk_rtscall_event_handler_t kRtsCallHandler = {
    &HandleRtsLaunched,    &HandleRtsAnswered,   &HandleRtsClosed,
    &HandleRtsData,        &HandleRtsSendSuccess, &HandleRtsSendFailure,
    &HandleRtsP2pResult,
};

#if defined(_WIN32)
template <typename T>
T LoadSymbol(HMODULE library, const char* name) {
  return reinterpret_cast<T>(GetProcAddress(library, name));
}
#else
template <typename T>
T LoadSymbol(void* library, const char* name) {
  return reinterpret_cast<T>(dlsym(library, name));
}
#endif

bool ResolveApi(
#if defined(_WIN32)
    HMODULE library,
#else
    void* library,
#endif
    MimcSdkApi* api) {
  api->init = LoadSymbol<decltype(api->init)>(library, "mimc_init");
  api->fini = LoadSymbol<decltype(api->fini)>(library, "mimc_fini");
  api->register_token_fetcher =
      LoadSymbol<decltype(api->register_token_fetcher)>(
          library, "mimc_register_token_fetcher");
  api->register_online_status_handler =
      LoadSymbol<decltype(api->register_online_status_handler)>(
          library, "mimc_register_online_status_handler");
  api->register_message_handler =
      LoadSymbol<decltype(api->register_message_handler)>(
          library, "mimc_register_message_handler");
  api->register_rtscall_event_handler =
      LoadSymbol<decltype(api->register_rtscall_event_handler)>(
          library, "mimc_rtc_register_rtscall_event_handler");
  api->login = LoadSymbol<decltype(api->login)>(library, "mimc_login");
  api->logout = LoadSymbol<decltype(api->logout)>(library, "mimc_logout");
  api->is_online =
      LoadSymbol<decltype(api->is_online)>(library, "mimc_isonline");
  api->send_message =
      LoadSymbol<decltype(api->send_message)>(library, "mimc_send_message");
  api->send_group_message = LoadSymbol<decltype(api->send_group_message)>(
      library, "mimc_send_group_message");
  api->send_online_message = LoadSymbol<decltype(api->send_online_message)>(
      library, "mimc_send_online_message");
  api->enable_p2p =
      LoadSymbol<decltype(api->enable_p2p)>(library, "mimc_enable_p2p");
  api->init_audio_stream = LoadSymbol<decltype(api->init_audio_stream)>(
      library, "mimc_rtc_init_audiostream_config");
  api->init_video_stream = LoadSymbol<decltype(api->init_video_stream)>(
      library, "mimc_rtc_init_videostream_config");
  api->set_send_buffer_size =
      LoadSymbol<decltype(api->set_send_buffer_size)>(
          library, "mimc_rtc_set_sendbuffer_size");
  api->set_receive_buffer_size =
      LoadSymbol<decltype(api->set_receive_buffer_size)>(
          library, "mimc_rtc_set_recvbuffer_size");
  api->get_send_buffer_size =
      LoadSymbol<decltype(api->get_send_buffer_size)>(
          library, "mimc_rtc_get_sendbuffer_size");
  api->get_receive_buffer_size =
      LoadSymbol<decltype(api->get_receive_buffer_size)>(
          library, "mimc_rtc_get_recvbuffer_size");
  api->get_send_buffer_usage =
      LoadSymbol<decltype(api->get_send_buffer_usage)>(
          library, "mimc_rtc_get_sendbuffer_usagerate");
  api->get_receive_buffer_usage =
      LoadSymbol<decltype(api->get_receive_buffer_usage)>(
          library, "mimc_rtc_get_recvbuffer_usagerate");
  api->clear_send_buffer = LoadSymbol<decltype(api->clear_send_buffer)>(
      library, "mimc_rtc_clear_sendbuffer");
  api->clear_receive_buffer =
      LoadSymbol<decltype(api->clear_receive_buffer)>(
          library, "mimc_rtc_clear_recvbuffer");
  api->dial_call = LoadSymbol<decltype(api->dial_call)>(
      library, "mimc_rtc_dial_call");
  api->close_call = LoadSymbol<decltype(api->close_call)>(
      library, "mimc_rtc_close_call");
  api->send_rts_data = LoadSymbol<decltype(api->send_rts_data)>(
      library, "mimc_rtc_send_data");
  return api->init != nullptr && api->fini != nullptr &&
         api->register_token_fetcher != nullptr &&
         api->register_online_status_handler != nullptr &&
         api->register_message_handler != nullptr && api->login != nullptr &&
         api->logout != nullptr && api->is_online != nullptr &&
         api->send_message != nullptr && api->send_group_message != nullptr &&
         api->send_online_message != nullptr;
}

bool HasRtsApi() {
  return g_sdk.register_rtscall_event_handler != nullptr &&
         g_sdk.enable_p2p != nullptr && g_sdk.init_audio_stream != nullptr &&
         g_sdk.init_video_stream != nullptr &&
         g_sdk.set_send_buffer_size != nullptr &&
         g_sdk.set_receive_buffer_size != nullptr &&
         g_sdk.get_send_buffer_size != nullptr &&
         g_sdk.get_receive_buffer_size != nullptr &&
         g_sdk.get_send_buffer_usage != nullptr &&
         g_sdk.get_receive_buffer_usage != nullptr &&
         g_sdk.clear_send_buffer != nullptr &&
         g_sdk.clear_receive_buffer != nullptr && g_sdk.dial_call != nullptr &&
         g_sdk.close_call != nullptr && g_sdk.send_rts_data != nullptr;
}

bool EnsureSdkLoaded() {
  std::lock_guard<std::mutex> lock(g_loader_mutex);
  if (g_sdk_loaded) {
    return true;
  }

#if defined(_WIN32)
  HMODULE process = GetModuleHandleW(nullptr);
  if (process != nullptr && ResolveApi(process, &g_sdk)) {
    g_sdk_loaded = true;
    return true;
  }
#else
  if (ResolveApi(RTLD_DEFAULT, &g_sdk)) {
    g_sdk_loaded = true;
    return true;
  }
#endif

  std::vector<std::string> candidates;
  const char* configured = std::getenv("FLUTTER_MIMC_CPP_SDK_LIBRARY");
  if (!IsEmpty(configured)) {
    candidates.emplace_back(configured);
  }
#if defined(_WIN32)
  candidates.emplace_back("mimc_sdk.dll");
#elif defined(__APPLE__)
  candidates.emplace_back("@rpath/libmimc_sdk.dylib");
  candidates.emplace_back("libmimc_sdk.dylib");
#else
  candidates.emplace_back("libmimc_sdk.so");
#endif

  std::string diagnostic;
  for (const std::string& candidate : candidates) {
#if defined(_WIN32)
    HMODULE library = LoadLibraryA(candidate.c_str());
    if (library == nullptr) {
      diagnostic += candidate + " (load failed); ";
      continue;
    }
#else
    void* library = dlopen(candidate.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (library == nullptr) {
      diagnostic += candidate + " (" + Safe(dlerror()) + "); ";
      continue;
    }
#endif
    MimcSdkApi resolved;
    if (ResolveApi(library, &resolved)) {
      g_sdk = resolved;
      g_sdk_library = library;
      g_sdk_loaded = true;
      ClearError();
      return true;
    }
    diagnostic += candidate + " (missing required C API symbols); ";
#if defined(_WIN32)
    FreeLibrary(library);
#else
    dlclose(library);
#endif
  }
  Fail(FLUTTER_MIMC_SDK_UNAVAILABLE,
       "Unable to load Xiaomi MIMC C++ SDK: " + diagnostic);
  return false;
}

int32_t SdkUnavailable() {
  EnsureSdkLoaded();
  std::lock_guard<std::mutex> lock(g_state_mutex);
  if (g_last_error.empty()) {
    g_last_error = "Xiaomi MIMC C++ SDK adapter is not loaded";
  }
  return FLUTTER_MIMC_SDK_UNAVAILABLE;
}

int32_t ValidateSend(const uint8_t* payload,
                     int32_t payload_length,
                     char* packet_id,
                     int32_t packet_id_capacity) {
  if (!g_initialized.load()) {
    return Fail(FLUTTER_MIMC_NOT_INITIALIZED, "MIMC is not initialized");
  }
  if (payload_length < 0 || (payload_length > 0 && payload == nullptr)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "payload is invalid");
  }
  if (packet_id == nullptr || packet_id_capacity <= 1) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "packet_id output buffer is invalid");
  }
  packet_id[0] = '\0';
  return FLUTTER_MIMC_OK;
}

int32_t ValidateRts() {
  if (!g_initialized.load()) {
    return Fail(FLUTTER_MIMC_NOT_INITIALIZED, "MIMC is not initialized");
  }
  if (!HasRtsApi()) {
    return Fail(FLUTTER_MIMC_SDK_UNAVAILABLE,
                "The loaded MIMC C++ SDK does not expose the RTS C API");
  }
  return FLUTTER_MIMC_OK;
}

bool MapRtsDataType(int32_t value, mimc_sdk_data_type_t* output) {
  if (value == 0) {
    *output = MIMC_SDK_AUDIO;
    return true;
  }
  if (value == 1) {
    *output = MIMC_SDK_VIDEO;
    return true;
  }
  return false;
}

bool MapRtsChannelType(int32_t value, mimc_sdk_channel_type_t* output) {
  switch (value) {
    case 0:
      *output = MIMC_SDK_CHANNEL_AUTO;
      return true;
    case 1:
      *output = MIMC_SDK_RELAY;
      return true;
    case 2:
      *output = MIMC_SDK_P2P_INTERNET;
      return true;
    case 3:
      *output = MIMC_SDK_P2P_INTRANET;
      return true;
    default:
      return false;
  }
}

}  // namespace

const char* flutter_mimc_native_version(void) { return "2.0.0-dev.3"; }

const char* flutter_mimc_last_error(void) {
  static thread_local std::string result;
  std::lock_guard<std::mutex> lock(g_state_mutex);
  result = g_last_error;
  return result.c_str();
}

uint8_t flutter_mimc_is_sdk_linked(void) {
  return EnsureSdkLoaded() ? 1 : 0;
}

uint64_t flutter_mimc_get_capabilities(void) {
  if (!EnsureSdkLoaded()) {
    return 0;
  }
  uint64_t capabilities = FLUTTER_MIMC_CAP_MESSAGE |
                          FLUTTER_MIMC_CAP_GROUP_MESSAGE |
                          FLUTTER_MIMC_CAP_ONLINE_MESSAGE;
  if (HasRtsApi()) capabilities |= FLUTTER_MIMC_CAP_REALTIME_STREAM;
  return capabilities;
}

int32_t flutter_mimc_initialize(int64_t app_id,
                                const char* app_account,
                                const char* resource,
                                const char* cache_directory,
                                const char* token,
                                uint8_t debug) {
  (void)debug;
  if (app_id <= 0 || IsEmpty(app_account) || IsEmpty(token)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "app_id, app_account and token are required");
  }
  if (IsTokenTooLong(token)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "token response exceeds the C++ SDK 2047-byte limit");
  }
  if (!EnsureSdkLoaded()) {
    return SdkUnavailable();
  }

  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  if (g_initialized.load()) {
    g_sdk.logout(&g_user);
    g_sdk.fini(&g_user);
    g_user = {};
    g_initialized.store(false);
    g_online.store(false);
  }
  {
    std::lock_guard<std::mutex> state_lock(g_state_mutex);
    g_token = token;
    g_events.clear();
  }
  const bool save_cache = !IsEmpty(cache_directory);
  g_sdk.init(&g_user, app_id, app_account, Safe(resource), save_cache,
             Safe(cache_directory));
  if (g_user.value == nullptr) {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK failed to create a user");
  }
  g_sdk.register_token_fetcher(&g_user, nullptr, &FetchToken, &FreeTokenArgs);
  g_sdk.register_online_status_handler(&g_user, &kOnlineStatusHandler);
  g_sdk.register_message_handler(&g_user, &kMessageHandler);
  if (HasRtsApi()) {
    g_sdk.register_rtscall_event_handler(&g_user, &kRtsCallHandler);
    g_sdk.enable_p2p(&g_user, true);
  }
  g_initialized.store(true);
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_update_token(const char* token) {
  if (IsEmpty(token)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "token is required");
  }
  if (IsTokenTooLong(token)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "token response exceeds the C++ SDK 2047-byte limit");
  }
  if (!g_initialized.load()) {
    return Fail(FLUTTER_MIMC_NOT_INITIALIZED, "MIMC is not initialized");
  }
  std::lock_guard<std::mutex> lock(g_state_mutex);
  g_token = token;
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_login(void) {
  if (!g_initialized.load()) {
    return Fail(FLUTTER_MIMC_NOT_INITIALIZED, "MIMC is not initialized");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  PushEvent(
      "{\"type\":\"connectionChanged\",\"data\":{\"state\":\"connecting\"}}");
  if (!g_sdk.login(&g_user)) {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK rejected the login request");
  }
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_logout(void) {
  if (!g_initialized.load()) {
    return Fail(FLUTTER_MIMC_NOT_INITIALIZED, "MIMC is not initialized");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  if (!g_sdk.logout(&g_user)) {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK rejected the logout request");
  }
  g_online.store(false);
  ClearError();
  return FLUTTER_MIMC_OK;
}

uint8_t flutter_mimc_is_online(void) {
  if (!g_initialized.load()) {
    return 0;
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  const bool online = g_sdk.is_online(&g_user);
  g_online.store(online);
  return online ? 1 : 0;
}

int32_t flutter_mimc_send_message(const char* to_account,
                                  const uint8_t* payload,
                                  int32_t payload_length,
                                  const char* biz_type,
                                  uint8_t store,
                                  char* packet_id,
                                  int32_t packet_id_capacity) {
  if (IsEmpty(to_account)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "to_account is required");
  }
  const int32_t validation =
      ValidateSend(payload, payload_length, packet_id, packet_id_capacity);
  if (validation != FLUTTER_MIMC_OK) {
    return validation;
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  g_sdk.send_message(&g_user, to_account,
                     reinterpret_cast<const char*>(payload), payload_length,
                     Safe(biz_type), store != 0, packet_id,
                     packet_id_capacity);
  if (packet_id[0] == '\0') {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK returned an empty packet id");
  }
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_send_group_message(int64_t topic_id,
                                        const uint8_t* payload,
                                        int32_t payload_length,
                                        const char* biz_type,
                                        uint8_t store,
                                        char* packet_id,
                                        int32_t packet_id_capacity) {
  if (topic_id <= 0) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "topic_id is required");
  }
  const int32_t validation =
      ValidateSend(payload, payload_length, packet_id, packet_id_capacity);
  if (validation != FLUTTER_MIMC_OK) {
    return validation;
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  g_sdk.send_group_message(
      &g_user, topic_id, reinterpret_cast<const char*>(payload),
      payload_length, Safe(biz_type), store != 0, packet_id,
      packet_id_capacity);
  if (packet_id[0] == '\0') {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK returned an empty packet id");
  }
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_send_online_message(const char* to_account,
                                         const uint8_t* payload,
                                         int32_t payload_length,
                                         const char* biz_type,
                                         uint8_t store,
                                         char* packet_id,
                                         int32_t packet_id_capacity) {
  if (IsEmpty(to_account)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "to_account is required");
  }
  const int32_t validation =
      ValidateSend(payload, payload_length, packet_id, packet_id_capacity);
  if (validation != FLUTTER_MIMC_OK) {
    return validation;
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  g_sdk.send_online_message(
      &g_user, to_account, reinterpret_cast<const char*>(payload),
      payload_length, Safe(biz_type), store != 0, packet_id,
      packet_id_capacity);
  if (packet_id[0] == '\0') {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK returned an empty packet id");
  }
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_set_rts_incoming_call_policy(
    uint8_t accepted,
    const char* description) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  g_accept_incoming_rts_calls.store(accepted != 0);
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_incoming_rts_description = Safe(description);
  }
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_configure_rts_stream(int32_t data_type,
                                          int32_t strategy,
                                          int32_t ack_wait_time_ms,
                                          uint8_t encrypt) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  mimc_sdk_data_type_t mapped_type;
  if (!MapRtsDataType(data_type, &mapped_type) ||
      (strategy != 0 && strategy != 1) || ack_wait_time_ms < 0) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "RTS stream configuration is invalid");
  }
  const mimc_sdk_stream_config_t config = {
      strategy == 0 ? MIMC_SDK_STREAM_FEC : MIMC_SDK_STREAM_ACK,
      static_cast<unsigned int>(ack_wait_time_ms),
      encrypt != 0,
  };
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  if (mapped_type == MIMC_SDK_AUDIO) {
    g_sdk.init_audio_stream(&g_user, &config);
  } else {
    g_sdk.init_video_stream(&g_user, &config);
  }
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_configure_rts_buffers(int32_t send_size,
                                           int32_t receive_size) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  if (send_size <= 0 || receive_size <= 0) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "RTS buffer sizes must be greater than zero");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  g_sdk.set_send_buffer_size(&g_user, send_size);
  g_sdk.set_receive_buffer_size(&g_user, receive_size);
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_get_rts_buffer_state(int32_t* send_size,
                                          int32_t* receive_size,
                                          float* send_usage_rate,
                                          float* receive_usage_rate) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  if (send_size == nullptr || receive_size == nullptr ||
      send_usage_rate == nullptr || receive_usage_rate == nullptr) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "RTS buffer state output pointers are required");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  *send_size = g_sdk.get_send_buffer_size(&g_user);
  *receive_size = g_sdk.get_receive_buffer_size(&g_user);
  *send_usage_rate = g_sdk.get_send_buffer_usage(&g_user);
  *receive_usage_rate = g_sdk.get_receive_buffer_usage(&g_user);
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_clear_rts_buffers(void) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  g_sdk.clear_send_buffer(&g_user);
  g_sdk.clear_receive_buffer(&g_user);
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_dial_rts_call(const char* to_account,
                                   const char* to_resource,
                                   const uint8_t* app_content,
                                   int32_t app_content_length,
                                   int64_t* call_id) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  if (IsEmpty(to_account) || call_id == nullptr || app_content_length < 0 ||
      (app_content_length > 0 && app_content == nullptr)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT,
                "RTS destination, content and call_id output are invalid");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  const uint64_t id = g_sdk.dial_call(
      &g_user, to_account, reinterpret_cast<const char*>(app_content),
      app_content_length, Safe(to_resource));
  if (id == 0 || id > static_cast<uint64_t>(INT64_MAX)) {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK rejected the RTS call");
  }
  *call_id = static_cast<int64_t>(id);
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_close_rts_call(int64_t call_id, const char* reason) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  if (call_id <= 0) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "RTS call_id is invalid");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  g_sdk.close_call(&g_user, static_cast<uint64_t>(call_id), Safe(reason));
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_send_rts_data(int64_t call_id,
                                   const uint8_t* payload,
                                   int32_t payload_length,
                                   int32_t data_type,
                                   int32_t priority,
                                   uint8_t can_be_dropped,
                                   uint32_t resend_count,
                                   int32_t channel_type,
                                   const char* context,
                                   int32_t* data_id) {
  const int32_t validation = ValidateRts();
  if (validation != FLUTTER_MIMC_OK) return validation;
  mimc_sdk_data_type_t mapped_data_type;
  mimc_sdk_channel_type_t mapped_channel_type;
  if (call_id <= 0 || payload_length < 0 || payload_length > 512 * 1024 ||
      (payload_length > 0 && payload == nullptr) || priority < 0 ||
      priority > 2 || !MapRtsDataType(data_type, &mapped_data_type) ||
      !MapRtsChannelType(channel_type, &mapped_channel_type) ||
      data_id == nullptr) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "RTS send arguments are invalid");
  }
  const char* safe_context = Safe(context);
  const size_t context_length = std::strlen(safe_context);
  if (context_length > static_cast<size_t>(INT32_MAX)) {
    return Fail(FLUTTER_MIMC_INVALID_ARGUMENT, "RTS context is too long");
  }
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  const int id = g_sdk.send_rts_data(
      &g_user, static_cast<uint64_t>(call_id),
      reinterpret_cast<const char*>(payload), payload_length, mapped_data_type,
      mapped_channel_type, safe_context, static_cast<int>(context_length),
      can_be_dropped != 0,
      static_cast<mimc_sdk_data_priority_t>(priority), resend_count);
  if (id < 0) {
    return Fail(FLUTTER_MIMC_INTERNAL_ERROR,
                "Xiaomi MIMC SDK rejected the RTS data");
  }
  *data_id = id;
  ClearError();
  return FLUTTER_MIMC_OK;
}

int32_t flutter_mimc_poll_event(char* event_json,
                                int32_t event_json_capacity) {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  if (g_events.empty()) {
    return 0;
  }
  const std::string& event = g_events.front();
  const int32_t required = static_cast<int32_t>(event.size() + 1);
  if (event_json == nullptr || event_json_capacity < required) {
    return -required;
  }
  std::memcpy(event_json, event.c_str(), static_cast<size_t>(required));
  g_events.pop_front();
  return required - 1;
}

void flutter_mimc_dispose(void) {
  std::lock_guard<std::mutex> sdk_lock(g_sdk_call_mutex);
  if (g_initialized.load() && g_sdk_loaded) {
    g_sdk.logout(&g_user);
    g_sdk.fini(&g_user);
  }
  g_user = {};
  g_initialized.store(false);
  g_online.store(false);
  g_accept_incoming_rts_calls.store(false);
  std::lock_guard<std::mutex> state_lock(g_state_mutex);
  g_events.clear();
  g_token.clear();
  g_incoming_rts_description = "Rejected by application policy";
  g_last_error.clear();
}
