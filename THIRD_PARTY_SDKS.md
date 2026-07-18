# Third-party MIMC SDK inventory

The mobile and Web SDK files were copied without modification from the
following Xiaomi repositories. SHA-256 values make later upgrades auditable.

| Platform | Upstream revision | Vendored file | SHA-256 |
|---|---|---|---|
| Android 2.0.8-SNAPSHOT | `59e8ac852e3cf5f371d34895c5ca8d5fc067ca8b` (2021-03-03) | `android/libs/mimc-java-sdk-2.0.8-SNAPSHOT.jar` | `52fc5b100c046215e9277e4d4109cc367408aa8032e8107d72f50801777c31e3` |
| Android RTS 2.0.8 (`armeabi-v7a`) | `59e8ac852e3cf5f371d34895c5ca8d5fc067ca8b` | `android/src/main/jniLibs/armeabi-v7a/librts.so` | `66343ac51364ae381bcd0f96cf70d584801ed99909c5530f426ab763376f04ee` |
| Android XMD 2.0.8 (`armeabi-v7a`) | `59e8ac852e3cf5f371d34895c5ca8d5fc067ca8b` | `android/src/main/jniLibs/armeabi-v7a/libxmdtransceiver.so` | `f85c3ca4b1c465f83aba49f63d0af5709e8168d0c8d1724daed6633b2bd409e1` |
| Android RTS 2.0.7 (`arm64-v8a`) | official 2.0.7 SDK distribution | `android/src/main/jniLibs/arm64-v8a/librts.so` | `6cdce74fe2a7850924c0b85eeea572976bfdc7436adaac4b178c2805621c4946` |
| Android XMD 2.0.7 (`arm64-v8a`) | official 2.0.7 SDK distribution | `android/src/main/jniLibs/arm64-v8a/libxmdtransceiver.so` | `5067394529c2aab96ead18af3858da28ec7a5775ee5fd2f928dea2ff7ce662bb` |
| Android RTS 2.0.7 (`x86`) | official 2.0.7 SDK distribution | `android/src/main/jniLibs/x86/librts.so` | `7609368a92d4592186bb47d4fea89918fea07db709810e1485b248bc87bd31fe` |
| Android XMD 2.0.7 (`x86`) | official 2.0.7 SDK distribution | `android/src/main/jniLibs/x86/libxmdtransceiver.so` | `3016dfd8db919669dc8de111f0c95794f9dfd70006e03c26feb0e5fc2b8216dc` |
| Android RTS 2.0.7 (`x86_64`) | official 2.0.7 SDK distribution | `android/src/main/jniLibs/x86_64/librts.so` | `fca0277602ebc80ae98287e0ad586cd695f92de6c5f34c4c5994cb1493cc319e` |
| Android XMD 2.0.7 (`x86_64`) | official 2.0.7 SDK distribution | `android/src/main/jniLibs/x86_64/libxmdtransceiver.so` | `694ca8b9c56d259f59898377afb77436ae876e74bbfdb6491572ab54c802ce8f` |
| iOS 2.2.7 | `e3665fcbdfff13ab1285c3595ae902e236b63d32` (2021-01-19) | `ios/Frameworks/MMCSDK.framework/MMCSDK` | `3a8859e78bb06d0ca5249d017a4145122ef75814e45c2fc66d34372c746675d2` |
| iOS protobuf | `e3665fcbdfff13ab1285c3595ae902e236b63d32` | `ios/Frameworks/MIMCProtoBuffer.framework/MIMCProtoBuffer` | `78f394666cd125d46cdbbb0f90540d149d69e1f3bed0e7e7941be7bdebddf9f4` |
| WebJS 1.0.3 | `8456b3cf9c3b9cec82e5c215c229683b67b8ff03` (2021-01-25) | `assets/web/mimc-min_1_0_3.js` | `712079b3ae5f4659510d879d998c1e872d215e404d88fb72489252cb33752b37` |
| macOS C++ Universal | `218265cadc26b00f89b8e689f093954f265752df` (2020-07-29) | `macos/Vendor/libmimc_sdk.dylib` | `12da431d20c3244d669a129cc124f8efef5ef2eec44c34be93296e777186920e` |

Xiaomi's 2.0.8 Android repository only publishes `armeabi-v7a` RTS native
objects. The other ABI objects come from Xiaomi's immediately preceding 2.0.7
distribution (archive SHA-256
`77a87e02848bc6a9a9a0021126378e95e7adae208acde8b29405f4664c18d5eb`).
The 2.0.8 changelog contains only a Java resolver-timeout change, so its JNI
surface remains compatible with those objects. Keeping the provenance split
explicit avoids presenting the additional ABI objects as 2.0.8 artifacts.

The desktop bridge targets the C ABI at C++ SDK revision
`218265cadc26b00f89b8e689f093954f265752df` (2020-07-29). Xiaomi does not
publish a portable desktop binary set, so `tool/build_desktop_sdk.sh` compiles
the official source and statically includes its vendored protobuf-lite,
json-c, and XMD sources. The macOS artifact is Universal x86_64/arm64, has a
10.14 deployment target, and only dynamically depends on system libcurl,
libc++, and libSystem.

The compatibility patch removes the unavailable desktop OpenSSL dependency by
using tested local SHA-1/Base64/RC4 equivalents, enables TLS certificate and
hostname verification for the Xiaomi resolver, fixes two 64-bit portability
issues, and adapts json-c's platform configuration. Reproducibility hashes:

The Flutter bridge dynamically resolves both the messaging C API and the
point-to-point RTS C API (`mimc_rtc_dial_call`, `mimc_rtc_send_data`, stream
configuration, buffer controls, and RTS callbacks). The public C API does not
expose the Android/iOS multi-user RTS channel feature, so desktop capability
reporting intentionally omits `realtimeChannel`.

| Build input | SHA-256 |
|---|---|
| `tool/desktop_sdk/mimc-portable-crypto.patch` | `086d9f94a24f2fcb2b27bd3d791447f8d03439d017be23c4f309a01878ff7c4d` |
| `tool/desktop_sdk/portable_crypto.cpp` | `1df54dff96540b3fc2581c76d28d2d5267449699b39cb889904501cba35b7331` |
| `tool/desktop_sdk/portable_crypto.h` | `6489ad5315c0822ef999ac9b30fb9688f2fd50968c6d2b9da7d538b35a535abb` |
