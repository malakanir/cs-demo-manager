import 'dart:io';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/models/format_exception.dart';
import 'package:csdm_mobile/playback/playback_controller.dart';
import 'package:csdm_mobile/ui/unsupported_map_screen.dart';
import 'package:csdm_mobile/ui/viewer/viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/csdmm_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('csdmm_t8'));
  tearDown(() => dir.deleteSync(recursive: true));

  void update(String path, String sql) {
    final db = sqlite3.open(path);
    db.execute(sql);
    db.close();
  }

  group('file ingestion errors', () {
    test('truncated file throws CsdmmFormatException', () {
      final path = createFixtureCsdmm(dir);
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, 100));
      expect(() => MatchData.load(path), throwsA(isA<CsdmmFormatException>()));
    });

    test('non-sqlite file throws CsdmmFormatException', () {
      final path = '${dir.path}/junk.csdmm';
      File(path).writeAsStringSync('this is definitely not a database' * 20);
      expect(() => MatchData.load(path), throwsA(isA<CsdmmFormatException>()));
    });

    test('empty file throws CsdmmFormatException', () {
      final path = '${dir.path}/empty.csdmm';
      File(path).writeAsBytesSync([]);
      expect(() => MatchData.load(path), throwsA(isA<CsdmmFormatException>()));
    });

    test('wrong format_version throws with the version in the message', () {
      final path = createFixtureCsdmm(dir);
      update(path, "UPDATE match SET value = '2' WHERE key = 'format_version'");
      expect(
        () => MatchData.load(path),
        throwsA(isA<CsdmmFormatException>().having((e) => e.reason, 'reason', contains('version 2'))),
      );
    });

    test('missing format_version throws', () {
      final path = createFixtureCsdmm(dir);
      update(path, "DELETE FROM match WHERE key = 'format_version'");
      expect(() => MatchData.load(path), throwsA(isA<CsdmmFormatException>()));
    });

    test('valid file still loads', () {
      expect(MatchData.load(createFixtureCsdmm(dir)).mapName, fixtureMapName);
    });
  });

  group('viewer', () {
    Future<void> pumpViewer(WidgetTester tester, MatchData data) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playback = ViewerPlayback(data: data, tickrate: data.tickrate);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackDataProvider.overrideWith((ref) => playback)],
          child: MaterialApp(home: ViewerScreen(checksum: data.checksum)),
        ),
      );
      // Let the map asset + radar image futures resolve on a real event loop.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    testWidgets('map without a radar asset shows the unsupported screen', (tester) async {
      final path = createFixtureCsdmm(dir);
      update(path, "UPDATE match SET value = 'de_nowhere' WHERE key = 'map_name'");
      final data = MatchData.load(path);

      await pumpViewer(tester, data);

      expect(find.byType(UnsupportedMapScreen), findsOneWidget);
      expect(find.textContaining('de_nowhere'), findsOneWidget);
    });

    testWidgets('viewer sets landscape on push and restores portrait on pop', (tester) async {
      final calls = <List<dynamic>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          calls.add(call.arguments as List<dynamic>);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final data = MatchData.load(createFixtureCsdmm(dir));
      await pumpViewer(tester, data);
      expect(calls.last, containsAll(['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']));
      expect(calls.last, isNot(contains('DeviceOrientation.portraitUp')));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(calls.last, ['DeviceOrientation.portraitUp']);
    });
  });
}
