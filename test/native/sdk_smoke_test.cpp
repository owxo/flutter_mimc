#include "../../src/flutter_mimc_bridge.h"

#include <cassert>
#include <cstdint>
#include <iostream>

int main() {
  assert(flutter_mimc_is_sdk_linked() == 1);
  const uint64_t capabilities = flutter_mimc_get_capabilities();
  assert(capabilities == (FLUTTER_MIMC_CAP_MESSAGE |
                          FLUTTER_MIMC_CAP_GROUP_MESSAGE |
                          FLUTTER_MIMC_CAP_ONLINE_MESSAGE |
                          FLUTTER_MIMC_CAP_REALTIME_STREAM));
  assert(flutter_mimc_initialize(
             123, "flutter-mimc-smoke", "desktop", "",
             R"({"code":200,"message":"smoke-test-only"})", 0) ==
         FLUTTER_MIMC_OK);
  assert(flutter_mimc_is_online() == 0);
  assert(flutter_mimc_update_token(
             R"({"code":200,"message":"updated-smoke-token"})") ==
         FLUTTER_MIMC_OK);
  flutter_mimc_dispose();
  std::cout << "official C++ SDK ABI smoke test passed\n";
  return 0;
}
