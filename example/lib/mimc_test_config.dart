import 'package:flutter/foundation.dart';

final class MimcTestConfig {
  const MimcTestConfig._();

  static const String appId = String.fromEnvironment(
    'MIMC_APP_ID',
    defaultValue: '',
  );
  static const String account = String.fromEnvironment(
    'MIMC_ACCOUNT',
    defaultValue: 'mimc_e2e_a',
  );
  static const String peerAccount = String.fromEnvironment(
    'MIMC_PEER_ACCOUNT',
    defaultValue: 'mimc_e2e_b',
  );
  static const String peerResource = String.fromEnvironment(
    'MIMC_PEER_RESOURCE',
  );
  static const String resourceOverride = String.fromEnvironment(
    'MIMC_RESOURCE',
  );
  static const String tokenEndpoint = String.fromEnvironment(
    'MIMC_TOKEN_ENDPOINT',
    defaultValue: '',
  );
  static const String fastAdminUserToken = String.fromEnvironment(
    'FASTADMIN_USER_TOKEN',
  );
  static const String testAuthToken = String.fromEnvironment(
    'MIMC_TEST_AUTH_TOKEN',
  );
  static const bool liveTest = bool.fromEnvironment('MIMC_LIVE_TEST');
  static const bool liveRtsTest = bool.fromEnvironment('MIMC_LIVE_RTS_TEST');
  static const bool liveRtsReceiverTest = bool.fromEnvironment(
    'MIMC_LIVE_RTS_RECEIVER_TEST',
  );
  static const bool autoStart = bool.fromEnvironment('MIMC_AUTO_START');

  static String get resource {
    if (resourceOverride.isNotEmpty) return resourceOverride;
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios-simulator',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
