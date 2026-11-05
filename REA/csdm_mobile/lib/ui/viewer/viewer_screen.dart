import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/csdmm_database.dart';
import '../../models/map_params.dart';
import '../../playback/playback_controller.dart';
import '../../render/effects_painter.dart';
import '../../render/players_painter.dart';
import '../../render/radar_painter.dart';
import '../../render/view_transform.dart';
import 'gestures.dart';
import 'kill_feed.dart';
import 'teams_panel.dart';
import 'playback_bar.dart';

/// Chrome auto-hides this long after the last touch while playing.
const chromeHideDelay = Duration(seconds: 3);
const playbackBarHeight = 64.0;
const roundsRailWidth = 56.0;

/// Formats ticks as a m:ss countdown at [tickrate].
String formatRemaining(int ticks, int tickrate) {
  final seconds = ticks / tickrate;
  final minutes = seconds.floor() ~/ 60;
  final rest = (seconds.floor() % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// Decodes the bundled radar PNG into a [ui.Image], cached by checksum.
final radarImageProvider = FutureProvider<ui.Image>((ref) async {
  final data = await rootBundle.load('assets/radars/cs2/de_mirage.png');
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    data.buffer.asUint8List(),
  );
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final codec = await descriptor.instantiateCodec();
  return (await codec.getNextFrame()).image;
});

/// The 2D replay viewer: full-bleed radar canvas, floating chrome,
/// landscape-first.
class _RoundEffects {
  const _RoundEffects({
    required this.grenades,
    required this.infernos,
    required this.shots,
    required this.grenadeEvents,
  });

  final List<GrenadeRow> grenades;
  final List<InfernoRow> infernos;
  final List<ShotRow> shots;
  final List<GrenadeEventRow> grenadeEvents;
}

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.checksum});

  final String checksum;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen>
    with TickerProviderStateMixin {
  Ticker? _ticker;
  Duration? _previousElapsed;
  ViewTransform? _transform;
  bool _chromeVisible = true;
  Timer? _hideTimer;
  MapParams? _map;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _map = MapParams.forMap(ref.read(playbackDataProvider).data.mapName);
    // Map params are loaded once per app start; in tests/isolation the cache
    // may still be empty, so load the asset on demand and rebuild.
    if (_map == null) {
      MapParams.loadFromAsset().then((_) {
        if (mounted) {
          setState(() => _map = MapParams.forMap(
                ref.read(playbackDataProvider).data.mapName,
              ));
        }
      });
    }
    // The ticker only runs while playing: an always-muted ticker would keep
    // pumping frames and never let pumpAndSettle finish in tests.
    _ticker = createTicker(_onTick);
    _scheduleHide();
  }

  /// Ticker wiring: the screen owns the frame loop and pushes elapsed
  /// wall-clock deltas into the controller, which owns all playback logic.
  /// This keeps the controller pure (no SchedulerBinding) and testable.
  void _onTick(Duration elapsed) {
    if (_disposed) {
      return;
    }
    final previous = _previousElapsed;
    _previousElapsed = elapsed;
    if (previous == null) {
      return;
    }
    ref
        .read(playbackControllerProvider.notifier)
        .tickAt(elapsed.inMilliseconds - previous.inMilliseconds);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(chromeHideDelay, () {
      if (mounted && ref.read(playbackControllerProvider).isPlaying) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  final Set<String> _focused = {};

  void _onCanvasTap(Offset position) {
    if (!_chromeVisible) {
      // First touch on hidden chrome only reveals it (no accidental scrub).
      setState(() => _chromeVisible = true);
      _scheduleHide();
      return;
    }
    final state = ref.read(playbackControllerProvider);
    final vt = _transform;
    final timeline = state.timeline;
    if (vt != null && timeline != null) {
      final hit = hitTestPlayer(timeline: timeline, tick: state.tick, vt: vt, screen: position);
      if (hit != null) {
        // Tap a player to focus it (thicker ring + name); tap again to clear.
        setState(() => _focused.contains(hit) ? _focused.remove(hit) : _focused.add(hit));
        return;
      }
    }
    if (ref.read(playbackControllerProvider).isPlaying) {
      setState(() => _chromeVisible = false);
      _hideTimer?.cancel();
    }
  }

  void _onInteraction() {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.dispose();
    _hideTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackControllerProvider);
    final data = ref.read(playbackDataProvider).data;

    // Drive the frame loop only while playing.
    final ticker = _ticker;
    if (ticker == null) {
      // Ticker disposed early (widget being torn down); skip.
    } else if (state.isPlaying && !ticker.isActive) {
      _previousElapsed = null;
      ticker.start();
    } else if (!state.isPlaying && ticker.isActive) {
      ticker.stop();
    }

    final map = _map;
    if (map == null) {
      return const Scaffold(body: Center(child: Text('Unsupported map')));
    }
    final timeline = state.timeline;
    if (timeline == null) {
      return const Scaffold(body: Center(child: Text('No positions')));
    }
    final radar = ref.watch(radarImageProvider).value;
    if (radar == null) {
      return const ColoredBox(color: Color(0xFF1B1F23));
    }

    // Desktop parity: X marks for every kill of the current round up to the
    // current tick (they stay visible for the rest of the round).
    final kills = data.kills
        .where(
          (k) =>
              k.roundNumber == state.roundNumber && k.tick <= state.tick,
        )
        .toList(growable: false);

    final fx = _effectsFor(data, state.roundNumber);
    final playerNames = {for (final p in data.players) p.steamId: p.name};

    return Scaffold(
      backgroundColor: const Color(0xFF1B1F23),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final vt =
              _transform ??= _initialTransform(map, constraints.biggest, radar);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onCanvasTap(d.localPosition),
                  onScaleStart: (_) => _onInteraction(),
                  onScaleUpdate: (details) {
                    _onInteraction();
                    setState(() {
                      CanvasGestures().apply(vt, details);
                    });
                  },
                  child: CustomPaint(
                    painter: RadarPainter(radar: radar, vt: vt),
                    foregroundPainter: PlayersPainter(
                      timeline: timeline,
                      tick: state.tick,
                      vt: vt,
                      zoom: vt.zoom,
                      kills: kills,
                      focusedIds: _focused,
                      playerNames: playerNames,
                    ),
                    child: CustomPaint(
                      painter: EffectsPainter(
                        grenades: fx.grenades,
                        infernos: fx.infernos,
                        shots: fx.shots,
                        grenadeEvents: fx.grenadeEvents,
                        tick: state.tick,
                        tickrate: state.tickrate,
                        vt: vt,
                        zoom: vt.zoom,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              // Kill feed: top-right, max 45% width, below the timer row.
              Positioned(
                top: 8,
                right: 8,
                width: constraints.biggest.width * 0.45,
                child: IgnorePointer(
                  child: KillFeed(
                    kills: visibleKills(
                      data.kills.where((k) => k.roundNumber == state.roundNumber).toList(growable: false),
                      state.tick,
                      state.tickrate,
                    ),
                    names: playerNames,
                  ),
                ),
              ),
              // Timer pill: always visible, even when chrome hides.
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: TimerPill(
                    remainingTicks:
                        state.roundFor(data.rounds)!.endOfficiallyTick -
                            state.tick,
                    tickrate: state.tickrate,
                  ),
                ),
              ),
              if (_chromeVisible) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: RoundsRail(state: state),
                ),
                // Teams panel sits below the kill feed (4 rows max).
                Positioned(
                  right: 8,
                  top: 120,
                  bottom: 96,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: TeamsPanel(
                      players: data.players,
                      timeline: timeline,
                      tick: state.tick,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: PlaybackBar(
                      width: constraints.biggest.width * 0.7,
                      height: playbackBarHeight,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  int? _fxRound;
  late _RoundEffects _fx;

  /// Round-filtered effect lists, rebuilt only when the round changes so the
  /// painter's identity-based shouldRepaint stays cheap.
  _RoundEffects _effectsFor(MatchData data, int round) {
    if (_fxRound != round) {
      final e = data.effects;
      _fx = _RoundEffects(
        grenades: e.grenades.where((g) => g.roundNumber == round).toList(growable: false),
        infernos: e.infernos.where((g) => g.roundNumber == round).toList(growable: false),
        shots: e.shots.where((g) => g.roundNumber == round).toList(growable: false),
        grenadeEvents: e.grenadeEvents.where((g) => g.roundNumber == round).toList(growable: false),
      );
      _fxRound = round;
    }
    return _fx;
  }

  ViewTransform _initialTransform(MapParams map, Size size, ui.Image radar) {
    final imageSize = radar.width.toDouble();
    final vt = ViewTransform(
      map: map,
      radarSize: imageSize,
      imageSize: imageSize,
      zoom: 1,
    );
    // Fit the square radar to the canvas height, centered horizontally.
    final zoom = ViewTransform.clampZoom(size.height / imageSize);
    vt
      ..zoom = zoom
      ..screenOrigin = Offset(
        (size.width - imageSize * zoom) / 2,
        (size.height - imageSize * zoom) / 2,
      )
      ..worldOrigin = Offset.zero;
    return vt;
  }
}
