import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/csdmm_database.dart';
import '../playback/playback_clock.dart';
import '../playback/positions_at_tick.dart';
import '../playback/round_timeline_builder.dart';

/// Immutable playback state of the viewer.
class PlaybackState {
  const PlaybackState({
    required this.tickrate,
    required this.roundNumber,
    required this.tick,
    required this.isPlaying,
    required this.speed,
    required this.atRoundEnd,
    required this.timeline,
  });

  final int tickrate;

  /// Round currently played (1-based, as stored in the file).
  final int roundNumber;
  final int tick;
  final bool isPlaying;

  /// 0.5 - 4.
  final double speed;

  /// True once [tick] reached `end_officially_tick`; playback stops there.
  final bool atRoundEnd;

  /// Positions of the current round, or null when the round has none.
  final RoundTimeline? timeline;

  RoundRow? roundFor(List<RoundRow> rounds) {
    for (final round in rounds) {
      if (round.roundNumber == roundNumber) {
        return round;
      }
    }
    return null;
  }

  PlaybackState copyWith({
    int? roundNumber,
    int? tick,
    bool? isPlaying,
    double? speed,
    bool? atRoundEnd,
    RoundTimeline? timeline,
  }) {
    return PlaybackState(
      tickrate: tickrate,
      roundNumber: roundNumber ?? this.roundNumber,
      tick: tick ?? this.tick,
      isPlaying: isPlaying ?? this.isPlaying,
      speed: speed ?? this.speed,
      atRoundEnd: atRoundEnd ?? this.atRoundEnd,
      timeline: timeline ?? this.timeline,
    );
  }
}

/// Match handed to the viewer (overridden per screen with the loaded file).
class ViewerPlayback {
  const ViewerPlayback({required this.data, required this.tickrate});

  final MatchData data;
  final int tickrate;
}

final playbackDataProvider = Provider<ViewerPlayback>(
  (ref) => throw UnimplementedError(
    'Override playbackDataProvider with the loaded MatchData',
  ),
);

/// Owns the playback clock. The screen drives [PlaybackController.tickAt]
/// from a [Ticker]; the controller itself never starts one, which keeps it
/// testable without fake async.
class PlaybackController extends Notifier<PlaybackState> {
  PlaybackClock? _clock;

  RoundRow? _roundOf(int number) {
    final rounds = ref.read(playbackDataProvider).data.rounds;
    for (final round in rounds) {
      if (round.roundNumber == number) {
        return round;
      }
    }
    return null;
  }

  @override
  PlaybackState build() {
    final playback = ref.read(playbackDataProvider);
    final data = playback.data;
    final first = data.rounds.first;
    _clock = PlaybackClock(playback.tickrate);
    _clock!.reset(first.freezeTimeEndTick);
    return PlaybackState(
      tickrate: playback.tickrate,
      roundNumber: first.roundNumber,
      tick: first.freezeTimeEndTick,
      isPlaying: false,
      speed: 1.0,
      atRoundEnd: false,
      timeline: data.hasPositions
          ? buildRoundTimeline(data, first.roundNumber)
          : null,
    );
  }

  /// Advances the tick for one animation frame. Does nothing while paused.
  void tickAt(int deltaMs) {
    final current = state;
    if (!current.isPlaying || current.atRoundEnd) {
      return;
    }
    final tick = _clock!.advance(deltaMs, current.speed);
    final round = _roundOf(current.roundNumber)!;
    final end = round.endOfficiallyTick;
    if (tick >= end) {
      _clock!.reset(end);
      state = current.copyWith(tick: end, isPlaying: false, atRoundEnd: true);
      return;
    }
    state = current.copyWith(tick: tick);
  }

  void toggle() {
    final current = state;
    // Nothing to play at the very end: user pauses/rewinds first.
    if (!current.isPlaying && current.atRoundEnd) {
      return;
    }
    state = current.copyWith(isPlaying: !current.isPlaying);
  }

  /// Desktop formula: `floor(percent * (end - start)) + start`.
  void seekToPercent(double percent) {
    final current = state;
    final round = _roundOf(current.roundNumber)!;
    final start = round.startTick;
    final end = round.endOfficiallyTick;
    final tick = (percent.clamp(0.0, 1.0) * (end - start)).floor() + start;
    _clock!.reset(tick);
    state = current.copyWith(
      tick: tick,
      atRoundEnd: tick >= end,
      // Seeking while stopped at the end rewinds into playable territory.
      isPlaying: current.atRoundEnd && tick < end ? false : current.isPlaying,
    );
  }

  void selectRound(int roundNumber) {
    final current = state;
    if (current.roundNumber == roundNumber) {
      return;
    }
    final round = _roundOf(roundNumber);
    if (round == null) {
      return;
    }
    final data = ref.read(playbackDataProvider).data;
    _clock!.reset(round.freezeTimeEndTick);
    state = PlaybackState(
      tickrate: current.tickrate,
      roundNumber: roundNumber,
      tick: round.freezeTimeEndTick,
      isPlaying: false,
      speed: current.speed,
      atRoundEnd: false,
      timeline: data.hasPositions
          ? buildRoundTimeline(data, roundNumber)
          : null,
    );
  }

  void setSpeed(double speed) {
    state = state.copyWith(speed: speed.clamp(0.5, 4.0));
  }
}

final playbackControllerProvider = NotifierProvider<PlaybackController,
    PlaybackState>(PlaybackController.new);
