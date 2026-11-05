import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/playback_controller.dart';
import 'viewer_screen.dart';

/// Bottom playback chrome: scrub bar with kill/freeze markers + play + speed.
class PlaybackBar extends ConsumerWidget {
  const PlaybackBar({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final controller = ref.read(playbackControllerProvider.notifier);
    final data = ref.read(playbackDataProvider).data;
    final round = state.roundFor(data.rounds);
    if (round == null) {
      return const SizedBox.shrink();
    }
    final span = (round.endOfficiallyTick - round.startTick).clamp(1, 1 << 31);
    final percent = ((state.tick - round.startTick) / span).clamp(0.0, 1.0);

    final kills = data.kills
        .where((k) => k.roundNumber == state.roundNumber)
        .map((k) => ((k.tick - round.startTick) / span).clamp(0.0, 1.0))
        .toList(growable: false);
    final freezePercent =
        ((round.freezeTimeEndTick - round.startTick) / span).clamp(0.0, 1.0);

    final plants = data.effects.bombEvents
        .where((b) => b.roundNumber == state.roundNumber && b.type == 'planted')
        .map((b) => ((b.tick - round.startTick) / span).clamp(0.0, 1.0))
        .toList(growable: false);

    return Container(
      key: playbackBarKey,
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0x8C000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              state.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: controller.toggle,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => controller.seekToPercent(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                  ),
                  onTapUp: (details) => controller.seekToPercent(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                  ),
                  child: CustomPaint(
                    painter: BarPainter(
                      percent: percent,
                      kills: kills,
                      freezePercent: freezePercent,
                      plants: plants,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
          SpeedButton(speed: state.speed, onSpeed: controller.setSpeed),
        ],
      ),
    );
  }
}

/// Public so tests/screens can find the bar.
final Key playbackBarKey = const Key('playback-bar');

class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key, required this.speed, required this.onSpeed});

  final double speed;
  final void Function(double) onSpeed;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      initialValue: speed,
      onSelected: onSpeed,
      itemBuilder: (context) => [
        for (final s in const [0.5, 1.0, 1.5, 2.0, 3.0, 4.0])
          PopupMenuItem(value: s, child: Text('$s×')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '$speed×',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}

class BarPainter extends CustomPainter {
  BarPainter({
    required this.percent,
    required this.kills,
    required this.freezePercent,
    this.plants = const [],
  });

  final double percent;
  final List<double> kills;
  final double freezePercent;
  final List<double> plants;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      track,
    );

    final played = Paint()
      ..color = const Color(0xFFF29423)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width * percent, size.height / 2),
      played,
    );

    final kill = Paint()..color = const Color(0xFFD7373F);
    for (final k in kills) {
      canvas.drawCircle(Offset(size.width * k, size.height / 2), 3, kill);
    }

    final plant = Paint()..color = const Color(0xFFDA7B11);
    for (final p in plants) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width * p, size.height / 2), width: 6, height: 6),
        plant,
      );
    }

    final freeze = Paint()..color = const Color(0xFF378EF0);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width * freezePercent, size.height / 2),
        width: 2,
        height: 10,
      ),
      freeze,
    );

    final thumb = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(size.width * percent, size.height / 2), 7, thumb);
  }

  @override
  bool shouldRepaint(covariant BarPainter old) =>
      old.percent != percent ||
      old.freezePercent != freezePercent ||
      old.kills.length != kills.length ||
      old.plants.length != plants.length;
}

/// Timer pill top-center; always visible even when chrome hides.
class TimerPill extends StatelessWidget {
  const TimerPill({
    super.key,
    required this.remainingTicks,
    required this.tickrate,
  });

  final int remainingTicks;
  final int tickrate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x8C000000),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        formatRemaining(remainingTicks, tickrate),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Vertical rounds rail on the left edge; tap selects the round.
class RoundsRail extends ConsumerWidget {
  const RoundsRail({super.key, required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.read(playbackDataProvider).data;
    return Container(
      width: roundsRailWidth,
      margin: const EdgeInsets.only(top: 48, bottom: 96),
      decoration: BoxDecoration(
        color: const Color(0x8C000000),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(12),
        ),
      ),
      child: ListView(
        children: [
          for (final round in data.rounds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: TextButton(
                onPressed: () => ref
                    .read(playbackControllerProvider.notifier)
                    .selectRound(round.roundNumber),
                style: TextButton.styleFrom(
                  backgroundColor:
                      round.roundNumber == state.roundNumber
                          ? const Color(0x33F29423)
                          : null,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 32),
                ),
                child: Text(
                  '${round.roundNumber}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: round.roundNumber == state.roundNumber
                        ? const Color(0xFFF29423)
                        : Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
