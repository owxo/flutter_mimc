import 'dart:io';

import '../flutter_mimc_method_channel.dart';
import '../flutter_mimc_platform_interface.dart';
import 'desktop/flutter_mimc_ffi.dart';

bool _registered = false;

void registerDesktopPlatformIfNeeded() {
  if (_registered) {
    return;
  }
  // Preserve platform implementations injected by applications or tests.
  if (FlutterMimcPlatform.instance is! MethodChannelFlutterMimc) {
    return;
  }
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    FlutterMimcPlatform.instance = FlutterMimcFfi();
    _registered = true;
  }
}
