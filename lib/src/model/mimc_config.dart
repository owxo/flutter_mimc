import 'mimc_rts.dart';

/// Immutable configuration used to create a MIMC user.
final class MimcConfig {
  const MimcConfig({
    required this.appId,
    required this.appAccount,
    this.resource,
    this.cacheDirectory,
    this.debug = false,
    this.rtsIncomingCallPolicy = MimcRtsIncomingCallPolicy.reject,
    this.rtsIncomingCallDescription = 'Rejected by application policy',
  })  : assert(appId is int || appId is String),
        assert(appId is! int || appId > 0),
        assert(appId is! String || appId != ''),
        assert(appAccount != '');

  /// Xiaomi AppID. Use a decimal [String] for Web because MIMC AppIDs exceed
  /// JavaScript's safe integer range. Existing native-only code may use [int].
  final Object appId;
  final String appAccount;
  final String? resource;
  final String? cacheDirectory;
  final bool debug;
  final MimcRtsIncomingCallPolicy rtsIncomingCallPolicy;
  final String rtsIncomingCallDescription;

  String get appIdString => appId.toString();

  int get appIdAsInt {
    final int? parsed = int.tryParse(appIdString);
    if (parsed == null || parsed <= 0) {
      throw ArgumentError.value(appId, 'appId', 'must be a positive integer');
    }
    return parsed;
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'appId': appId,
        'appAccount': appAccount,
        'resource': resource,
        'cacheDirectory': cacheDirectory,
        'debug': debug,
        'rtsIncomingCallPolicy': rtsIncomingCallPolicy.name,
        'rtsIncomingCallDescription': rtsIncomingCallDescription,
      };
}
