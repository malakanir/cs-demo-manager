import 'dart:io';

import 'package:csdm_mobile/models/map_params.dart';
import 'package:csdm_mobile/render/view_transform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real bundled `assets/maps.json` so the transform is pinned against
/// the same numbers the app ships with.
MapParams mirage() {
  final jsonText = File('assets/maps.json').readAsStringSync();
  final maps = MapParams.parseAll(jsonText);
  return maps.firstWhere((map) => map.name == 'de_mirage');
}

void main() {
  // de_mirage from assets/maps.json:
  //   position_x = -3230, position_y = 1713, scale = 5.0
  // Radar image is 1024x1024 (verified against the copied PNG).
  //
  // Hand computed sample point: world (-730, -287)
  //   radar x = (x - position_x) / scale = (-730 - (-3230)) / 5 = 2500 / 5 = 500
  //   radar y = (position_y - y) / scale = (1713 - (-287)) / 5  = 2000 / 5 = 400
  final map = mirage();
  const radarSize = 1024.0;

  group('worldToRadar', () {
    test('maps a known de_mirage world point to hand-computed pixels', () {
      final transform = ViewTransform(map: map, radarSize: radarSize);

      expect(
        transform.worldToRadar(-730, -287),
        const Offset(500, 400),
      );
    });

    test('flips Y: a higher world Y is a smaller radar pixel Y', () {
      final transform = ViewTransform(map: map, radarSize: radarSize);

      // Same X, increasing world Y.
      final low = transform.worldToRadar(0, 0);
      final high = transform.worldToRadar(0, 500);

      expect(high.dy, lessThan(low.dy));
      // world Y = position_y is the top edge of the radar.
      expect(transform.worldToRadar(0, map.posY).dy, 0);
      // Every radar pixel is `scale` world units.
      expect(low.dy - high.dy, closeTo(100, 1e-9));
    });

    test('scales from the natural radar size to imageSize', () {
      // A 2048px map is bundled at 2048, so imageSize == radarSize keeps
      // natural pixels. Rendering a 1024px radar at 512 still maps the centre.
      final transform = ViewTransform(
        map: map,
        radarSize: radarSize,
        imageSize: 512,
      );

      expect(
        transform.worldToRadar(-730, -287),
        const Offset(250, 200),
      );
    });
  });

  group('worldToScreen / screenToWorld', () {
    test('applies worldOrigin, zoom and screenOrigin in radar space', () {
      final transform = ViewTransform(
        map: map,
        radarSize: radarSize,
        worldOrigin: const Offset(100, 50),
        screenOrigin: const Offset(10, 20),
        zoom: 2,
      );

      // radar (-730, -287) = (500, 400)
      // screen x = (500 - 100) * 2 + 10 = 810
      // screen y = (400 -  50) * 2 + 20 = 720
      expect(
        transform.worldToScreen(const Offset(-730, -287)),
        const Offset(810, 720),
      );
    });

    test('screenToWorld is the inverse within epsilon', () {
      final transform = ViewTransform(
        map: map,
        radarSize: radarSize,
        worldOrigin: const Offset(133.5, 87.25),
        screenOrigin: const Offset(7, 11),
        zoom: 3.25,
      );

      const world = Offset(-1234.5, 987.25);
      final roundTripped = transform.screenToWorld(
        transform.worldToScreen(world),
      );

      expect(roundTripped.dx, closeTo(world.dx, 1e-9));
      expect(roundTripped.dy, closeTo(world.dy, 1e-9));
    });
  });

  group('zoom clamp', () {
    test('clamps constructor zoom to 0.1..5', () {
      expect(
        ViewTransform(map: map, radarSize: radarSize, zoom: 0.01).zoom,
        0.1,
      );
      expect(
        ViewTransform(map: map, radarSize: radarSize, zoom: 12).zoom,
        5,
      );
      expect(
        ViewTransform(map: map, radarSize: radarSize, zoom: 2.5).zoom,
        2.5,
      );
    });

    test('clamps zoom assignments and exposes the bounds', () {
      final transform = ViewTransform(map: map, radarSize: radarSize)
        ..zoom = 0.05;
      expect(transform.zoom, 0.1);
      transform.zoom = 9;
      expect(transform.zoom, 5);
      expect(ViewTransform.minZoom, 0.1);
      expect(ViewTransform.maxZoom, 5);
      expect(ViewTransform.clampZoom(0.001), 0.1);
      expect(ViewTransform.clampZoom(42), 5);
    });
  });
}
