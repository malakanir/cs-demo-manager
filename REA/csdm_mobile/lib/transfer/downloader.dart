import 'dart:io';

import 'package:dio/dio.dart';

import 'pairing.dart';

class MatchSummary {
  const MatchSummary({
    required this.checksum,
    required this.mapName,
    required this.date,
    required this.duration,
    required this.hasPositions,
  });

  factory MatchSummary.fromJson(Map<String, dynamic> j) => MatchSummary(
        checksum: j['checksum'] as String,
        mapName: j['mapName'] as String,
        date: DateTime.parse(j['date'] as String),
        duration: (j['duration'] as num).toDouble(),
        hasPositions: j['hasPositions'] as bool,
      );

  final String checksum;
  final String mapName;
  final DateTime date;
  final double duration;
  final bool hasPositions;
}

class Downloader {
  Downloader(this.dir, {Dio? dio}) : _dio = dio ?? Dio();

  final Directory dir;
  final Dio _dio;

  Options _auth(PairingInfo p) => Options(headers: {'Authorization': 'Bearer ${p.token}'});

  Future<List<MatchSummary>> listMatches(PairingInfo p) async {
    final res = await _dio.get<List<dynamic>>('${p.baseUrl}/api/matches', options: _auth(p));
    return [for (final m in res.data!) MatchSummary.fromJson(m as Map<String, dynamic>)];
  }

  /// Downloads to `<checksum>.csdmm.part` then renames; the .part file is
  /// removed on failure or cancel so a half file is never listed as cached.
  Future<File> downloadMatch(
    PairingInfo p,
    String checksum, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final part = File('${dir.path}/$checksum.csdmm.part');
    try {
      await _dio.download(
        '${p.baseUrl}/api/matches/$checksum/export',
        part.path,
        options: _auth(p),
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
      );
      return await part.rename('${dir.path}/$checksum.csdmm');
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }
}
