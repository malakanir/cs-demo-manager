import 'dart:io';
import 'dart:isolate';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/models/format_exception.dart';
import 'package:csdm_mobile/models/packed_timeline.dart';
import 'package:csdm_mobile/render/players_painter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blobs.dart';
import 'support/csdmm_fixture.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('csdmm_t9'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('loadAsync returns the same data as load', () async {
    final path = createFixtureCsdmm(dir);
    final sync = MatchData.load(path);
    final async = await MatchData.loadAsync(path);

    expect(async.meta, sync.meta);
    expect(async.rounds.length, sync.rounds.length);
    expect(async.kills.length, sync.kills.length);
    final a = async.positions[1]!.first.movements;
    final s = sync.positions[1]!.first.movements;
    expect(a.ticks, s.ticks);
    expect(a.xPos, s.xPos);
  });

  test('loadAsync rethrows CsdmmFormatException from the isolate', () async {
    final path = '${dir.path}/junk.csdmm';
    File(path).writeAsStringSync('not a database' * 50);
    await expectLater(MatchData.loadAsync(path), throwsA(isA<CsdmmFormatException>()));
  });

  test('100k-sample movement blobs decode off the main isolate with exact values', () async {
    const n = 100000;
    final result = await Isolate.run(() {
      final t = PackedTimeline.decodeMovements(
        ticks: int32Blob(List.generate(n, (i) => i)),
        x: float32Blob(List.generate(n, (i) => i * 0.5)),
        y: float32Blob(List<double>.filled(n, 1)),
        z: float32Blob(List<double>.filled(n, 2)),
        yaw: float32Blob(List<double>.filled(n, 3)),
        flashDurationRemaining: float32Blob(List<double>.filled(n, 0)),
        isDucking: uint8Blob(List<int>.filled(n, 0)),
        isAirborne: uint8Blob(List<int>.filled(n, 1)),
      );
      return (t.movementCount, t.xPos[n - 1], t.isAirborne[n - 1]);
    });
    expect(result, (n, (n - 1) * 0.5, 1));
  });

  test('name painters are cached per player and name', () {
    final a = PlayersPainter.namePainterFor('p1', 'Alice');
    expect(identical(a, PlayersPainter.namePainterFor('p1', 'Alice')), isTrue);
    // A renamed player gets a fresh painter instead of stale text.
    expect(identical(a, PlayersPainter.namePainterFor('p1', 'Alicia')), isFalse);
  });
}
