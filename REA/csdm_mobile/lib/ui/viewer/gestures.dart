import 'package:flutter/material.dart';

import '../../render/view_transform.dart';

/// Pan / pinch handling over the radar canvas with zoom-at-touch.
///
/// Zoom-at-touch: while pinching, the world (radar-space) point under the
/// gesture focal point is kept stationary on screen. One-finger drags pan by
/// shifting [ViewTransform.worldOrigin]. Zoom stays clamped to 0.1-5 by
/// [ViewTransform.zoom].
///
/// The helper mutates the transform in place (it is a mutable value object
/// owned by the screen state) and reports it back so the screen can repaint.
class CanvasGestures {
  CanvasGestures({this.onTransform});

  final void Function(ViewTransform transform)? onTransform;

  Offset? _focal;

  void apply(ViewTransform transform, ScaleUpdateDetails details) {
    final focal = details.localFocalPoint;
    if (details.scale != 1) {
      final screenOrigin = transform.screenOrigin;
      // Radar-space point currently under the fingers.
      final radarUnderFocal =
          (focal - screenOrigin) / transform.zoom + transform.worldOrigin;
      transform.zoom *= details.scale;
      transform.worldOrigin =
          radarUnderFocal - (focal - screenOrigin) / transform.zoom;
    } else {
      final delta = focal - (_focal ?? focal);
      if (delta != Offset.zero) {
        transform.worldOrigin -= delta / transform.zoom;
      }
    }
    _focal = focal;
    onTransform?.call(transform);
  }
}
