import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_mimc_method_channel.dart';
import 'src/model/mimc_capability.dart';
import 'src/model/mimc_config.dart';
import 'src/model/mimc_event.dart';
import 'src/model/mimc_rts.dart';

abstract class FlutterMimcPlatform extends PlatformInterface {
  FlutterMimcPlatform() : super(token: _token);

  static final Object _token = Object();
  static FlutterMimcPlatform _instance = MethodChannelFlutterMimc();

  static FlutterMimcPlatform get instance => _instance;

  static set instance(FlutterMimcPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<MimcEvent> get events;

  Future<Set<MimcCapability>> getCapabilities();

  Future<void> initialize({
    required MimcConfig config,
    required String token,
  });

  Future<void> updateToken(String token);

  Future<void> login();

  Future<void> logout();

  Future<bool> isOnline();

  Future<String> sendMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  });

  Future<String> sendGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  });

  Future<String> sendOnlineMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = false,
  });

  Future<String> sendUnlimitedGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  });

  Future<int> createUnlimitedGroup(String topicName);

  Future<void> joinUnlimitedGroup(int topicId);

  Future<void> quitUnlimitedGroup(int topicId);

  Future<void> dismissUnlimitedGroup(int topicId);

  Future<void> setRtsIncomingCallPolicy(
    MimcRtsIncomingCallPolicy policy, {
    String description = '',
  });

  Future<void> configureRtsStream(
    MimcRtsDataType dataType,
    MimcRtsStreamConfig config,
  );

  Future<void> configureRtsBuffers({
    required int sendSize,
    required int receiveSize,
  });

  Future<MimcRtsBufferState> getRtsBufferState();

  Future<void> clearRtsBuffers();

  Future<int> dialRtsCall({
    required String toAccount,
    String toResource = '',
    List<int> appContent = const <int>[],
  });

  Future<void> closeRtsCall(int callId, {String reason = ''});

  Future<int> sendRtsData({
    required int callId,
    required List<int> payload,
    required MimcRtsDataType dataType,
    MimcRtsDataPriority priority = MimcRtsDataPriority.p1,
    bool canBeDropped = false,
    int resendCount = 0,
    MimcRtsChannelType channelType = MimcRtsChannelType.automatic,
    String context = '',
  });

  Future<int> createRtsChannel({List<int> extra = const <int>[]});

  Future<void> joinRtsChannel({
    required int callId,
    required String callKey,
  });

  Future<void> leaveRtsChannel({
    required int callId,
    required String callKey,
  });

  Future<List<MimcRtsChannelMember>> getRtsChannelMembers(int callId);

  Future<void> dispose();
}
