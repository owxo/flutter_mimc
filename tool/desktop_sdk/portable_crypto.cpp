#include "portable_crypto.h"

#include <algorithm>
#include <array>
#include <vector>

namespace flutter_mimc_compat {
namespace {

constexpr char kBase64Alphabet[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

uint32_t RotateLeft(uint32_t value, unsigned int bits) {
  return (value << bits) | (value >> (32U - bits));
}

uint32_t ReadBigEndian(const uint8_t* input) {
  return (static_cast<uint32_t>(input[0]) << 24U) |
         (static_cast<uint32_t>(input[1]) << 16U) |
         (static_cast<uint32_t>(input[2]) << 8U) |
         static_cast<uint32_t>(input[3]);
}

void WriteBigEndian(uint32_t value, uint8_t* output) {
  output[0] = static_cast<uint8_t>(value >> 24U);
  output[1] = static_cast<uint8_t>(value >> 16U);
  output[2] = static_cast<uint8_t>(value >> 8U);
  output[3] = static_cast<uint8_t>(value);
}

int Base64Value(unsigned char value) {
  if (value >= 'A' && value <= 'Z') {
    return value - 'A';
  }
  if (value >= 'a' && value <= 'z') {
    return value - 'a' + 26;
  }
  if (value >= '0' && value <= '9') {
    return value - '0' + 52;
  }
  if (value == '+') {
    return 62;
  }
  if (value == '/') {
    return 63;
  }
  return -1;
}

}  // namespace

std::string Base64Encode(const std::string& input) {
  std::string output;
  output.reserve(((input.size() + 2U) / 3U) * 4U);
  for (size_t index = 0; index < input.size(); index += 3U) {
    const size_t remaining = input.size() - index;
    const uint32_t first = static_cast<unsigned char>(input[index]);
    const uint32_t second =
        remaining > 1U ? static_cast<unsigned char>(input[index + 1U]) : 0U;
    const uint32_t third =
        remaining > 2U ? static_cast<unsigned char>(input[index + 2U]) : 0U;
    const uint32_t value = (first << 16U) | (second << 8U) | third;
    output.push_back(kBase64Alphabet[(value >> 18U) & 0x3fU]);
    output.push_back(kBase64Alphabet[(value >> 12U) & 0x3fU]);
    output.push_back(remaining > 1U ? kBase64Alphabet[(value >> 6U) & 0x3fU]
                                    : '=');
    output.push_back(remaining > 2U ? kBase64Alphabet[value & 0x3fU] : '=');
  }
  return output;
}

bool Base64Decode(const std::string& input, std::string* output) {
  if (output == nullptr || input.empty() || input.size() % 4U != 0U) {
    return false;
  }
  output->clear();
  output->reserve((input.size() / 4U) * 3U);
  for (size_t index = 0; index < input.size(); index += 4U) {
    const bool last = index + 4U == input.size();
    const int first = Base64Value(static_cast<unsigned char>(input[index]));
    const int second =
        Base64Value(static_cast<unsigned char>(input[index + 1U]));
    const bool third_padding = input[index + 2U] == '=';
    const bool fourth_padding = input[index + 3U] == '=';
    const int third = third_padding
                          ? 0
                          : Base64Value(
                                static_cast<unsigned char>(input[index + 2U]));
    const int fourth =
        fourth_padding
            ? 0
            : Base64Value(static_cast<unsigned char>(input[index + 3U]));
    if (first < 0 || second < 0 || third < 0 || fourth < 0 ||
        (!last && (third_padding || fourth_padding)) ||
        (third_padding && !fourth_padding)) {
      output->clear();
      return false;
    }
    const uint32_t value = (static_cast<uint32_t>(first) << 18U) |
                           (static_cast<uint32_t>(second) << 12U) |
                           (static_cast<uint32_t>(third) << 6U) |
                           static_cast<uint32_t>(fourth);
    output->push_back(static_cast<char>(value >> 16U));
    if (!third_padding) {
      output->push_back(static_cast<char>(value >> 8U));
    }
    if (!fourth_padding) {
      output->push_back(static_cast<char>(value));
    }
  }
  return true;
}

void Rc4(const unsigned char* key,
         int key_length,
         const unsigned char* input,
         size_t input_length,
         unsigned char* output) {
  if (key == nullptr || key_length <= 0 || input == nullptr ||
      output == nullptr) {
    return;
  }
  std::array<uint8_t, 256> state{};
  for (size_t index = 0; index < state.size(); ++index) {
    state[index] = static_cast<uint8_t>(index);
  }
  uint8_t second_index = 0;
  for (size_t index = 0; index < state.size(); ++index) {
    second_index = static_cast<uint8_t>(
        second_index + state[index] + key[index % static_cast<size_t>(key_length)]);
    std::swap(state[index], state[second_index]);
  }
  uint8_t first_index = 0;
  second_index = 0;
  for (size_t index = 0; index < input_length; ++index) {
    first_index = static_cast<uint8_t>(first_index + 1U);
    second_index = static_cast<uint8_t>(second_index + state[first_index]);
    std::swap(state[first_index], state[second_index]);
    const uint8_t key_byte = static_cast<uint8_t>(
        state[static_cast<uint8_t>(state[first_index] + state[second_index])]);
    output[index] = static_cast<unsigned char>(input[index] ^ key_byte);
  }
}

std::array<uint8_t, 20> Sha1(const uint8_t* input, size_t input_length) {
  const uint64_t bit_length = static_cast<uint64_t>(input_length) * 8U;
  size_t padded_length = input_length + 1U;
  while (padded_length % 64U != 56U) {
    ++padded_length;
  }
  std::vector<uint8_t> message(padded_length + 8U, 0U);
  if (input_length > 0U) {
    std::copy(input, input + input_length, message.begin());
  }
  message[input_length] = 0x80U;
  for (size_t index = 0; index < 8U; ++index) {
    message[padded_length + index] =
        static_cast<uint8_t>(bit_length >> ((7U - index) * 8U));
  }

  uint32_t h0 = 0x67452301U;
  uint32_t h1 = 0xefcdab89U;
  uint32_t h2 = 0x98badcfeU;
  uint32_t h3 = 0x10325476U;
  uint32_t h4 = 0xc3d2e1f0U;
  for (size_t offset = 0; offset < message.size(); offset += 64U) {
    std::array<uint32_t, 80> words{};
    for (size_t index = 0; index < 16U; ++index) {
      words[index] = ReadBigEndian(message.data() + offset + index * 4U);
    }
    for (size_t index = 16U; index < words.size(); ++index) {
      words[index] = RotateLeft(words[index - 3U] ^ words[index - 8U] ^
                                    words[index - 14U] ^ words[index - 16U],
                                1U);
    }

    uint32_t a = h0;
    uint32_t b = h1;
    uint32_t c = h2;
    uint32_t d = h3;
    uint32_t e = h4;
    for (size_t index = 0; index < words.size(); ++index) {
      uint32_t function;
      uint32_t constant;
      if (index < 20U) {
        function = (b & c) | ((~b) & d);
        constant = 0x5a827999U;
      } else if (index < 40U) {
        function = b ^ c ^ d;
        constant = 0x6ed9eba1U;
      } else if (index < 60U) {
        function = (b & c) | (b & d) | (c & d);
        constant = 0x8f1bbcdcU;
      } else {
        function = b ^ c ^ d;
        constant = 0xca62c1d6U;
      }
      const uint32_t temporary = RotateLeft(a, 5U) + function + e + constant +
                                 words[index];
      e = d;
      d = c;
      c = RotateLeft(b, 30U);
      b = a;
      a = temporary;
    }
    h0 += a;
    h1 += b;
    h2 += c;
    h3 += d;
    h4 += e;
  }

  std::array<uint8_t, 20> digest{};
  WriteBigEndian(h0, digest.data());
  WriteBigEndian(h1, digest.data() + 4U);
  WriteBigEndian(h2, digest.data() + 8U);
  WriteBigEndian(h3, digest.data() + 12U);
  WriteBigEndian(h4, digest.data() + 16U);
  return digest;
}

}  // namespace flutter_mimc_compat
