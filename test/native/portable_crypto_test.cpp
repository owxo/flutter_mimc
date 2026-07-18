#include "../../tool/desktop_sdk/portable_crypto.h"

#include <array>
#include <cassert>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>

namespace {

template <size_t Size>
std::string Hex(const std::array<uint8_t, Size>& bytes) {
  std::ostringstream output;
  for (const uint8_t byte : bytes) {
    output << std::hex << std::setw(2) << std::setfill('0')
           << static_cast<unsigned int>(byte);
  }
  return output.str();
}

std::string Hex(const std::string& bytes) {
  std::ostringstream output;
  for (const unsigned char byte : bytes) {
    output << std::hex << std::setw(2) << std::setfill('0')
           << static_cast<unsigned int>(byte);
  }
  return output.str();
}

}  // namespace

int main() {
  using flutter_mimc_compat::Base64Decode;
  using flutter_mimc_compat::Base64Encode;
  using flutter_mimc_compat::Rc4;
  using flutter_mimc_compat::Sha1;

  assert(Hex(Sha1(reinterpret_cast<const uint8_t*>("abc"), 3)) ==
         "a9993e364706816aba3e25717850c26c9cd0d89d");
  const std::string binary("\x00\xff", 2);
  assert(Base64Encode(binary) == "AP8=");
  std::string decoded;
  assert(Base64Decode("AP8=", &decoded));
  assert(decoded == binary);
  assert(!Base64Decode("not base64", &decoded));

  const std::string plaintext = "Plaintext";
  std::string encrypted(plaintext.size(), '\0');
  Rc4(reinterpret_cast<const unsigned char*>("Key"), 3,
      reinterpret_cast<const unsigned char*>(plaintext.data()),
      plaintext.size(), reinterpret_cast<unsigned char*>(encrypted.data()));
  assert(Hex(encrypted) == "bbf316e8d940af0ad3");
  std::string decrypted(plaintext.size(), '\0');
  Rc4(reinterpret_cast<const unsigned char*>("Key"), 3,
      reinterpret_cast<const unsigned char*>(encrypted.data()),
      encrypted.size(), reinterpret_cast<unsigned char*>(decrypted.data()));
  assert(decrypted == plaintext);
  return 0;
}
