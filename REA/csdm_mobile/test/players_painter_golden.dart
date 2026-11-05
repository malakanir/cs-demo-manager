import 'dart:io';
import 'dart:ui' as ui;

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/models/map_params.dart';
import 'package:csdm_mobile/models/packed_timeline.dart';
import 'package:csdm_mobile/playback/positions_at_tick.dart';
import 'package:csdm_mobile/render/players_painter.dart';
import 'package:csdm_mobile/render/view_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blobs.dart';

PackedTimeline _movements({required List<int> ticks, required List<double> x, required List<double> y}) {
  final count = ticks.length;
  return PackedTimeline.decodeMovements(
    ticks: int32Blob(ticks),
    x: float32Blob(x),
    y: float32Blob(y),
    z: float32Blob(List<double>.filled(count, 0)),
    yaw: float32Blob(List<double>.filled(count, 0)),
    flashDurationRemaining: float32Blob(List<double>.filled(count, 0)),
    isDucking: uint8Blob(List<int>.filled(count, 0)),
    isAirborne: uint8Blob(List<int>.filled(count, 0)),
  );
}

PackedTimeline _states({
  required List<int> ticks,
  required List<int> side,
  required List<int> health,
  required List<int> scoping,
}) {
  final count = ticks.length;
  return PackedTimeline.decodeStates(
    stateTicks: int32Blob(ticks),
    isAlive: uint8Blob(List<int>.filled(count, 1)),
    side: int32Blob(side),
    money: int32Blob(List<int>.filled(count, 0)),
    health: int32Blob(health),
    armor: int32Blob(List<int>.filled(count, 0)),
    hasHelmet: uint8Blob(List<int>.filled(count, 0)),
    hasBomb: uint8Blob(List<int>.filled(count, 0)),
    hasDefuseKit: uint8Blob(List<int>.filled(count, 0)),
    isScoping: uint8Blob(scoping),
    isDefusing: uint8Blob(List<int>.filled(count, 0)),
    isPlanting: uint8Blob(List<int>.filled(count, 0)),
    isGrabbingHostage: uint8Blob(List<int>.filled(count, 0)),
    activeWeaponNames: List<String>.filled(count, 'weapon_ak47'),
    equipments: List<String>.filled(count, ''),
    grenades: List<String>.filled(count, ''),
    pistols: List<String>.filled(count, ''),
    smgs: List<String>.filled(count, ''),
    rifles: List<String>.filled(count, ''),
    heavy: List<String>.filled(count, ''),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('players painter golden frame', (tester) async {
    final maps = MapParams.parseAll(
      File('assets/maps.json').readAsStringSync(),
    );
    final mirage = maps.firstWhere((map) => map.name == 'de_mirage');

    // de_mirage: position_x -3230, position_y 1713, scale 5.
    // Radar points were chosen first, then converted back to world:
    //   alice radar (200, 200) -> world (-2230, 713)
    //   bob   radar (150, 120) -> world (-2480, 1113)
    final timeline = RoundTimeline(
      tickrate: 64,
      players: [
        PlayerTimeline(
          steamId: 'alice',
          movements: _movements(
            ticks: [100, 200],
            x: [-2230, -2230],
            y: [713, 713],
          ),
          // First state has side 3 (CT), health 45 and is scoping.
          states: _states(
            ticks: [100],
            side: [3],
            health: [45],
            scoping: [1],
          ),
        ),
        PlayerTimeline(
          steamId: 'bob',
          movements: _movements(
            ticks: [100, 200],
            x: [-2480, -2480],
            y: [1113, 1113],
          ),
          // First state is at tick 200, so at the rendered tick 150 the state
          // is null while the side is still derived from the first state (2=T).
          states: _states(
            ticks: [200],
            side: [2],
            health: [100],
            scoping: [0],
          ),
        ),
      ],
    );

    // worldOrigin (100,100), screenOrigin (20,20), zoom 2.5:
    //   alice radar (200,200) -> screen ((200-100)*2.5+20) = (270, 270)
    //   bob   radar (150,120) -> screen ((50*2.5)+20, (20*2.5)+20) = (145, 70)
    final transform = ViewTransform(
      map: mirage,
      radarSize: 1024,
      worldOrigin: const Offset(100, 100),
      screenOrigin: const Offset(20, 20),
      zoom: 2.5,
    );

    final painter = PlayersPainter(
      timeline: timeline,
      tick: 150,
      vt: transform,
      zoom: 2.5,
      focusedIds: const {'alice'},
      playerNames: const {'alice': 'Alice', 'bob': 'Bob'},
      kills: const [
        KillRow(
          roundNumber: 1,
          tick: 120,
          killerSteamId: 'alice',
          victimSteamId: 'bob',
          assisterSteamId: null,
          killerSide: 3,
          victimSide: 2,
          weaponName: 'weapon_ak47',
          headshot: true,
          killerX: -2230,
          killerY: 713,
          victimX: -2480,
          victimY: 1113,
          throughSmoke: false,
          noScope: false,
          penetratedObjects: 0,
        ),
      ],
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 512, 512),
      Paint()..color = const Color(0xFF1B1F23),
    );
    painter.paint(canvas, const Size(512, 512));
    final image = await recorder.endRecording().toImage(512, 512);

    await expectLater(
      image,
      matchesGoldenFile('goldens/players_frame.png'),
    );
  });

  test('shouldRepaint compares the transform, tick and focus set', () {
    final mirage = MapParams.parseAll(
      (File('assets/maps.json').readAsStringSync()),
    ).firstWhere((map) => map.name == 'de_mirage');
    final timeline = RoundTimeline(
      tickrate: 64,
      players: [
        PlayerTimeline(
          steamId: 'alice',
          movements: _movements(ticks: [100], x: [0], y: [0]),
          states: _states(ticks: [100], side: [3], health: [100], scoping: [0]),
        ),
      ],
    );
    ViewTransform makeTransform() => ViewTransform(
      map: mirage,
      radarSize: 1024,
      worldOrigin: const Offset(10, 10),
    );
    PlayersPainter makePainter(ViewTransform transform, int tick, Set<String> focus) {
      return PlayersPainter(
        timeline: timeline,
        tick: tick,
        vt: transform,
        zoom: 1,
        focusedIds: focus,
      );
    }

    final transform = makeTransform();
    final painter = makePainter(transform, 150, const {});
    expect(painter.shouldRepaint(makePainter(makeTransform(), 150, const {})), isFalse);
    expect(painter.shouldRepaint(makePainter(makeTransform(), 151, const {})), isTrue);
    expect(painter.shouldRepaint(makePainter(makeTransform()..zoom = 2, 150, const {})), isTrue);
    expect(painter.shouldRepaint(makePainter(makeTransform(), 150, const {'alice'})), isTrue);
  });
}
