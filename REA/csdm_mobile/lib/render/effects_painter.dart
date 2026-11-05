import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../models/csdmm_database.dart';
import '../playback/positions_at_tick.dart';
import 'view_transform.dart';

const heColor = Color(0xFF268E6C);
const smokeColor = Color(0xFF737373);
const flashColor = Color(0xFFF9A43F);
const molotovColor = Color(0xFFDA7B11);
const decoyColor = Color(0xFFF76D74);
const infernoFill = Color(0x50DA7B11);

const smokeRadius = 26.0;
const _smokeSeconds = 18;
const _decoySeconds = 15;
const _shotSeconds = 0.25;
const _shotLength = 80.0;

Color grenadeColor(String name) {
  final n = name.toLowerCase();
  if (n.contains('smoke')) return smokeColor;
  if (n.contains('flash')) return flashColor;
  if (n.contains('molotov') || n.contains('incendiary')) return molotovColor;
  if (n.contains('decoy')) return decoyColor;
  return heColor;
}

/// Grenade trajectories, smoke/decoy rings, HE/flash bursts, fires and shot
/// lines for one round at one tick. Inputs are pre-filtered to the round.
class EffectsPainter extends CustomPainter {
  EffectsPainter({
    required this.grenades,
    required this.infernos,
    required this.shots,
    required this.grenadeEvents,
    required this.tick,
    required this.tickrate,
    required this.vt,
    required this.zoom,
  });

  final List<GrenadeRow> grenades;
  final List<InfernoRow> infernos;
  final List<ShotRow> shots;
  final List<GrenadeEventRow> grenadeEvents;
  final int tick;
  final int tickrate;
  final ViewTransform vt;
  final double zoom;

  Offset _s(num x, num y) => vt.worldToScreen(Offset(x.toDouble(), y.toDouble()));

  @override
  void paint(Canvas canvas, Size size) {
    for (final inferno in infernos) {
      _drawInferno(canvas, inferno);
    }
    for (final g in grenades) {
      _drawGrenadePath(canvas, g);
    }
    for (final e in grenadeEvents) {
      _drawEvent(canvas, e);
    }
    // Shots are noise when zoomed out (UX doc).
    if (zoom >= 1) {
      for (final s in shots) {
        _drawShot(canvas, s);
      }
    }
  }

  void _drawInferno(Canvas canvas, InfernoRow inferno) {
    if (inferno.ticks.isEmpty || tick > inferno.ticks.last) return;
    final i = findLastIndexAtOrBefore(inferno.ticks, tick);
    if (i < 0 || i >= inferno.convexHulls2d.length) return;
    final hull = inferno.convexHulls2d[i];
    if (hull.length < 6) return;
    final path = Path();
    for (var k = 0; k + 1 < hull.length; k += 2) {
      final p = _s(hull[k], hull[k + 1]);
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = infernoFill);
  }

  void _drawGrenadePath(Canvas canvas, GrenadeRow g) {
    if (g.ticks.isEmpty || tick < g.ticks.first || tick > g.ticks.last) return;
    final last = findLastIndexAtOrBefore(g.ticks, tick);
    final color = grenadeColor(g.grenadeName);
    final path = Path();
    for (var i = 0; i <= last; i++) {
      final p = _s(g.x[i], g.y[i]);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
    canvas.drawCircle(_s(g.x[last], g.y[last]), 3, Paint()..color = color);
  }

  void _drawEvent(Canvas canvas, GrenadeEventRow e) {
    final elapsed = tick - e.tick;
    if (elapsed < 0) return;
    final center = _s(e.x, e.y);
    switch (e.type) {
      case 'smoke_start':
        final total = _smokeSeconds * tickrate;
        if (elapsed > total) return;
        canvas.drawCircle(center, smokeRadius, Paint()..color = smokeColor.withAlpha(0x99));
        // Ring counts down clockwise from 12 o'clock.
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: smokeRadius),
          -math.pi / 2,
          2 * math.pi * (1 - elapsed / total),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFFFFFFFF),
        );
      case 'decoy_start':
        if (elapsed > _decoySeconds * tickrate) return;
        canvas.drawCircle(
          center,
          10,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = decoyColor,
        );
      case 'he_explode' || 'flash_explode':
        // Burst fades out over one second of game time.
        if (elapsed > tickrate) return;
        final color = e.type == 'he_explode' ? heColor : flashColor;
        canvas.drawCircle(center, 20, Paint()..color = color.withValues(alpha: 1 - elapsed / tickrate));
    }
  }

  void _drawShot(Canvas canvas, ShotRow s) {
    final elapsed = tick - s.tick;
    if (elapsed < 0 || elapsed > _shotSeconds * tickrate) return;
    final progress = elapsed / (_shotSeconds * tickrate);
    final start = _s(s.x, s.y);
    final rad = s.playerYaw * math.pi / 180;
    // Same yaw convention as PlayersPainter: 0 = up the screen.
    final end = start + Offset(math.sin(rad), -math.cos(rad)) * (_shotLength * progress);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 1 - progress),
    );
  }

  @override
  bool shouldRepaint(covariant EffectsPainter old) =>
      old.tick != tick ||
      old.vt != vt ||
      old.zoom != zoom ||
      !identical(old.grenades, grenades) ||
      !identical(old.infernos, infernos) ||
      !identical(old.shots, shots) ||
      !identical(old.grenadeEvents, grenadeEvents);
}
