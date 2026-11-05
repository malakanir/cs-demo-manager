import 'dart:io';
import 'dart:ui' as ui;

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/models/map_params.dart';
import 'package:csdm_mobile/models/packed_timeline.dart';
import 'package:csdm_mobile/render/effects_painter.dart';
import 'package:csdm_mobile/render/view_transform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blobs.dart';

// de_mirage: position_x -3230, position_y 1713, scale 5 -> radar (200,200) = world (-2230, 713).
const _eventTick = 1000;

EffectsPainter _painter(ViewTransform vt, int tick) {
  return EffectsPainter(
    tickrate: 64,
    tick: tick,
    vt: vt,
    zoom: vt.zoom,
    grenades: [
      GrenadeRow(
        roundNumber: 1,
        grenadeId: 'g1',
        projectileId: 'p1',
        grenadeName: 'HE Grenade',
        throwerSteamId: 'a',
        throwerSide: 3,
        ticks: decodeInt32Blob(int32Blob([900, 950, 1000, 1100])),
        x: decodeFloat32Blob(float32Blob([-2730, -2630, -2480, -2480])),
        y: decodeFloat32Blob(float32Blob([713, 813, 913, 913])),
        z: decodeFloat32Blob(float32Blob([0, 0, 0, 0])),
      ),
    ],
    infernos: [
      InfernoRow(
        roundNumber: 1,
        uniqueId: 'i1',
        throwerSteamId: 'a',
        ticks: decodeInt32Blob(int32Blob([1000, 1200])),
        convexHulls2d: const [
          [-2230, 713, -2130, 713, -2180, 813],
          [-2230, 713, -2130, 713, -2180, 813],
        ],
      ),
    ],
    shots: const [],
    grenadeEvents: const [
      GrenadeEventRow(roundNumber: 1, tick: _eventTick, type: 'he_explode', x: -2480, y: 913, grenadeId: 'g1'),
      GrenadeEventRow(roundNumber: 1, tick: _eventTick, type: 'smoke_start', x: -2230, y: 1113, grenadeId: 's1'),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mirage = MapParams.parseAll(File('assets/maps.json').readAsStringSync()).firstWhere((m) => m.name == 'de_mirage');
  ViewTransform vt() => ViewTransform(
        map: mirage,
        radarSize: 1024,
        worldOrigin: const Offset(100, 100),
        screenOrigin: const Offset(20, 20),
        zoom: 2.5,
      );

  Future<ui.Image> render(int tick) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 512, 512), Paint()..color = const Color(0xFF1B1F23));
    _painter(vt(), tick).paint(canvas, const Size(512, 512));
    return recorder.endRecording().toImage(512, 512);
  }

  testWidgets('effects at event tick', (tester) async {
    await expectLater(await render(_eventTick), matchesGoldenFile('goldens/effects_t0.png'));
  });

  testWidgets('effects one second later (burst faded, smoke ring shorter)', (tester) async {
    await expectLater(await render(_eventTick + 64), matchesGoldenFile('goldens/effects_t1.png'));
  });

  test('grenade colors per type', () {
    expect(grenadeColor('Smoke Grenade'), smokeColor);
    expect(grenadeColor('Flashbang'), flashColor);
    expect(grenadeColor('Molotov'), molotovColor);
    expect(grenadeColor('Incendiary Grenade'), molotovColor);
    expect(grenadeColor('Decoy Grenade'), decoyColor);
    expect(grenadeColor('HE Grenade'), heColor);
  });
}
