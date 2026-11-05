import '../models/csdmm_database.dart';
import 'positions_at_tick.dart';

/// Builds the [RoundTimeline] of one round from a [MatchData] aggregate.
///
/// Timelines are built lazily, one round at a time: decoding states dominates
/// the cost, and playback only ever needs the current round.
RoundTimeline buildRoundTimeline(MatchData data, int roundNumber) {
  final rows = data.positions[roundNumber];
  if (rows == null || rows.isEmpty) {
    return RoundTimeline(tickrate: data.tickrate, players: const []);
  }
  return RoundTimeline(
    tickrate: data.tickrate,
    players: [
      for (final row in rows)
        PlayerTimeline(
          steamId: row.playerSteamId,
          movements: row.movements,
          states: row.states,
        ),
    ],
  );
}
