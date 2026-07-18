import 'dart:async';
import 'dart:convert';

import 'package:flutter_mimc/flutter_mimc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_mimc_example/mimc_test_config.dart';
import 'package:flutter_mimc_example/mimc_token_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'logs in and receives a server ACK from the real MIMC service',
    (WidgetTester tester) async {
      final FlutterMimc mimc = FlutterMimc.instance;
      final Completer<void> online = Completer<void>();
      final Set<String> acknowledgedPacketIds = <String>{};
      final List<String> streamFailures = <String>[];

      final StreamSubscription<MimcEvent> events = mimc.events.listen(
        (MimcEvent event) {
          switch (event) {
            case MimcConnectionChanged(
                state: MimcConnectionState.online,
              ):
              if (!online.isCompleted) online.complete();
            case MimcServerAckReceived(:final ack):
              acknowledgedPacketIds.add(ack.packetId);
            default:
              break;
          }
        },
        onError: (Object error) => streamFailures.add('event stream: $error'),
      );

      try {
        final MimcTokenClient tokenClient = MimcTokenClient(
          endpoint: MimcTestConfig.tokenEndpoint,
          userToken: MimcTestConfig.fastAdminUserToken,
          testAuthToken: MimcTestConfig.testAuthToken,
        );
        await mimc.initialize(
          config: MimcConfig(
            appId: MimcTestConfig.appId,
            appAccount: MimcTestConfig.account,
            resource: MimcTestConfig.resource,
            debug: true,
            rtsIncomingCallPolicy: MimcRtsIncomingCallPolicy.accept,
          ),
          tokenProvider: () =>
              tokenClient.fetchForAccount(MimcTestConfig.account),
        );
        if (MimcTestConfig.liveRtsTest || MimcTestConfig.liveRtsReceiverTest) {
          // Use an explicit cross-SDK stream profile. Native SDK generations
          // do not all ship with the same audio defaults (notably encryption),
          // and both peers must agree before user-data frames can be decoded.
          await mimc.configureRtsStream(
            MimcRtsDataType.audio,
            const MimcRtsStreamConfig(
              strategy: MimcRtsStreamStrategy.ack,
              ackWaitTimeMs: 150,
              encrypt: false,
            ),
          );
        }
        await mimc.login();
        await online.future.timeout(const Duration(seconds: 30));
        expect(await mimc.isOnline(), isTrue);

        final String packetId = await mimc.sendMessage(
          toAccount: MimcTestConfig.peerAccount,
          payload: utf8.encode(
            'flutter_mimc live E2E ${DateTime.now().toUtc().toIso8601String()}',
          ),
          bizType: 'flutter_mimc.live_e2e',
        );
        await _waitUntil(
          () => acknowledgedPacketIds.contains(packetId),
          const Duration(seconds: 30),
          'No server ACK for packet $packetId',
        );
        // ACK code values differ between SDK generations (for example iOS
        // reports 100); the ACK callback itself confirms server receipt.
        expect(streamFailures, isEmpty);

        if (MimcTestConfig.liveRtsReceiverTest) {
          await _runRtsReceiverTest(mimc);
        } else if (MimcTestConfig.liveRtsTest) {
          await _runRtsTest(mimc);
        }
      } finally {
        if (mimc.isInitialized) {
          try {
            await mimc.logout();
          } finally {
            await mimc.dispose();
          }
        }
        await events.cancel();
      }
    },
    skip: !MimcTestConfig.liveTest,
  );
}

Future<void> _runRtsReceiverTest(FlutterMimc mimc) async {
  final Completer<MimcRtsCallIncoming> incoming =
      Completer<MimcRtsCallIncoming>();
  final Completer<MimcRtsDataReceived> data = Completer<MimcRtsDataReceived>();
  final Set<int> successfulDataIds = <int>{};
  final StreamSubscription<MimcEvent> events = mimc.events.listen(
    (MimcEvent event) {
      // ignore: avoid_print
      print('MIMC_RTS_RECEIVER_EVENT $event');
      switch (event) {
        case MimcRtsCallIncoming():
          if (!incoming.isCompleted) incoming.complete(event);
        case MimcRtsDataReceived():
          if (!data.isCompleted) data.complete(event);
        case MimcRtsDataSendResult(:final dataId, success: true):
          successfulDataIds.add(dataId);
        default:
          break;
      }
    },
  );

  try {
    final MimcRtsCallIncoming incomingEvent = await incoming.future.timeout(
      const Duration(seconds: 90),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final int responseDataId = await mimc.sendRtsData(
      callId: incomingEvent.callId,
      payload: _rtsPayload,
      dataType: MimcRtsDataType.audio,
      priority: MimcRtsDataPriority.p0,
      canBeDropped: false,
      resendCount: 3,
      channelType: MimcRtsChannelType.automatic,
      context: 'live-e2e-receiver',
    );
    await _waitUntil(
      () => successfulDataIds.contains(responseDataId),
      const Duration(seconds: 30),
      'No successful receiver RTS send callback for data $responseDataId',
    );
    final MimcRtsDataReceived dataEvent = await data.future.timeout(
      const Duration(seconds: 45),
    );
    expect(dataEvent.callId, incomingEvent.callId);
    expect(dataEvent.payload, _rtsPayload);
    expect(dataEvent.dataType, MimcRtsDataType.audio);
    await mimc.closeRtsCall(
      incomingEvent.callId,
      reason: 'Receiver E2E complete',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    await events.cancel();
  }
}

Future<void> _runRtsTest(FlutterMimc mimc) async {
  final Completer<int> answered = Completer<int>();
  final Completer<MimcRtsDataReceived> received =
      Completer<MimcRtsDataReceived>();
  final Set<int> successfulDataIds = <int>{};
  final List<String> rtsEvents = <String>[];
  final StreamSubscription<MimcEvent> events = mimc.events.listen(
    (MimcEvent event) {
      rtsEvents.add(event.toString());
      // Keep native RTS diagnostics visible in `flutter test` output. This is
      // especially useful when an old Xiaomi relay rejects a connection before
      // an incoming-call callback can be delivered.
      // ignore: avoid_print
      print('MIMC_RTS_EVENT $event');
      switch (event) {
        case MimcRtsCallAnswered(:final callId, accepted: true):
          if (!answered.isCompleted) answered.complete(callId);
        case MimcRtsDataSendResult(:final dataId, success: true):
          successfulDataIds.add(dataId);
        case MimcRtsDataReceived():
          if (!received.isCompleted) received.complete(event);
        default:
          break;
      }
    },
  );

  int? activeCallId;
  try {
    // Login becoming ONLINE only proves that the FE connection is ready. The
    // RTS SDK creates its relay connection lazily, so give the SDK a short
    // settling window before the first dial.
    await Future<void>.delayed(const Duration(seconds: 3));
    final int dialCallId = await mimc.dialRtsCall(
      toAccount: MimcTestConfig.peerAccount,
      toResource: MimcTestConfig.peerResource,
      appContent: utf8.encode('flutter_mimc automated RTS E2E'),
    );
    final int answeredCallId = await answered.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'No RTS answer callback. Observed events: ${rtsEvents.join(' | ')}',
        const Duration(seconds: 45),
      ),
    );
    expect(answeredCallId, dialCallId);
    activeCallId = answeredCallId;

    // Let the SDK prefer P2P intranet/internet and fall back to relay. A short
    // settling window avoids sending before the receiver's stream is ready.
    await Future<void>.delayed(const Duration(seconds: 2));
    final int dataId = await mimc.sendRtsData(
      callId: activeCallId,
      // Match the official Xiaomi SDK efficiency test's 100 KiB frame. A
      // one-line UTF-8 sample is smaller than a realistic encoded audio
      // packet and does not exercise native stream fragmentation/reassembly.
      payload: _rtsPayload,
      dataType: MimcRtsDataType.audio,
      priority: MimcRtsDataPriority.p0,
      canBeDropped: false,
      resendCount: 3,
      channelType: MimcRtsChannelType.automatic,
      context: 'live-e2e',
    );
    await _waitUntil(
      () => successfulDataIds.contains(dataId),
      const Duration(seconds: 30),
      'No successful RTS send callback for data $dataId',
    );
    final MimcRtsDataReceived response = await received.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'No peer RTS data callback. Observed events: ${rtsEvents.join(' | ')}',
        const Duration(seconds: 30),
      ),
    );
    expect(response.callId, activeCallId);
    expect(response.payload, _rtsPayload);
    expect(response.dataType, MimcRtsDataType.audio);
    // The sender callback confirms that the SDK/relay accepted the frame, not
    // that the peer callback has already returned. Avoid closing the call in
    // the same event-loop turn and racing the receiver's data callback.
    await Future<void>.delayed(const Duration(seconds: 5));
  } finally {
    if (activeCallId != null) {
      await mimc.closeRtsCall(activeCallId, reason: 'Automated E2E complete');
    }
    await events.cancel();
  }
}

final List<int> _rtsPayload = List<int>.unmodifiable(
  List<int>.generate(100 * 1024, (int index) => index & 0xff),
);

Future<void> _waitUntil(
  bool Function() condition,
  Duration timeout,
  String timeoutMessage,
) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException(timeoutMessage, timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
