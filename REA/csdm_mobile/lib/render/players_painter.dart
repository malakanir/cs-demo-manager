import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../models/csdmm_database.dart';
import '../playback/positions_at_tick.dart';
import 'view_transform.dart';

/// Colors match the desktop viewer: CT blue, T orange, red HP pie.
const ctColor = Color(0xFF378EF0);
const tColor = Color(0xFFF29423);

/// Semi-transparent red HP pie (`#d7373f99`, alpha 0x99).
const hpPieColor = Color(0x99D7373F);

/// Fallback ring color when neither the tick state nor the timeline knows the
/// player's side (no state at all).
const unknownSideColor = Color(0xFF8A8F98);

/// Circle radius in screen pixels, matching the desktop viewer.
const playerRadius = 8.0;

/// Draws every player of a round at one tick on top of the radar.
///
/// Per player: a team-colored circle (side from the tick state, falling back to
/// the timeline's first state via [RoundTimeline.sideOf], then gray), an HP pie
/// clipped to the circle when a state exists, a white yaw line (longer when
/// scoping), and the player name when [zoom] > 2.
class PlayersPainter extends CustomPainter {
  PlayersPainter({
    required this.timeline,
    required this.tick,
    required this.vt,
    required this.zoom,
    this.focusedIds = const {},
    Map<String, String> playerNames = const {},
    this.kills = const [],
  }) : playerNames = Map.unmodifiable(playerNames);

  final RoundTimeline timeline;
  final int tick;
  final ViewTransform vt;
  final double zoom;

  /// Players to highlight (a thicker outline).
  final Set<String> focusedIds;

  /// Steam ID to display name.
  final Map<String, String> playerNames;

  /// Kills to draw as an X at the victim's death position.
  final List<KillRow> kills;

  @override
  void paint(Canvas canvas, Size size) {
    for (final steamId in timeline.steamIds) {
      final player = timeline.playerAt(steamId, tick);
      if (player == null) {
        continue;
      }
      final side = player.state?.side ?? timeline.sideOf(steamId);
      final color = switch (side) {
        3 => ctColor,
        2 => tColor,
        _ => unknownSideColor,
      };
      _drawPlayer(canvas, steamId, player, color);
    }
    for (final kill in kills) {
      _drawKill(canvas, kill);
    }
  }

  void _drawPlayer(
    Canvas canvas,
    String steamId,
    PlayerAtTick player,
    Color color,
  ) {
    final center = vt.worldToScreen(Offset(player.x, player.y));
    if (!_isVisible(center, canvas)) {
      return;
    }

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = focusedIds.contains(steamId) ? 3 : 1.5
      ..color = color;
    canvas.drawCircle(center, playerRadius, outline);

    final state = player.state;
    if (state != null) {
      // HP pie: a filled wedge clipped to the circle, from 12 o'clock clockwise
      // in the direction the health depletes.
      final fraction = (state.health / 100).clamp(0.0, 1.0);
      final pie = Paint()..color = hpPieColor;
      if (fraction > 0) {
        final rect = Rect.fromCircle(center: center, radius: playerRadius);
        canvas.drawArc(
          rect,
          -math.pi / 2,
          -2 * math.pi * fraction,
          true,
          pie,
        );
      }
    }

    final lineLength = player.state?.isScoping == true
        ? playerRadius + 6
        : playerRadius;
    final yawLine = Paint()
      ..strokeWidth = 2
      ..color = const Color(0xFFFFFFFF);
    // Yaw 0 points "north" (up the screen, decreasing radar Y).
    final yawRadians = player.yaw * math.pi / 180;
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.sin(yawRadians) * lineLength,
        center.dy - math.cos(yawRadians) * lineLength,
      ),
      yawLine,
    );

    if (zoom > 2) {
      _drawName(canvas, steamId, center);
    }
  }

  void _drawName(Canvas canvas, String steamId, Offset center) {
    final name = playerNames[steamId];
    if (name == null) {
      return;
    }
    final tp = _namePainter(steamId, name);
    tp.paint(
      canvas,
      center + Offset(playerRadius + 4, -playerRadius - 4),
    );
  }

  /// One [TextPainter] per steam ID, reused across frames.
  static final Map<String, TextPainter> _namePainters = {};

  static TextPainter _namePainter(String steamId, String name) {
    return _namePainters.putIfAbsent(steamId, () {
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      return tp;
    });
  }

  void _drawKill(Canvas canvas, KillRow kill) {
    if (kill.victimX == null || kill.victimY == null) {
      return;
    }
    final center = vt.worldToScreen(Offset(kill.victimX!, kill.victimY!));
    if (!_isVisible(center, canvas)) {
      return;
    }
    const xRadius = 7.0;
    final paint = Paint()
      ..strokeWidth = 2.5
      ..color = const Color(0xFFD7373F);
    canvas.drawLine(
      center + const Offset(-xRadius, -xRadius),
      center + const Offset(xRadius, xRadius),
      paint,
    );
    canvas.drawLine(
      center + const Offset(-xRadius, xRadius),
      center + const Offset(xRadius, -xRadius),
      paint,
    );
  }

  bool _isVisible(Offset center, Canvas canvas) {
    final bounds = canvas.getDestinationClipBounds();
    if (bounds.isInfinite) {
      return true;
    }
    return bounds.contains(center);
  }

  @override
  bool shouldRepaint(covariant PlayersPainter oldDelegate) {
    return oldDelegate.tick != tick ||
        oldDelegate.vt != vt ||
        oldDelegate.zoom != zoom ||
        !setEquals(oldDelegate.focusedIds, focusedIds) ||
        !mapEquals(oldDelegate.playerNames, playerNames) ||
        !listEquals(oldDelegate.kills, kills);
  }
}
