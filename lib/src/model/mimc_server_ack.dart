/// Acknowledgement returned after the MIMC server processes a message.
final class MimcServerAck {
  const MimcServerAck({
    required this.packetId,
    this.sequence,
    this.timestamp,
    this.code = 0,
    this.description = '',
  });

  factory MimcServerAck.fromMap(Map<Object?, Object?> map) => MimcServerAck(
        packetId: map['packetId'] as String? ?? '',
        sequence: _toInt(map['sequence']),
        timestamp: _toInt(map['timestamp']),
        code: _toInt(map['code']) ?? 0,
        description:
            map['description'] as String? ?? map['desc'] as String? ?? '',
      );

  final String packetId;
  final int? sequence;
  final int? timestamp;
  final int code;
  final String description;
}

int? _toInt(Object? value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };
