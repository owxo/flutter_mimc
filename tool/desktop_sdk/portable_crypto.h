#ifndef FLUTTER_MIMC_PORTABLE_CRYPTO_H_
#define FLUTTER_MIMC_PORTABLE_CRYPTO_H_

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace flutter_mimc_compat {

std::string Base64Encode(const std::string& input);
bool Base64Decode(const std::string& input, std::string* output);

void Rc4(const unsigned char* key,
         int key_length,
         const unsigned char* input,
         size_t input_length,
         unsigned char* output);

std::array<uint8_t, 20> Sha1(const uint8_t* input, size_t input_length);

}  // namespace flutter_mimc_compat

#endif  // FLUTTER_MIMC_PORTABLE_CRYPTO_H_
