import 'dart:typed_data';

import 'mimc_connection_state.dart';
import 'mimc_message.dart';
import 'mimc_rts.dart';
import 'mimc_server_ack.dart';

sealed class MimcEvent {
  const MimcEvent();

  factory MimcEvent.fromMap(Map<Object?, Object?> map) {
    final String type = map['type'] as String? ?? '';
    final Map<Object?, Object?> data = _asMap(map['data']);
    return switch (type) {
      'connectionChanged' => MimcConnectionChanged(
          state: _connectionState(data['state'] as String?),
          reason: data['reason'] as String?,
          description: data['description'] as String?,
        ),
      'message' ||
      'groupMessage' ||
      'onlineMessage' ||
      'unlimitedGroupMessage' =>
        MimcMessageReceived(MimcMessage.fromMap(data)),
      'serverAck' => MimcServerAckReceived(MimcServerAck.fromMap(data)),
      'sendMessageTimeout' ||
      'sendGroupMessageTimeout' ||
      'sendUnlimitedGroupMessageTimeout' =>
        MimcSendTimedOut(MimcMessage.fromMap(data)),
      'tokenRefreshRequired' => const MimcTokenRefreshRequired(),
      'unlimitedGroupDismissed' => MimcUnlimitedGroupDismissed(
          topicId: _toInt(data['topicId']) ?? 0,
        ),
      'offlinePullNotification' => MimcOfflinePullNotification(
          minSequence: _toInt(data['minSequence']),
          maxSequence: _toInt(data['maxSequence']),
        ),
      'rtsCallIncoming' => MimcRtsCallIncoming(
          callId: _toInt(data['callId']) ?? 0,
          fromAccount: data['fromAccount'] as String? ?? '',
          fromResource: data['fromResource'] as String? ?? '',
          appContent: _toBytes(data['appContent']),
          acceptedByPolicy: data['accepted'] as bool? ?? false,
        ),
      'rtsCallAnswered' => MimcRtsCallAnswered(
          callId: _toInt(data['callId']) ?? 0,
          accepted: data['accepted'] as bool? ?? false,
          description: data['description'] as String? ?? '',
        ),
      'rtsCallClosed' => MimcRtsCallClosed(
          callId: _toInt(data['callId']) ?? 0,
          description: data['description'] as String? ?? '',
        ),
      'rtsData' || 'rtsChannelData' => MimcRtsDataReceived(
          callId: _toInt(data['callId']) ?? 0,
          fromAccount: data['fromAccount'] as String? ?? '',
          fromResource: data['fromResource'] as String? ?? '',
          payload: _toBytes(data['payload']),
          dataType: _enumByName(
            MimcRtsDataType.values,
            data['dataType'],
            MimcRtsDataType.audio,
          ),
          channelType: data['channelType'] == null
              ? null
              : _enumByName(
                  MimcRtsChannelType.values,
                  data['channelType'],
                  MimcRtsChannelType.automatic,
                ),
          isChannel: type == 'rtsChannelData',
        ),
      'rtsSendData' || 'rtsChannelSendData' => MimcRtsDataSendResult(
          callId: _toInt(data['callId']) ?? 0,
          dataId: _toInt(data['dataId']) ?? -1,
          success: data['success'] as bool? ?? false,
          context: data['context'] as String?,
          isChannel: type == 'rtsChannelSendData',
        ),
      'rtsP2pResult' => MimcRtsP2pResult(
          callId: _toInt(data['callId']) ?? 0,
          result: _toInt(data['result']) ?? -1,
          selfNatType: _toInt(data['selfNatType']) ?? -1,
          peerNatType: _toInt(data['peerNatType']) ?? -1,
        ),
      'rtsChannelCreated' => MimcRtsChannelCreated(
          identity: _toInt(data['identity']) ?? -1,
          callId: _toInt(data['callId']) ?? -1,
          callKey: data['callKey'] as String? ?? '',
          success: data['success'] as bool? ?? false,
          description: data['description'] as String? ?? '',
          extra: _toBytes(data['extra']),
        ),
      'rtsChannelJoined' => MimcRtsChannelJoined(
          callId: _toInt(data['callId']) ?? -1,
          appAccount: data['appAccount'] as String? ?? '',
          resource: data['resource'] as String? ?? '',
          success: data['success'] as bool? ?? false,
          description: data['description'] as String? ?? '',
          extra: _toBytes(data['extra']),
          members: _channelMembers(data['members']),
        ),
      'rtsChannelLeft' => MimcRtsChannelLeft(
          callId: _toInt(data['callId']) ?? -1,
          appAccount: data['appAccount'] as String? ?? '',
          resource: data['resource'] as String? ?? '',
          success: data['success'] as bool? ?? false,
          description: data['description'] as String? ?? '',
        ),
      'rtsChannelUserJoined' ||
      'rtsChannelUserLeft' =>
        MimcRtsChannelMembershipChanged(
          callId: _toInt(data['callId']) ?? -1,
          appAccount: data['appAccount'] as String? ?? '',
          resource: data['resource'] as String? ?? '',
          joined: type == 'rtsChannelUserJoined',
        ),
      _ => MimcUnknownEvent(type: type, data: data),
    };
  }
}

final class MimcConnectionChanged extends MimcEvent {
  const MimcConnectionChanged({
    required this.state,
    this.reason,
    this.description,
  });

  final MimcConnectionState state;
  final String? reason;
  final String? description;
}

final class MimcMessageReceived extends MimcEvent {
  const MimcMessageReceived(this.message);

  final MimcMessage message;
}

final class MimcServerAckReceived extends MimcEvent {
  const MimcServerAckReceived(this.ack);

  final MimcServerAck ack;
}

final class MimcSendTimedOut extends MimcEvent {
  const MimcSendTimedOut(this.message);

  final MimcMessage message;
}

final class MimcTokenRefreshRequired extends MimcEvent {
  const MimcTokenRefreshRequired();
}

final class MimcUnlimitedGroupDismissed extends MimcEvent {
  const MimcUnlimitedGroupDismissed({required this.topicId});

  final int topicId;
}

final class MimcOfflinePullNotification extends MimcEvent {
  const MimcOfflinePullNotification({this.minSequence, this.maxSequence});

  final int? minSequence;
  final int? maxSequence;
}

final class MimcRtsCallIncoming extends MimcEvent {
  const MimcRtsCallIncoming({
    required this.callId,
    required this.fromAccount,
    required this.fromResource,
    required this.appContent,
    required this.acceptedByPolicy,
  });

  final int callId;
  final String fromAccount;
  final String fromResource;
  final Uint8List appContent;
  final bool acceptedByPolicy;
}

final class MimcRtsCallAnswered extends MimcEvent {
  const MimcRtsCallAnswered({
    required this.callId,
    required this.accepted,
    required this.description,
  });

  final int callId;
  final bool accepted;
  final String description;
}

final class MimcRtsCallClosed extends MimcEvent {
  const MimcRtsCallClosed({
    required this.callId,
    required this.description,
  });

  final int callId;
  final String description;
}

final class MimcRtsDataReceived extends MimcEvent {
  const MimcRtsDataReceived({
    required this.callId,
    required this.fromAccount,
    required this.fromResource,
    required this.payload,
    required this.dataType,
    required this.channelType,
    required this.isChannel,
  });

  final int callId;
  final String fromAccount;
  final String fromResource;
  final Uint8List payload;
  final MimcRtsDataType dataType;
  final MimcRtsChannelType? channelType;
  final bool isChannel;
}

final class MimcRtsDataSendResult extends MimcEvent {
  const MimcRtsDataSendResult({
    required this.callId,
    required this.dataId,
    required this.success,
    required this.context,
    required this.isChannel,
  });

  final int callId;
  final int dataId;
  final bool success;
  final String? context;
  final bool isChannel;
}

final class MimcRtsP2pResult extends MimcEvent {
  const MimcRtsP2pResult({
    required this.callId,
    required this.result,
    required this.selfNatType,
    required this.peerNatType,
  });

  final int callId;
  final int result;
  final int selfNatType;
  final int peerNatType;
}

final class MimcRtsChannelCreated extends MimcEvent {
  const MimcRtsChannelCreated({
    required this.identity,
    required this.callId,
    required this.callKey,
    required this.success,
    required this.description,
    required this.extra,
  });

  final int identity;
  final int callId;
  final String callKey;
  final bool success;
  final String description;
  final Uint8List extra;
}

final class MimcRtsChannelJoined extends MimcEvent {
  const MimcRtsChannelJoined({
    required this.callId,
    required this.appAccount,
    required this.resource,
    required this.success,
    required this.description,
    required this.extra,
    required this.members,
  });

  final int callId;
  final String appAccount;
  final String resource;
  final bool success;
  final String description;
  final Uint8List extra;
  final List<MimcRtsChannelMember> members;
}

final class MimcRtsChannelLeft extends MimcEvent {
  const MimcRtsChannelLeft({
    required this.callId,
    required this.appAccount,
    required this.resource,
    required this.success,
    required this.description,
  });

  final int callId;
  final String appAccount;
  final String resource;
  final bool success;
  final String description;
}

final class MimcRtsChannelMembershipChanged extends MimcEvent {
  const MimcRtsChannelMembershipChanged({
    required this.callId,
    required this.appAccount,
    required this.resource,
    required this.joined,
  });

  final int callId;
  final String appAccount;
  final String resource;
  final bool joined;
}

final class MimcUnknownEvent extends MimcEvent {
  const MimcUnknownEvent({required this.type, required this.data});

  final String type;
  final Map<Object?, Object?> data;
}

Map<Object?, Object?> _asMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<Object?, Object?>.from(value);
  }
  return <Object?, Object?>{};
}

MimcConnectionState _connectionState(String? state) => switch (state) {
      'connecting' => MimcConnectionState.connecting,
      'online' => MimcConnectionState.online,
      _ => MimcConnectionState.offline,
    };

int? _toInt(Object? value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };

Uint8List _toBytes(Object? value) => switch (value) {
      Uint8List bytes => bytes,
      List<Object?> values => Uint8List.fromList(values.cast<int>()),
      _ => Uint8List(0),
    };

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is String) {
    for (final T value in values) {
      if (value.name == name) return value;
    }
  }
  return fallback;
}

List<MimcRtsChannelMember> _channelMembers(Object? value) {
  if (value is! List) return const <MimcRtsChannelMember>[];
  return value.whereType<Map>().map((Map member) {
    return MimcRtsChannelMember.fromMap(Map<Object?, Object?>.from(member));
  }).toList(growable: false);
}
