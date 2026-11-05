import 'dart:ui';

import '../models/map_params.dart';

/// Converts Counter-Strike world coordinates to radar image pixels and screen
/// pixels, and back.
///
/// Three coordinate spaces are involved:
///
/// * **world** — demo coordinates (units), Y pointing north.
/// * **radar** — pixels of the bundled radar image, `0..imageSize`, with the
///   origin at the top-left. The map transform (`position_x`, `position_y`,
///   `scale`) converts world to radar and flips Y:
///   `x' = (x - posX) / scale * imageSize / radarSize`,
///   `y' = (posY - y) / scale * imageSize / radarSize`.
/// * **screen** — canvas pixels. `worldOrigin` is the radar-space point drawn at
///   `screenOrigin`, and [zoom] scales radar pixels to screen pixels.
///
/// [radarSize] is the natural width/height of the radar image (1024, or 2048
/// for the maps updated in the May 9 2025 CS2 update). [imageSize] defaults to
/// [radarSize]; set it when the radar is drawn at another size.
class ViewTransform {
  ViewTransform({
    required this.map,
    required this.radarSize,
    double? imageSize,
    this.worldOrigin = Offset.zero,
    this.screenOrigin = Offset.zero,
    double zoom = 1,
  }) : imageSize = imageSize ?? radarSize,
       _zoom = clampZoom(zoom);

  static const double minZoom = 0.1;
  static const double maxZoom = 5;

  /// Map parameters (position/scale) used by [worldToRadar].
  final MapParams map;

  /// Natural radar image size in pixels (the PNG width/height).
  final double radarSize;

  /// Radar size in its rendered pixel space. Equals [radarSize] unless the
  /// radar is drawn at another resolution.
  final double imageSize;

  /// Radar-space point displayed at [screenOrigin].
  Offset worldOrigin;

  /// Screen-space position of [worldOrigin].
  Offset screenOrigin;

  double _zoom;

  /// Screen pixels per radar pixel, clamped to [minZoom]..[maxZoom].
  double get zoom => _zoom;

  set zoom(double value) => _zoom = clampZoom(value);

  static double clampZoom(double value) =>
      value.clamp(minZoom, maxZoom).toDouble();

  /// Converts world coordinates to radar image pixels.
  Offset worldToRadar(double x, double y) {
    final factor = imageSize / radarSize;
    return Offset(
      (x - map.posX) / map.scale * factor,
      (map.posY - y) / map.scale * factor,
    );
  }

  /// Converts world coordinates to canvas pixels.
  Offset worldToScreen(Offset world) {
    final radar = worldToRadar(world.dx, world.dy);
    return Offset(
      (radar.dx - worldOrigin.dx) * _zoom + screenOrigin.dx,
      (radar.dy - worldOrigin.dy) * _zoom + screenOrigin.dy,
    );
  }

  /// Converts canvas pixels back to world coordinates.
  Offset screenToWorld(Offset screen) {
    final radarX = (screen.dx - screenOrigin.dx) / _zoom + worldOrigin.dx;
    final radarY = (screen.dy - screenOrigin.dy) / _zoom + worldOrigin.dy;
    final worldPerRadar = map.scale * radarSize / imageSize;
    return Offset(
      radarX * worldPerRadar + map.posX,
      map.posY - radarY * worldPerRadar,
    );
  }

  /// Screen-space size of the radar image.
  double get scaledRadarSize => imageSize * _zoom;

  @override
  bool operator ==(Object other) {
    return other is ViewTransform &&
        other.map.name == map.name &&
        other.map.posX == map.posX &&
        other.map.posY == map.posY &&
        other.map.scale == map.scale &&
        other.radarSize == radarSize &&
        other.imageSize == imageSize &&
        other.worldOrigin == worldOrigin &&
        other.screenOrigin == screenOrigin &&
        other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hash(
    map.name,
    map.posX,
    map.posY,
    map.scale,
    radarSize,
    imageSize,
    worldOrigin,
    screenOrigin,
    zoom,
  );
}
