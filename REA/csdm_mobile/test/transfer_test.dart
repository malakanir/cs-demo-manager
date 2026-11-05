import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csdm_mobile/transfer/downloader.dart';
import 'package:csdm_mobile/transfer/library.dart';
import 'package:csdm_mobile/transfer/pairing.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    last = o;
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('PairingInfo.parse', () {
    test('valid url', () {
      final p = PairingInfo.parse('http://192.168.1.5:8080/#/abc123')!;
      expect(p.baseUrl, 'http://192.168.1.5:8080');
      expect(p.token, 'abc123');
    });
    test('rejects garbage, missing fragment, wrong scheme', () {
      expect(PairingInfo.parse('not a url'), isNull);
      expect(PairingInfo.parse('http://192.168.1.5:8080/'), isNull);
      expect(PairingInfo.parse('http://192.168.1.5:8080/#/'), isNull);
      expect(PairingInfo.parse('ftp://192.168.1.5/#/x'), isNull);
    });
  });

  group('Downloader', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('csdm_dl'));
    tearDown(() => dir.deleteSync(recursive: true));
    const pair = PairingInfo(baseUrl: 'http://h:1', token: 'tok');

    test('downloads, reports progress, renames .part and sends bearer', () async {
      final bytes = Uint8List.fromList(List.generate(100, (i) => i));
      final adapter = _Adapter((_) => ResponseBody.fromBytes(bytes, 200, headers: {
            Headers.contentLengthHeader: ['100'],
          }));
      final dio = Dio()..httpClientAdapter = adapter;
      var lastReceived = 0;
      final file = await Downloader(dir, dio: dio)
          .downloadMatch(pair, 'abc', onProgress: (r, t) => lastReceived = r);
      expect(file.path, '${dir.path}/abc.csdmm');
      expect(file.readAsBytesSync(), bytes);
      expect(lastReceived, 100);
      expect(File('${dir.path}/abc.csdmm.part').existsSync(), isFalse);
      expect(adapter.last!.headers['Authorization'], 'Bearer tok');
      expect(Library(dir).listCached(), ['abc']);
    });

    test('cancel leaves no .part and no cached entry', () async {
      final adapter = _Adapter((_) => ResponseBody(
          Stream<Uint8List>.fromFuture(Completer<Uint8List>().future), 200));
      final dio = Dio()..httpClientAdapter = adapter;
      final token = CancelToken();
      final f = Downloader(dir, dio: dio).downloadMatch(pair, 'abc', cancelToken: token);
      Timer(const Duration(milliseconds: 50), () => token.cancel());
      await expectLater(f, throwsA(isA<DioException>()));
      expect(Directory(dir.path).listSync(), isEmpty);
    });

    test('listMatches parses summaries', () async {
      final body = jsonEncode([
        {'checksum': 'abc', 'mapName': 'de_mirage', 'date': '2026-01-01T00:00:00.000Z', 'duration': 1800.5, 'tickrate': 64, 'hasPositions': true},
      ]);
      final dio = Dio()
        ..httpClientAdapter = _Adapter((_) => ResponseBody.fromString(body, 200, headers: {
              Headers.contentTypeHeader: ['application/json'],
            }));
      final list = await Downloader(dir, dio: dio).listMatches(pair);
      expect(list.single.mapName, 'de_mirage');
      expect(list.single.hasPositions, isTrue);
    });
  });
}
