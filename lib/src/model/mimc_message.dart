import 'dart:typed_data';

/// The transport channel through which a message was received.
enum MimcMessageChannel {
  direct,
  group,
  online,
  unlimitedGroup,
}

/// A binary-safe MIMC message shared by every platform implementation.
final class MimcMessage {
  MimcMessage({
    required this.payload,
    this.packetId,
    this.sequence,
    this.timestamp,
    this.fromAccount,
    this.fromResource,
    this.toAccount,
    this.toResource,
    this.topicId,
    this.bizType = '',
    this.channel = MimcMessageChannel.direct,
  });

  factory MimcMessage.fromMap(Map<Object?, Object?> map) {
    final Object? payload = map['payload'];
    return MimcMessage(
      packetId: map['packetId'] as String?,
      sequence: _toInt(map['sequence']),
      timestamp: _toInt(map['timestamp']),
      fromAccount: map['fromAccount'] as String?,
      fromResource: map['fromResource'] as String?,
      toAccount: map['toAccount'] as String?,
      toResource: map['toResource'] as String?,
      topicId: _toInt(map['topicId']),
      bizType: map['bizType'] as String? ?? '',
      payload: switch (payload) {
        Uint8List value => value,
        List<Object?> value => Uint8List.fromList(value.cast<int>()),
        _ => Uint8List(0),
      },
      channel: _channelFromName(map['channel'] as String?),
    );
  }

  final String? packetId;
  final int? sequence;
  final int? timestamp;
  final String? fromAccount;
  final String? fromResource;
  final String? toAccount;
  final String? toResource;
  final int? topicId;
  final String bizType;
  final Uint8List payload;
  final MimcMessageChannel channel;

  Map<String, Object?> toMap() => <String, Object?>{
        'packetId': packetId,
        'sequence': sequence,
        'timestamp': timestamp,
        'fromAccount': fromAccount,
        'fromResource': fromResource,
        'toAccount': toAccount,
        'toResource': toResource,
        'topicId': topicId,
        'bizType': bizType,
        'payload': payload,
        'channel': channel.name,
      };
}

int? _toInt(Object? value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };

MimcMessageChannel _channelFromName(String? name) =>
    MimcMessageChannel.values
        .where((value) => value.name == name)
        .firstOrNull ??
    MimcMessageChannel.direct;

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
