import 'dart:typed_data';

import '../models/packed_timeline.dart';

/// Interpolated position of one player at one tick.
///
/// Instances are created on demand by [RoundTimeline.playerAt]; the timeline
/// itself never materialises one object per sample.
class PlayerAtTick {
  const PlayerAtTick({
    required this.tick,
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    required this.flash,
    required this.ducking,
    required this.airborne,
    required this.state,
  });

  final int tick;
  final double x;
  final double y;
  final double z;

  /// Yaw in degrees, normalised to `[0, 360)`.
  final double yaw;

  /// Remaining flash duration in seconds.
  final double flash;

  /// Movement booleans are stepped from the previous sample, never interpolated.
  final bool ducking;
  final bool airborne;

  /// State at or before [tick], or null when the player has no state yet.
  final StateAtTick? state;
}

/// Player state at a tick. States only change when something meaningful
/// happens, so they are stepped (last sample at or before the tick) instead of
/// interpolated.
class StateAtTick {
  const StateAtTick({
    required this.tick,
    required this.isAlive,
    required this.side,
    required this.money,
    required this.health,
    required this.armor,
    required this.hasHelmet,
    required this.hasBomb,
    required this.hasDefuseKit,
    required this.isScoping,
    required this.isDefusing,
    required this.isPlanting,
    required this.isGrabbingHostage,
    required this.activeWeaponName,
    required this.equipments,
    required this.grenades,
    required this.pistols,
    required this.smgs,
    required this.rifles,
    required this.heavy,
  });

  final int tick;
  final bool isAlive;
  final int side;
  final int money;
  final int health;
  final int armor;
  final bool hasHelmet;
  final bool hasBomb;
  final bool hasDefuseKit;
  final bool isScoping;
  final bool isDefusing;
  final bool isPlanting;
  final bool isGrabbingHostage;
  final String activeWeaponName;

  /// Raw comma-separated inventory strings, exactly as stored in the file.
  final String equipments;
  final String grenades;
  final String pistols;
  final String smgs;
  final String rifles;
  final String heavy;
}

/// Per-player input of a [RoundTimeline]: movement samples plus state samples.
class PlayerTimeline {
  const PlayerTimeline({
    required this.steamId,
    required this.movements,
    required this.states,
  });

  final String steamId;
  final PackedTimeline movements;

  /// Packed timeline decoded with [PackedTimeline.decodeStates].
  final PackedTimeline states;
}

/// Positions of every player of one round, sampled at an arbitrary tick.
///
/// Build it once per round and call [playerAt] for every frame. Movement samples
/// stay in their flat typed lists; the only allocation per query is the
/// returned [PlayerAtTick] (states are decoded once, in the constructor).
class RoundTimeline {
  RoundTimeline({
    required this.tickrate,
    required Iterable<PlayerTimeline> players,
    int? maxInterpolationTickCount,
  }) : maxInterpolationTickCount = maxInterpolationTickCount ?? tickrate,
       _players = {
         for (final player in players)
           player.steamId: _PreparedTimeline(player),
       };

  final int tickrate;

  /// Gaps longer than this many ticks are not interpolated: the previous sample
  /// is held instead.
  final int maxInterpolationTickCount;

  final Map<String, _PreparedTimeline> _players;

  Iterable<String> get steamIds => _players.keys;

  bool contains(String steamId) => _players.containsKey(steamId);

  /// Position of [steamId] at [tick], or null when the player is unknown, the
  /// tick is before their first sample, or their samples ended before [tick].
  PlayerAtTick? playerAt(String steamId, int tick) {
    final player = _players[steamId];
    if (player == null) {
      return null;
    }

    final movements = player.movements;
    if (movements.movementCount == 0) {
      return null;
    }

    final index = findLastIndexAtOrBefore(movements.ticks, tick);
    if (index == -1) {
      return null;
    }

    final previousTick = movements.ticks[index];
    if (previousTick == tick) {
      return PlayerAtTick(
        tick: tick,
        x: movements.xPos[index],
        y: movements.yPos[index],
        z: movements.zPos[index],
        yaw: _normalizeAngle(movements.yaw[index]),
        flash: movements.flash[index],
        ducking: movements.isDucking[index] == 1,
        airborne: movements.isAirborne[index] == 1,
        state: _stateAt(player, tick),
      );
    }

    final nextIndex = index + 1;
    // The player's movements ended before this tick: nothing to show, not even
    // a held last sample (death, disconnect, end of the round...).
    if (nextIndex >= movements.movementCount) {
      return null;
    }

    final state = _stateAt(player, tick);
    final tickCount = movements.ticks[nextIndex] - previousTick;
    if (tickCount > maxInterpolationTickCount) {
      return PlayerAtTick(
        tick: tick,
        x: movements.xPos[index],
        y: movements.yPos[index],
        z: movements.zPos[index],
        yaw: _normalizeAngle(movements.yaw[index]),
        flash: movements.flash[index],
        ducking: movements.isDucking[index] == 1,
        airborne: movements.isAirborne[index] == 1,
        state: state,
      );
    }

    final ratio = (tick - previousTick) / tickCount;
    return PlayerAtTick(
      tick: tick,
      x: _lerp(movements.xPos[index], movements.xPos[nextIndex], ratio),
      y: _lerp(movements.yPos[index], movements.yPos[nextIndex], ratio),
      z: _lerp(movements.zPos[index], movements.zPos[nextIndex], ratio),
      yaw: interpolateYaw(
        movements.yaw[index],
        movements.yaw[nextIndex],
        ratio,
      ),
      flash: _lerp(movements.flash[index], movements.flash[nextIndex], ratio),
      ducking: movements.isDucking[index] == 1,
      airborne: movements.isAirborne[index] == 1,
      state: state,
    );
  }

  StateAtTick? _stateAt(_PreparedTimeline player, int tick) {
    final index = findLastIndexAtOrBefore(player.stateTicks, tick);
    if (index == -1) {
      return null;
    }
    return player.states[index];
  }
}

/// Returns the index of the last item with a tick lower than or equal to [tick],
/// or -1 when every item is after [tick].
///
/// [ticks] must be sorted ascending. Runs in O(log n).
int findLastIndexAtOrBefore(Int32List ticks, int tick) {
  var low = 0;
  var high = ticks.length - 1;
  var index = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (ticks[middle] <= tick) {
      index = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return index;
}

/// Interpolates a yaw angle through the shortest rotation.
///
/// Uses the desktop viewer formula `((to - from) % 360 + 540) % 360 - 180` for
/// the signed delta, then normalises the result to `[0, 360)`. A delta of
/// exactly 180 degrees is degenerate (both directions are as short); it is
/// resolved to +180 so that 90 -> 270 passes through 180.
double interpolateYaw(double from, double to, double t) {
  var delta = ((to - from) % 360 + 540) % 360 - 180;
  if (delta == -180) {
    delta = 180;
  }
  return _normalizeAngle(from + delta * t);
}

double _lerp(double from, double to, double ratio) {
  return from + (to - from) * ratio;
}

double _normalizeAngle(double angle) {
  return (angle % 360 + 360) % 360;
}

/// Decodes state samples once, so [RoundTimeline.playerAt] only does a binary
/// search and returns the matching immutable state.
class _PreparedTimeline {
  _PreparedTimeline(PlayerTimeline player)
    : movements = player.movements,
      stateTicks = player.states.stateTicks,
      states = _decodeStates(player.states);

  final PackedTimeline movements;
  final Int32List stateTicks;
  final List<StateAtTick> states;
}

List<StateAtTick> _decodeStates(PackedTimeline packed) {
  return List<StateAtTick>.generate(
    packed.stateCount,
    (index) => StateAtTick(
      tick: packed.stateTicks[index],
      isAlive: packed.isAlive[index] == 1,
      side: packed.side[index],
      money: packed.money[index],
      health: packed.health[index],
      armor: packed.armor[index],
      hasHelmet: packed.hasHelmet[index] == 1,
      hasBomb: packed.hasBomb[index] == 1,
      hasDefuseKit: packed.hasDefuseKit[index] == 1,
      isScoping: packed.isScoping[index] == 1,
      isDefusing: packed.isDefusing[index] == 1,
      isPlanting: packed.isPlanting[index] == 1,
      isGrabbingHostage: packed.isGrabbingHostage[index] == 1,
      activeWeaponName: packed.activeWeaponNames[index],
      equipments: packed.equipments[index],
      grenades: packed.grenades[index],
      pistols: packed.pistols[index],
      smgs: packed.smgs[index],
      rifles: packed.rifles[index],
      heavy: packed.heavy[index],
    ),
    growable: false,
  );
}
