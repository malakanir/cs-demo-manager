import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'view_transform.dart';

/// Draws the full radar image through a [ViewTransform].
///
/// The radar is stretched to `transform.scaledRadarSize` screen pixels, with
/// its top-left corner placed at `screenOrigin - worldOrigin * zoom`, so a
/// [PlayersPainter] using the same transform lines up pixel-perfectly.
class RadarPainter extends CustomPainter {
  RadarPainter({required this.radar, required this.vt});

  final ui.Image radar;
  final ViewTransform vt;

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = Offset(
      vt.screenOrigin.dx - vt.worldOrigin.dx * vt.zoom,
      vt.screenOrigin.dy - vt.worldOrigin.dy * vt.zoom,
    );
    canvas.drawImageRect(
      radar,
      Rect.fromLTWH(0, 0, radar.width.toDouble(), radar.height.toDouble()),
      Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        vt.scaledRadarSize,
        vt.scaledRadarSize,
        ),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return radar != oldDelegate.radar || vt != oldDelegate.vt;
  }
}
