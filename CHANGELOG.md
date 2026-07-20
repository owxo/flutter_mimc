## 2.0.0-dev.2

* Fixed iOS Simulator builds by propagating the legacy framework's arm64
  exclusion to the consuming application target. Physical-device arm64 builds
  are unchanged.

## 2.0.0-dev.1

Pre-release: the public API and platform bridges are implemented. Live MIMC
login/message/ACK has passed on a Redmi physical device. RTS call setup and
send acknowledgements pass, but cross-device peer data delivery is still under
investigation and is not declared production-ready in this version.

* Started a ground-up, null-safe rewrite.
* Added a typed platform interface shared by Android, iOS, Web, Windows,
  Linux, and macOS.
* Bundled Android MIMC 2.0.8, iOS MMCSDK 2.2.7, and WebJS 1.0.3.
* Added a desktop C ABI and Dart FFI bridge with dynamic C++ SDK loading,
  binary-safe callbacks, capability detection, and a native mock-SDK test.
* Added a reproducible desktop SDK build, a bundled Universal macOS binary,
  portable crypto vector tests, and an official-SDK ABI smoke test.
* Added direct, group, online, unlimited-group, acknowledgement, timeout,
  offline-pull, connection, and token-refresh APIs/events where supported.
* Hardened Android token initialization and asynchronous unlimited-group
  request tracking on Android, iOS, and Web.
* Added point-to-point RTS calls, binary audio/video data, stream and buffer
  controls, lifecycle events, desktop P2P results, and Android/iOS RTS
  channels. Web reports RTS as unsupported because WebJS 1.0.3 has no API.
* Added a PHP token proxy sample that derives `appAccount` from the backend's
  authenticated user ID, plus live MIMC login/message/ACK E2E tooling.
* Replaced project-specific example identifiers with generic placeholders.
* Fixed Web token JSON conversion and AppIDs beyond JavaScript's safe integer
  range by accepting decimal-string AppIDs across all platforms.
* Replaced the legacy Flutter v1 plugin metadata.
