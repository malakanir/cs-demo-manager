/// Thrown when a `.csdmm` file cannot be read: truncated/corrupt SQLite data,
/// an unsupported `format_version`, or blobs that fail to decode.
class CsdmmFormatException implements Exception {
  const CsdmmFormatException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
