/// Immediate policy returned to the native SDK when an RTS call arrives.
///
/// Xiaomi's SDK requires the launch callback to return synchronously, so the
/// policy must be configured before the call arrives. The incoming-call event
/// is still emitted for application UI and auditing.
enum MimcRtsIncomingCallPolicy { reject, accept }

enum MimcRtsDataType { audio, video }

/// Transport selection for point-to-point RTS data.
enum MimcRtsChannelType {
  automatic,
  relay,
  p2pInternet,
  p2pIntranet,
}

/// P0 is the highest priority and P2 is the lowest.
enum MimcRtsDataPriority { p0, p1, p2 }

enum MimcRtsStreamStrategy { fec, ack }

final class MimcRtsStreamConfig {
  const MimcRtsStreamConfig({
    this.strategy = MimcRtsStreamStrategy.fec,
    this.ackWaitTimeMs = 200,
    this.encrypt = true,
  }) : assert(ackWaitTimeMs >= 0);

  final MimcRtsStreamStrategy strategy;
  final int ackWaitTimeMs;
  final bool encrypt;

  Map<String, Object?> toMap() => <String, Object?>{
        'strategy': strategy.name,
        'ackWaitTimeMs': ackWaitTimeMs,
        'encrypt': encrypt,
      };
}

final class MimcRtsBufferState {
  const MimcRtsBufferState({
    required this.sendSize,
    required this.receiveSize,
    required this.sendUsageRate,
    required this.receiveUsageRate,
  });

  factory MimcRtsBufferState.fromMap(Map<Object?, Object?> map) =>
      MimcRtsBufferState(
        sendSize: _toInt(map['sendSize']) ?? 0,
        receiveSize: _toInt(map['receiveSize']) ?? 0,
        sendUsageRate: _toDouble(map['sendUsageRate']) ?? 0,
        receiveUsageRate: _toDouble(map['receiveUsageRate']) ?? 0,
      );

  final int sendSize;
  final int receiveSize;
  final double sendUsageRate;
  final double receiveUsageRate;
}

final class MimcRtsChannelMember {
  const MimcRtsChannelMember({
    required this.appAccount,
    required this.resource,
  });

  factory MimcRtsChannelMember.fromMap(Map<Object?, Object?> map) =>
      MimcRtsChannelMember(
        appAccount: map['appAccount'] as String? ?? '',
        resource: map['resource'] as String? ?? '',
      );

  final String appAccount;
  final String resource;
}

int? _toInt(Object? value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };

double? _toDouble(Object? value) => switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
