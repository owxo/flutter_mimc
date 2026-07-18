import 'dart:async';

import 'package:flutter/services.dart';

import 'flutter_mimc_platform_interface.dart';
import 'src/mimc_exception.dart';
import 'src/model/mimc_capability.dart';
import 'src/model/mimc_config.dart';
import 'src/model/mimc_event.dart';
import 'src/model/mimc_rts.dart';

class MethodChannelFlutterMimc extends FlutterMimcPlatform {
  MethodChannelFlutterMimc({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : methodChannel =
            methodChannel ?? const MethodChannel('dev.flutter_mimc/methods'),
        eventChannel =
            eventChannel ?? const EventChannel('dev.flutter_mimc/events');

  final MethodChannel methodChannel;
  final EventChannel eventChannel;
  Stream<MimcEvent>? _events;

  @override
  Stream<MimcEvent> get events => _events ??= eventChannel
      .receiveBroadcastStream()
      .map(_eventFromPlatform)
      .asBroadcastStream();

  @override
  Future<Set<MimcCapability>> getCapabilities() async {
    final List<Object?> values =
        await _invoke<List<Object?>>('getCapabilities') ?? <Object?>[];
    return values
        .whereType<String>()
        .map(_capabilityFromName)
        .whereType<MimcCapability>()
        .toSet();
  }

  @override
  Future<void> initialize({
    required MimcConfig config,
    required String token,
  }) =>
      _invoke<void>('initialize', <String, Object?>{
        ...config.toMap(),
        'token': token,
      });

  @override
  Future<void> updateToken(String token) =>
      _invoke<void>('updateToken', <String, Object?>{'token': token});

  @override
  Future<void> login() => _invoke<void>('login');

  @override
  Future<void> logout() => _invoke<void>('logout');

  @override
  Future<bool> isOnline() async => await _invoke<bool>('isOnline') ?? false;

  @override
  Future<String> sendMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      await _invoke<String>('sendMessage', <String, Object?>{
        'toAccount': toAccount,
        'payload': Uint8List.fromList(payload),
        'bizType': bizType,
        'store': store,
      }) ??
      '';

  @override
  Future<String> sendGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      await _invoke<String>('sendGroupMessage', <String, Object?>{
        'topicId': topicId,
        'payload': Uint8List.fromList(payload),
        'bizType': bizType,
        'store': store,
      }) ??
      '';

  @override
  Future<String> sendOnlineMessage({
    required String toAccount,
    required List<int> payload,
    String bizType = '',
    bool store = false,
  }) async =>
      await _invoke<String>('sendOnlineMessage', <String, Object?>{
        'toAccount': toAccount,
        'payload': Uint8List.fromList(payload),
        'bizType': bizType,
        'store': store,
      }) ??
      '';

  @override
  Future<String> sendUnlimitedGroupMessage({
    required int topicId,
    required List<int> payload,
    String bizType = '',
    bool store = true,
  }) async =>
      await _invoke<String>('sendUnlimitedGroupMessage', <String, Object?>{
        'topicId': topicId,
        'payload': Uint8List.fromList(payload),
        'bizType': bizType,
        'store': store,
      }) ??
      '';

  @override
  Future<int> createUnlimitedGroup(String topicName) async =>
      await _invoke<int>('createUnlimitedGroup', <String, Object?>{
        'topicName': topicName,
      }) ??
      0;

  @override
  Future<void> joinUnlimitedGroup(int topicId) => _invoke<void>(
      'joinUnlimitedGroup', <String, Object?>{'topicId': topicId});

  @override
  Future<void> quitUnlimitedGroup(int topicId) => _invoke<void>(
      'quitUnlimitedGroup', <String, Object?>{'topicId': topicId});

  @override
  Future<void> dismissUnlimitedGroup(int topicId) => _invoke<void>(
        'dismissUnlimitedGroup',
        <String, Object?>{'topicId': topicId},
      );

  @override
  Future<void> setRtsIncomingCallPolicy(
    MimcRtsIncomingCallPolicy policy, {
    String description = '',
  }) =>
      _invoke<void>('setRtsIncomingCallPolicy', <String, Object?>{
        'policy': policy.name,
        'description': description,
      });

  @override
  Future<void> configureRtsStream(
    MimcRtsDataType dataType,
    MimcRtsStreamConfig config,
  ) =>
      _invoke<void>('configureRtsStream', <String, Object?>{
        'dataType': dataType.name,
        ...config.toMap(),
      });

  @override
  Future<void> configureRtsBuffers({
    required int sendSize,
    required int receiveSize,
  }) =>
      _invoke<void>('configureRtsBuffers', <String, Object?>{
        'sendSize': sendSize,
        'receiveSize': receiveSize,
      });

  @override
  Future<MimcRtsBufferState> getRtsBufferState() async {
    final Map<Object?, Object?> state =
        await _invoke<Map<Object?, Object?>>('getRtsBufferState') ??
            <Object?, Object?>{};
    return MimcRtsBufferState.fromMap(state);
  }

  @override
  Future<void> clearRtsBuffers() => _invoke<void>('clearRtsBuffers');

  @override
  Future<int> dialRtsCall({
    required String toAccount,
    String toResource = '',
    List<int> appContent = const <int>[],
  }) async =>
      await _invoke<int>('dialRtsCall', <String, Object?>{
        'toAccount': toAccount,
        'toResource': toResource,
        'appContent': Uint8List.fromList(appContent),
      }) ??
      -1;

  @override
  Future<void> closeRtsCall(int callId, {String reason = ''}) =>
      _invoke<void>('closeRtsCall', <String, Object?>{
        'callId': callId,
        'reason': reason,
      });

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
      await _invoke<int>('sendRtsData', <String, Object?>{
        'callId': callId,
        'payload': Uint8List.fromList(payload),
        'dataType': dataType.name,
        'priority': priority.name,
        'canBeDropped': canBeDropped,
        'resendCount': resendCount,
        'channelType': channelType.name,
        'context': context,
      }) ??
      -1;

  @override
  Future<int> createRtsChannel({List<int> extra = const <int>[]}) async =>
      await _invoke<int>('createRtsChannel', <String, Object?>{
        'extra': Uint8List.fromList(extra),
      }) ??
      -1;

  @override
  Future<void> joinRtsChannel({
    required int callId,
    required String callKey,
  }) =>
      _invoke<void>('joinRtsChannel', <String, Object?>{
        'callId': callId,
        'callKey': callKey,
      });

  @override
  Future<void> leaveRtsChannel({
    required int callId,
    required String callKey,
  }) =>
      _invoke<void>('leaveRtsChannel', <String, Object?>{
        'callId': callId,
        'callKey': callKey,
      });

  @override
  Future<List<MimcRtsChannelMember>> getRtsChannelMembers(int callId) async {
    final List<Object?> members =
        await _invoke<List<Object?>>('getRtsChannelMembers', <String, Object?>{
              'callId': callId,
            }) ??
            <Object?>[];
    return members.whereType<Map>().map((Map member) {
      return MimcRtsChannelMember.fromMap(Map<Object?, Object?>.from(member));
    }).toList(growable: false);
  }

  @override
  Future<void> dispose() => _invoke<void>('dispose');

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw MimcException(
        error.code,
        error.message ?? 'MIMC platform call failed',
        error.details,
      );
    }
  }
}

MimcEvent _eventFromPlatform(Object? value) {
  if (value is Map<Object?, Object?>) {
    return MimcEvent.fromMap(value);
  }
  if (value is Map) {
    return MimcEvent.fromMap(Map<Object?, Object?>.from(value));
  }
  return MimcUnknownEvent(
    type: 'invalidPlatformEvent',
    data: <Object?, Object?>{'value': value},
  );
}

MimcCapability? _capabilityFromName(String name) {
  for (final MimcCapability capability in MimcCapability.values) {
    if (capability.name == name) {
      return capability;
    }
  }
  return null;
}
