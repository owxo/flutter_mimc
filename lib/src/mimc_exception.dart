/// An error reported by a MIMC platform implementation.
final class MimcException implements Exception {
  const MimcException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'MimcException($code, $message)';
}
