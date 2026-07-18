import 'dart:async';

import 'package:flutter_mimc/flutter_mimc.dart';
import 'package:flutter_mimc/flutter_mimc_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;

  setUp(() async {
    platform = _FakePlatform();
    FlutterMimcPlatform.instance = platform;
    await FlutterMimc.instance.dispose();
  });

  tearDown(() => FlutterMimc.instance.dispose());

  test('preserves AppIDs larger than the JavaScript safe integer limit', () {
    const MimcConfig config = MimcConfig(
      appId: '9007199254740993',
      appAccount: 'backend-user-42',
    );

    expect(config.appIdString, '9007199254740993');
    expect(config.appIdAsInt, 9007199254740993);
    expect(config.toMap()['appId'], '9007199254740993');
  });

  test('initializes, logs in and sends a binary message', () async {
    var tokenCalls = 0;
    await FlutterMimc.instance.initialize(
      config: const MimcConfig(appId: 123, appAccount: 'alice'),
      tokenProvider: () async => '{"token":"${++tokenCalls}"}',
    );

    await FlutterMimc.instance.login();
    final String packetId = await FlutterMimc.instance.sendMessage(
      toAccount: 'bob',
      payload: <int>[0, 1, 255],
      bizType: 'test',
    );

    expect(platform.initialToken, '{"token":"1"}');
    expect(platform.loggedIn, isTrue);
    expect(platform.lastPayload, <int>[0, 1, 255]);
    expect(packetId, 'packet-1');
  });

  test('refreshes the token when requested by the platform', () async {
    var tokenCalls = 0;
    await FlutterMimc.instance.initialize(
      config: const MimcConfig(appId: 123, appAccount: 'alice'),
      tokenProvider: () async => 'token-${++tokenCalls}',
    );

    platform.controller.add(const MimcTokenRefreshRequired());
    await pumpEventQueue();

    expect(platform.updatedToken, 'token-2');
  });

  test('rejects operations before initialize', () async {
    expect(
      () => FlutterMimc.instance.login(),
      throwsA(isA<MimcException>()),
    );
  });

  test('decodes binary group messages and lifecycle events', () {
    final MimcEvent messageEvent = MimcEvent.fromMap(<Object?, Object?>{
      'type': 'groupMessage',
      'data': <Object?, Object?>{
        'packetId': 'p1',
        'topicId': '42',
        'payload': <int>[0, 128, 255],
        'channel': 'group',
      },
    });
    final MimcEvent pullEvent = MimcEvent.fromMap(<Object?, Object?>{
      'type': 'offlinePullNotification',
      'data': <Object?, Object?>{'minSequence': 7, 'maxSequence': 9},
    });
    final MimcEvent dismissEvent = MimcEvent.fromMap(<Object?, Object?>{
      'type': 'unlimitedGroupDismissed',
      'data': <Object?, Object?>{'topicId': 42},
    });

    expect(messageEvent, isA<MimcMessageReceived>());
    final MimcMessage message = (messageEvent as MimcMessageReceived).message;
    expect(message.topicId, 42);
    expect(message.payload, <int>[0, 128, 255]);
    expect(message.channel, MimcMessageChannel.group);
    expect(
      (pullEvent as MimcOfflinePullNotification).maxSequence,
      9,
    );
    expect(
      (dismissEvent as MimcUnlimitedGroupDismissed).topicId,
      42,
    );
  });

  test('exposes RTS calls and decodes binary RTS events', () async {
    await FlutterMimc.instance.initialize(
      config: const MimcConfig(
        appId: 123,
        appAccount: 'alice',
        rtsIncomingCallPolicy: MimcRtsIncomingCallPolicy.accept,
      ),
      tokenProvider: () async => '{"token":"1"}',
    );

    expect(
      await FlutterMimc.instance.dialRtsCall(
        toAccount: 'bob',
        appContent: <int>[1, 2],
      ),
      99,
    );
    expect(
      await FlutterMimc.instance.sendRtsData(
        callId: 99,
        payload: <int>[0, 128, 255],
        dataType: MimcRtsDataType.video,
        context: 'frame-1',
      ),
      7,
    );

    final MimcEvent dataEvent = MimcEvent.fromMap(<Object?, Object?>{
      'type': 'rtsData',
      'data': <Object?, Object?>{
        'callId': 99,
        'fromAccount': 'bob',
        'fromResource': 'phone',
        'payload': <int>[0, 128, 255],
        'dataType': 'video',
        'channelType': 'p2pInternet',
      },
    });
    final MimcEvent joinedEvent = MimcEvent.fromMap(<Object?, Object?>{
      'type': 'rtsChannelJoined',
      'data': <Object?, Object?>{
        'callId': 100,
        'success': true,
        'members': <Object?>[
          <Object?, Object?>{'appAccount': 'bob', 'resource': 'phone'},
        ],
      },
    });

    expect(dataEvent, isA<MimcRtsDataReceived>());
    final MimcRtsDataReceived data = dataEvent as MimcRtsDataReceived;
    expect(data.payload, <int>[0, 128, 255]);
    expect(data.dataType, MimcRtsDataType.video);
    expect(data.channelType, MimcRtsChannelType.p2pInternet);
    final MimcRtsChannelJoined joined = joinedEvent as MimcRtsChannelJoined;
    expect(joined.members.single.appAccount, 'bob');
  });
}

final class _FakePlatform extends FlutterMimcPlatform {
  final StreamController<MimcEvent> controller =
      StreamController<MimcEvent>.broadcast();

  String? initialToken;
  String? updatedToken;
  bool loggedIn = false;
  List<int>? lastPayload;

  @override
  Stream<MimcEvent> get events => controller.stream;

  @override
  Future<Set<MimcCapability>> getCapabilities() async =>
      <MimcCapability>{MimcCapability.message};

  @override
  Future<void> initialize({
    required MimcConfig config,
    required String token,
  }) async {
    initialToken = token;
  }

  @override
  Future<void> updateToken(String token) async => updatedToken = token;

  @override
  Future<void> login() async => loggedIn = true;

  @override
  Future<void> logout() async => loggedIn = false;

  @override
  Future<bool> isOnline() async => loggedIn;

  @override
  Future<String> sendMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async {
    lastPayload = payload;
    return 'packet-1';
  }

  @override
  Future<String> sendGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      'group-packet';

  @override
  Future<String> sendOnlineMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = false,
  }) async =>
      'online-packet';

  @override
  Future<String> sendUnlimitedGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      'uc-packet';

  @override
  Future<int> createUnlimitedGroup(String topicName) async => 42;

  @override
  Future<void> joinUnlimitedGroup(int topicId) async {}

  @override
  Future<void> quitUnlimitedGroup(int topicId) async {}

  @override
  Future<void> dismissUnlimitedGroup(int topicId) async {}

  @override
  Future<void> setRtsIncomingCallPolicy(
    MimcRtsIncomingCallPolicy policy, {
    String description = '',
  }) async {}

  @override
  Future<void> configureRtsStream(
    MimcRtsDataType dataType,
    MimcRtsStreamConfig config,
  ) async {}

  @override
  Future<void> configureRtsBuffers({
    required int sendSize,
    required int receiveSize,
  }) async {}

  @override
  Future<MimcRtsBufferState> getRtsBufferState() async =>
      const MimcRtsBufferState(
        sendSize: 1024,
        receiveSize: 2048,
        sendUsageRate: 0,
        receiveUsageRate: 0,
      );

  @override
  Future<void> clearRtsBuffers() async {}

  @override
  Future<int> dialRtsCall({
    required String toAccount,
    String toResource = '',
    List<int> appContent = const <int>[],
  }) async =>
      99;

  @override
  Future<void> closeRtsCall(int callId, {String reason = ''}) async {}

  @override
  Future<int> sendRtsData({
    required int callId,
    required List<int> payload,
    required MimcRtsDataType dataType,
    MimcRtsDataPriority priority = MimcRtsDataPriority.p1,
    bool canBeDropped = false,
    int resendCount = 0,
    MimcRtsChannelType channelType = MimcRtsChannelType.automatic,
    String context = '',
  }) async =>
      7;

  @override
  Future<int> createRtsChannel({List<int> extra = const <int>[]}) async => 88;

  @override
  Future<void> joinRtsChannel({
    required int callId,
    required String callKey,
  }) async {}

  @override
  Future<void> leaveRtsChannel({
    required int callId,
    required String callKey,
  }) async {}

  @override
  Future<List<MimcRtsChannelMember>> getRtsChannelMembers(int callId) async =>
      const <MimcRtsChannelMember>[];

  @override
  Future<void> dispose() async {
    loggedIn = false;
  }
}
