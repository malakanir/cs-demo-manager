import 'dart:typed_data';

/// Builds a big-endian int32 BLOB, mirroring how csdm packs integers.
Uint8List int32Blob(List<int> values) {
  final data = ByteData(values.length * 4);
  for (var index = 0; index < values.length; index++) {
    data.setInt32(index * 4, values[index], Endian.big);
  }
  return data.buffer.asUint8List();
}

/// Builds a big-endian float32 BLOB, mirroring how csdm packs decimals.
Uint8List float32Blob(List<double> values) {
  final data = ByteData(values.length * 4);
  for (var index = 0; index < values.length; index++) {
    data.setFloat32(index * 4, values[index], Endian.big);
  }
  return data.buffer.asUint8List();
}

/// Builds a uint8 BLOB for boolean columns.
Uint8List uint8Blob(List<int> values) => Uint8List.fromList(values);

/// Returns [blob] as a sublist view starting at an arbitrary byte offset, to
/// make sure decoders use [ByteData.sublistView] instead of assuming 4-byte
/// alignment.
Uint8List unaligned(Uint8List blob) {
  final backing = Uint8List(blob.length + 3);
  backing.setRange(3, backing.length, blob);
  return Uint8List.sublistView(backing, 3);
}
