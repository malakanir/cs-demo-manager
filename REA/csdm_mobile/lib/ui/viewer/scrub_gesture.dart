import 'package:flutter/material.dart';

/// Dragging more than this many dp above the track switches to fine scrub.
const fineScrubThreshold = 24.0;

/// Fine scrub moves the playhead this many times slower than the finger.
const fineScrubDamping = 4.0;

/// Pure scrub math: absolute position on the track, or damped relative
/// movement once the finger is dragged up away from it.
class FineScrub {
  double _percent = 0;
  double? _anchorX;
  double? _anchorBase;

  double start(double x, double width) {
    _anchorX = null;
    _anchorBase = null;
    return _percent = (x / width).clamp(0.0, 1.0);
  }

  double update({required double x, required double y, required double width}) {
    if (y < -fineScrubThreshold) {
      // Keep the playhead where it was when the finger left the track.
      final anchor = _anchorX ??= x;
      final base = _anchorBase ??= _percent;
      return _percent = (base + (x - anchor) / width / fineScrubDamping).clamp(0.0, 1.0);
    }
    _anchorX = null;
    _anchorBase = null;
    return _percent = (x / width).clamp(0.0, 1.0);
  }
}

/// Horizontal scrub track. Owns its pan recognizer so a drag that starts on
/// the track never reaches the canvas behind it.
class ScrubTrack extends StatefulWidget {
  const ScrubTrack({super.key, required this.painter, required this.onSeek});

  final CustomPainter painter;
  final void Function(double percent) onSeek;

  @override
  State<ScrubTrack> createState() => _ScrubTrackState();
}

class _ScrubTrackState extends State<ScrubTrack> {
  final _scrub = FineScrub();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => widget.onSeek(_scrub.start(d.localPosition.dx, width)),
          onPanUpdate: (d) => widget.onSeek(
            _scrub.update(x: d.localPosition.dx, y: d.localPosition.dy, width: width),
          ),
          onTapUp: (d) => widget.onSeek(_scrub.start(d.localPosition.dx, width)),
          child: CustomPaint(painter: widget.painter, child: const SizedBox.expand()),
        );
      },
    );
  }
}
