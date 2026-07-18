import 'package:flutter/foundation.dart';
import 'package:flutter_mimc/flutter_mimc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool isDesktop() =>
      !kIsWeb &&
      <TargetPlatform>{
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  testWidgets('reports at least the basic messaging capability', (
    WidgetTester tester,
  ) async {
    final Set<MimcCapability> capabilities =
        await FlutterMimc.instance.getCapabilities();
    expect(capabilities, contains(MimcCapability.message));
    if (isDesktop()) {
      expect(
        capabilities,
        <MimcCapability>{
          MimcCapability.message,
          MimcCapability.groupMessage,
          MimcCapability.onlineMessage,
          MimcCapability.realtimeStream,
        },
      );
    }
  });

  testWidgets('configures the desktop RTS bridge without logging in', (
    WidgetTester tester,
  ) async {
    if (!isDesktop()) return;
    final Set<MimcCapability> capabilities =
        await FlutterMimc.instance.getCapabilities();
    if (!capabilities.contains(MimcCapability.realtimeStream)) return;

    await FlutterMimc.instance.initialize(
      config: const MimcConfig(
        appId: 123,
        appAccount: 'flutter-mimc-rts-smoke',
        resource: 'desktop',
        rtsIncomingCallPolicy: MimcRtsIncomingCallPolicy.accept,
      ),
      tokenProvider: () async => '{"code":200,"message":"rts-smoke-test-only"}',
    );
    try {
      await FlutterMimc.instance.configureRtsStream(
        MimcRtsDataType.audio,
        const MimcRtsStreamConfig(),
      );
      await FlutterMimc.instance.configureRtsBuffers(
        sendSize: 1024 * 1024,
        receiveSize: 1024 * 1024,
      );
      final MimcRtsBufferState state =
          await FlutterMimc.instance.getRtsBufferState();
      expect(state.sendSize, greaterThanOrEqualTo(0));
      expect(state.receiveSize, greaterThanOrEqualTo(0));
      await FlutterMimc.instance.clearRtsBuffers();
    } finally {
      await FlutterMimc.instance.dispose();
    }
  });

  testWidgets('reports an offline iOS RTS dial failure without crashing', (
    WidgetTester tester,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    await FlutterMimc.instance.initialize(
      config: const MimcConfig(
        appId: 123,
        appAccount: 'flutter-mimc-rts-failure-smoke',
        resource: 'simulator',
      ),
      tokenProvider: () async => '{"code":200,"message":"offline-test-only"}',
    );
    try {
      await expectLater(
        FlutterMimc.instance.dialRtsCall(toAccount: 'offline-peer'),
        throwsA(
          isA<MimcException>().having(
            (MimcException error) => error.code,
            'code',
            'rts_dial_failed',
          ),
        ),
      );
    } finally {
      await FlutterMimc.instance.dispose();
    }
  });
}
