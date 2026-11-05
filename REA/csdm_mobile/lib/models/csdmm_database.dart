import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'packed_timeline.dart';

/// Read-only, typed access to a `.csdmm` match file.
///
/// The file layout is defined in REA/2026-11-02-csdm-mobile-design.md §3.1.
/// Every query returns plain immutable rows; position BLOBs are decoded into
/// [PackedTimeline]s on read.
class CsdmmDatabase {
  CsdmmDatabase._(this._database);

  static CsdmmDatabase open(String path) {
    return CsdmmDatabase._(sqlite3.open(path, mode: OpenMode.readOnly));
  }

  final Database _database;

  Map<String, String> getMeta() {
    final rows = _database.select('SELECT key, value FROM match');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  List<PlayerRow> getPlayers() {
    final rows = _database.select(
      'SELECT steam_id, name, team_name, color FROM players ORDER BY steam_id',
    );
    return [
      for (final row in rows)
        PlayerRow(
          steamId: row['steam_id'] as String,
          name: row['name'] as String,
          teamName: row['team_name'] as String?,
          color: row['color'] as String?,
        ),
    ];
  }

  List<RoundRow> getRounds() {
    final rows = _database.select(
      'SELECT round_number, start_tick, freeze_time_end_tick, end_tick, end_officially_tick, '
      'winner_side, end_reason, score_ct, score_t FROM rounds ORDER BY round_number',
    );
    return [
      for (final row in rows)
        RoundRow(
          roundNumber: row['round_number'] as int,
          startTick: row['start_tick'] as int,
          freezeTimeEndTick: row['freeze_time_end_tick'] as int,
          endTick: row['end_tick'] as int,
          endOfficiallyTick: row['end_officially_tick'] as int,
          winnerSide: row['winner_side'] as int?,
          endReason: row['end_reason'] as String?,
          scoreCt: row['score_ct'] as int?,
          scoreT: row['score_t'] as int?,
        ),
    ];
  }

  /// Player timelines grouped by round number, ordered by player steam id.
  Map<int, List<PlayerPositionRow>> getPositions() {
    final rows = _database.select(
      'SELECT round_number, player_steam_id, '
      'ticks, x, y, z, yaw, flash_duration_remaining, is_ducking, is_airborne, '
      'state_ticks, is_alive, side, money, health, armor, has_helmet, has_bomb, '
      'has_defuse_kit, is_scoping, is_defusing, is_planting, is_grabbing_hostage, '
      'active_weapon_name, equipments, grenades, pistols, smgs, rifles, heavy '
      'FROM player_positions ORDER BY round_number, player_steam_id',
    );

    final positions = <int, List<PlayerPositionRow>>{};
    for (final row in rows) {
      final roundNumber = row['round_number'] as int;
      final movements = PackedTimeline.decodeMovements(
        ticks: row['ticks'] as Uint8List,
        x: row['x'] as Uint8List,
        y: row['y'] as Uint8List,
        z: row['z'] as Uint8List,
        yaw: row['yaw'] as Uint8List,
        flashDurationRemaining: row['flash_duration_remaining'] as Uint8List,
        isDucking: row['is_ducking'] as Uint8List,
        isAirborne: row['is_airborne'] as Uint8List,
      );
      final stateCount = (row['state_ticks'] as Uint8List).lengthInBytes ~/ 4;
      final states = PackedTimeline.decodeStates(
        stateTicks: row['state_ticks'] as Uint8List,
        isAlive: row['is_alive'] as Uint8List,
        side: row['side'] as Uint8List,
        money: row['money'] as Uint8List,
        health: row['health'] as Uint8List,
        armor: row['armor'] as Uint8List,
        hasHelmet: row['has_helmet'] as Uint8List,
        hasBomb: row['has_bomb'] as Uint8List,
        hasDefuseKit: row['has_defuse_kit'] as Uint8List,
        isScoping: row['is_scoping'] as Uint8List,
        isDefusing: row['is_defusing'] as Uint8List,
        isPlanting: row['is_planting'] as Uint8List,
        isGrabbingHostage: row['is_grabbing_hostage'] as Uint8List,
        activeWeaponNames: _splitWeaponList(
          row['active_weapon_name'] as String,
          stateCount,
        ),
        equipments: _splitWeaponList(row['equipments'] as String, stateCount),
        grenades: _splitWeaponList(row['grenades'] as String, stateCount),
        pistols: _splitWeaponList(row['pistols'] as String, stateCount),
        smgs: _splitWeaponList(row['smgs'] as String, stateCount),
        rifles: _splitWeaponList(row['rifles'] as String, stateCount),
        heavy: _splitWeaponList(row['heavy'] as String, stateCount),
      );

      final playerPositions = positions.putIfAbsent(roundNumber, () => []);
      playerPositions.add(
        PlayerPositionRow(
          roundNumber: roundNumber,
          playerSteamId: row['player_steam_id'] as String,
          movements: movements,
          states: states,
        ),
      );
    }

    return positions;
  }

  List<KillRow> getKills() {
    final rows = _database.select(
      'SELECT round_number, tick, killer_steam_id, victim_steam_id, assister_steam_id, '
      'killer_side, victim_side, weapon_name, headshot, killer_x, killer_y, victim_x, victim_y, '
      'through_smoke, no_scope, penetrated_objects FROM kills ORDER BY round_number, tick',
    );
    return [
      for (final row in rows)
        KillRow(
          roundNumber: row['round_number'] as int,
          tick: row['tick'] as int,
          killerSteamId: row['killer_steam_id'] as String?,
          victimSteamId: row['victim_steam_id'] as String,
          assisterSteamId: row['assister_steam_id'] as String?,
          killerSide: row['killer_side'] as int?,
          victimSide: row['victim_side'] as int,
          weaponName: row['weapon_name'] as String,
          headshot: (row['headshot'] as int) == 1,
          killerX: _nullableDouble(row['killer_x']),
          killerY: _nullableDouble(row['killer_y']),
          victimX: _nullableDouble(row['victim_x']),
          victimY: _nullableDouble(row['victim_y']),
          throughSmoke: _nullableBool(row['through_smoke']),
          noScope: _nullableBool(row['no_scope']),
          penetratedObjects: row['penetrated_objects'] as int?,
        ),
    ];
  }

  List<GrenadeRow> getGrenades() {
    final rows = _database.select(
      'SELECT round_number, grenade_id, projectile_id, grenade_name, thrower_steam_id, thrower_side, '
      'ticks, x, y, z FROM grenades ORDER BY round_number, grenade_id',
    );
    return [
      for (final row in rows)
        GrenadeRow(
          roundNumber: row['round_number'] as int,
          grenadeId: row['grenade_id'] as String,
          projectileId: row['projectile_id'] as String,
          grenadeName: row['grenade_name'] as String,
          throwerSteamId: row['thrower_steam_id'] as String,
          throwerSide: row['thrower_side'] as int,
          ticks: decodeInt32Blob(row['ticks'] as Uint8List),
          x: decodeFloat32Blob(row['x'] as Uint8List),
          y: decodeFloat32Blob(row['y'] as Uint8List),
          z: decodeFloat32Blob(row['z'] as Uint8List),
        ),
    ];
  }

  List<InfernoRow> getInfernos() {
    final rows = _database.select(
      'SELECT round_number, unique_id, thrower_steam_id, ticks, convex_hulls_2d '
      'FROM infernos ORDER BY round_number, unique_id',
    );
    return [
      for (final row in rows)
        InfernoRow(
          roundNumber: row['round_number'] as int,
          uniqueId: row['unique_id'] as String,
          throwerSteamId: row['thrower_steam_id'] as String,
          ticks: decodeInt32Blob(row['ticks'] as Uint8List),
          convexHulls2d: _parseConvexHulls(row['convex_hulls_2d'] as String),
        ),
    ];
  }

  List<ShotRow> getShots() {
    final rows = _database.select(
      'SELECT round_number, tick, shooter_steam_id, weapon_name, x, y, player_yaw '
      'FROM shots ORDER BY round_number, tick',
    );
    return [
      for (final row in rows)
        ShotRow(
          roundNumber: row['round_number'] as int,
          tick: row['tick'] as int,
          shooterSteamId: row['shooter_steam_id'] as String,
          weaponName: row['weapon_name'] as String,
          x: _double(row['x']),
          y: _double(row['y']),
          playerYaw: _double(row['player_yaw']),
        ),
    ];
  }

  List<BombEventRow> getBombEvents() {
    final rows = _database.select(
      'SELECT round_number, tick, type FROM bomb_events ORDER BY round_number, tick',
    );
    return [
      for (final row in rows)
        BombEventRow(
          roundNumber: row['round_number'] as int,
          tick: row['tick'] as int,
          type: row['type'] as String,
        ),
    ];
  }

  List<GrenadeEventRow> getGrenadeEvents() {
    final rows = _database.select(
      'SELECT round_number, tick, type, x, y, grenade_id FROM grenade_events ORDER BY round_number, tick',
    );
    return [
      for (final row in rows)
        GrenadeEventRow(
          roundNumber: row['round_number'] as int,
          tick: row['tick'] as int,
          type: row['type'] as String,
          x: _double(row['x']),
          y: _double(row['y']),
          grenadeId: row['grenade_id'] as String?,
        ),
    ];
  }

  MapTransformRow? getMapTransform() {
    final rows = _database.select(
      'SELECT name, position_x, position_y, scale, threshold_z, game FROM map_transform LIMIT 1',
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.single;
    return MapTransformRow(
      name: row['name'] as String,
      positionX: _double(row['position_x']),
      positionY: _double(row['position_y']),
      scale: _double(row['scale']),
      thresholdZ: _double(row['threshold_z']),
      game: row['game'] as String,
    );
  }

  void close() {
    _database.close();
  }
}

/// Everything a match file contains, loaded in one pass.
class MatchData {
  const MatchData({
    required this.meta,
    required this.players,
    required this.rounds,
    required this.positions,
    required this.kills,
    required this.effects,
    required this.mapTransform,
  });

  static MatchData load(String path) {
    final database = CsdmmDatabase.open(path);
    try {
      return MatchData(
        meta: database.getMeta(),
        players: database.getPlayers(),
        rounds: database.getRounds(),
        positions: database.getPositions(),
        kills: database.getKills(),
        effects: MatchEffects(
          grenades: database.getGrenades(),
          infernos: database.getInfernos(),
          shots: database.getShots(),
          bombEvents: database.getBombEvents(),
          grenadeEvents: database.getGrenadeEvents(),
        ),
        mapTransform: database.getMapTransform(),
      );
    } finally {
      database.close();
    }
  }

  final Map<String, String> meta;
  final List<PlayerRow> players;
  final List<RoundRow> rounds;
  final Map<int, List<PlayerPositionRow>> positions;
  final List<KillRow> kills;
  final MatchEffects effects;
  final MapTransformRow? mapTransform;

  String get checksum => meta['checksum']!;
  String get mapName => meta['map_name']!;
  int get tickrate => int.parse(meta['tickrate']!);
  int get tickCount => int.parse(meta['tick_count']!);
  bool get hasPositions => meta['has_positions'] == 'true';
}

/// Non-player effects (grenades, fires, shots, bomb/effect markers).
class MatchEffects {
  const MatchEffects({
    required this.grenades,
    required this.infernos,
    required this.shots,
    required this.bombEvents,
    required this.grenadeEvents,
  });

  final List<GrenadeRow> grenades;
  final List<InfernoRow> infernos;
  final List<ShotRow> shots;
  final List<BombEventRow> bombEvents;
  final List<GrenadeEventRow> grenadeEvents;
}

class PlayerRow {
  const PlayerRow({
    required this.steamId,
    required this.name,
    required this.teamName,
    required this.color,
  });

  final String steamId;
  final String name;
  final String? teamName;
  final String? color;
}

class RoundRow {
  const RoundRow({
    required this.roundNumber,
    required this.startTick,
    required this.freezeTimeEndTick,
    required this.endTick,
    required this.endOfficiallyTick,
    required this.winnerSide,
    required this.endReason,
    required this.scoreCt,
    required this.scoreT,
  });

  final int roundNumber;
  final int startTick;
  final int freezeTimeEndTick;
  final int endTick;
  final int endOfficiallyTick;
  final int? winnerSide;
  final String? endReason;
  final int? scoreCt;
  final int? scoreT;
}

class PlayerPositionRow {
  const PlayerPositionRow({
    required this.roundNumber,
    required this.playerSteamId,
    required this.movements,
    required this.states,
  });

  final int roundNumber;
  final String playerSteamId;
  final PackedTimeline movements;
  final PackedTimeline states;
}

class KillRow {
  const KillRow({
    required this.roundNumber,
    required this.tick,
    required this.killerSteamId,
    required this.victimSteamId,
    required this.assisterSteamId,
    required this.killerSide,
    required this.victimSide,
    required this.weaponName,
    required this.headshot,
    required this.killerX,
    required this.killerY,
    required this.victimX,
    required this.victimY,
    required this.throughSmoke,
    required this.noScope,
    required this.penetratedObjects,
  });

  final int roundNumber;
  final int tick;
  final String? killerSteamId;
  final String victimSteamId;
  final String? assisterSteamId;
  final int? killerSide;
  final int victimSide;
  final String weaponName;
  final bool headshot;
  final double? killerX;
  final double? killerY;
  final double? victimX;
  final double? victimY;
  final bool? throughSmoke;
  final bool? noScope;
  final int? penetratedObjects;
}

class GrenadeRow {
  const GrenadeRow({
    required this.roundNumber,
    required this.grenadeId,
    required this.projectileId,
    required this.grenadeName,
    required this.throwerSteamId,
    required this.throwerSide,
    required this.ticks,
    required this.x,
    required this.y,
    required this.z,
  });

  final int roundNumber;
  final String grenadeId;
  final String projectileId;
  final String grenadeName;
  final String throwerSteamId;
  final int throwerSide;
  final Int32List ticks;
  final Float32List x;
  final Float32List y;
  final Float32List z;
}

class InfernoRow {
  const InfernoRow({
    required this.roundNumber,
    required this.uniqueId,
    required this.throwerSteamId,
    required this.ticks,
    required this.convexHulls2d,
  });

  final int roundNumber;
  final String uniqueId;
  final String throwerSteamId;
  final Int32List ticks;

  /// Convex hulls as flat `[x1, y1, x2, y2, ...]` sequences.
  final List<List<double>> convexHulls2d;
}

class ShotRow {
  const ShotRow({
    required this.roundNumber,
    required this.tick,
    required this.shooterSteamId,
    required this.weaponName,
    required this.x,
    required this.y,
    required this.playerYaw,
  });

  final int roundNumber;
  final int tick;
  final String shooterSteamId;
  final String weaponName;
  final double x;
  final double y;
  final double playerYaw;
}

class BombEventRow {
  const BombEventRow({
    required this.roundNumber,
    required this.tick,
    required this.type,
  });

  final int roundNumber;
  final int tick;

  /// `plant_start`, `planted`, `defuse_start`, `defused` or `exploded`.
  final String type;
}

class GrenadeEventRow {
  const GrenadeEventRow({
    required this.roundNumber,
    required this.tick,
    required this.type,
    required this.x,
    required this.y,
    required this.grenadeId,
  });

  final int roundNumber;
  final int tick;
  final String type;
  final double x;
  final double y;
  final String? grenadeId;
}

class MapTransformRow {
  const MapTransformRow({
    required this.name,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.thresholdZ,
    required this.game,
  });

  final String name;
  final double positionX;
  final double positionY;
  final double scale;
  final double thresholdZ;
  final String game;
}

/// The exporter newline-joins the per-state inventory arrays, so `\n` separates
/// state samples. A weapon name never contains `\n`, which keeps the state
/// boundaries unambiguous even when a single state carries several weapons of
/// the same category (`weapon_flashbang,weapon_smokegrenade`). An empty array
/// is written as an empty string, which still represents one value per state
/// sample.
List<String> _splitWeaponList(String value, int stateCount) {
  if (stateCount == 0) {
    return const [];
  }
  if (value.isEmpty) {
    return List<String>.filled(stateCount, '');
  }
  return value.split('\n');
}

List<List<double>> _parseConvexHulls(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) {
    throw FormatException('convex_hulls_2d is not a JSON array', value);
  }
  return [
    for (final hull in decoded)
      if (hull is String)
        hull.isEmpty
            ? const <double>[]
            : [
                for (final coordinate in hull.split(','))
                  double.parse(coordinate),
              ]
      else
        throw FormatException('convex_hulls_2d entry is not a string', value),
  ];
}

double _double(Object? value) => (value as num).toDouble();

double? _nullableDouble(Object? value) =>
    value == null ? null : (value as num).toDouble();

bool? _nullableBool(Object? value) =>
    value == null ? null : (value as int) == 1;
