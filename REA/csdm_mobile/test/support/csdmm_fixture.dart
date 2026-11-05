import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'blobs.dart';

/// Checksum/map of the synthetic match, mirroring the csdm-export fixture.
const fixtureChecksum = 'deadbeefdeadbeef';
const fixtureMapName = 'de_mirage';
const aliceSteamId = '76561190000000001';
const bobSteamId = '76561190000000002';

/// Schema from REA/2026-11-02-csdm-mobile-design.md §3.1, with the Plan #1
/// ruling applied: `players` has no side column.
const _schema = '''
CREATE TABLE match (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE players (
  steam_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  team_name TEXT,
  color TEXT
);

CREATE TABLE rounds (
  round_number INTEGER PRIMARY KEY,
  start_tick INTEGER NOT NULL,
  freeze_time_end_tick INTEGER NOT NULL,
  end_tick INTEGER NOT NULL,
  end_officially_tick INTEGER NOT NULL,
  winner_side INTEGER, end_reason TEXT, score_ct INTEGER, score_t INTEGER
);

CREATE TABLE player_positions (
  round_number INTEGER NOT NULL,
  player_steam_id TEXT NOT NULL,
  ticks BLOB NOT NULL, x BLOB NOT NULL, y BLOB NOT NULL, z BLOB NOT NULL, yaw BLOB NOT NULL,
  flash_duration_remaining BLOB NOT NULL, is_ducking BLOB NOT NULL, is_airborne BLOB NOT NULL,
  state_ticks BLOB NOT NULL, is_alive BLOB NOT NULL, side BLOB NOT NULL, money BLOB NOT NULL,
  health BLOB NOT NULL, armor BLOB NOT NULL, has_helmet BLOB NOT NULL, has_bomb BLOB NOT NULL,
  has_defuse_kit BLOB NOT NULL, is_scoping BLOB NOT NULL, is_defusing BLOB NOT NULL,
  is_planting BLOB NOT NULL, is_grabbing_hostage BLOB NOT NULL,
  active_weapon_name TEXT NOT NULL, equipments TEXT NOT NULL, grenades TEXT NOT NULL,
  pistols TEXT NOT NULL, smgs TEXT NOT NULL, rifles TEXT NOT NULL, heavy TEXT NOT NULL,
  PRIMARY KEY (round_number, player_steam_id)
);

CREATE TABLE grenades (
  round_number INTEGER NOT NULL,
  grenade_id TEXT NOT NULL, projectile_id TEXT NOT NULL, grenade_name TEXT NOT NULL,
  thrower_steam_id TEXT NOT NULL, thrower_side INTEGER NOT NULL,
  ticks BLOB NOT NULL, x BLOB NOT NULL, y BLOB NOT NULL, z BLOB NOT NULL,
  PRIMARY KEY (round_number, grenade_id)
);

CREATE TABLE infernos (
  round_number INTEGER NOT NULL, unique_id TEXT NOT NULL, thrower_steam_id TEXT NOT NULL,
  ticks BLOB NOT NULL, convex_hulls_2d TEXT NOT NULL,
  PRIMARY KEY (round_number, unique_id)
);

CREATE TABLE kills (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  killer_steam_id TEXT, victim_steam_id TEXT NOT NULL, assister_steam_id TEXT,
  killer_side INTEGER, victim_side INTEGER NOT NULL,
  weapon_name TEXT NOT NULL, headshot INTEGER NOT NULL,
  killer_x REAL, killer_y REAL, victim_x REAL, victim_y REAL,
  through_smoke INTEGER, no_scope INTEGER, penetrated_objects INTEGER
);

CREATE TABLE shots (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  shooter_steam_id TEXT NOT NULL, weapon_name TEXT NOT NULL,
  x REAL NOT NULL, y REAL NOT NULL, player_yaw REAL NOT NULL
);

CREATE TABLE bomb_events (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  type TEXT NOT NULL
);

CREATE TABLE grenade_events (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  type TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL, grenade_id TEXT
);

CREATE TABLE map_transform (
  name TEXT NOT NULL, position_x REAL NOT NULL, position_y REAL NOT NULL,
  scale REAL NOT NULL, threshold_z REAL NOT NULL, game TEXT NOT NULL
);

CREATE INDEX idx_kills_round ON kills(round_number, tick);
CREATE INDEX idx_shots_round ON shots(round_number, tick);
''';

/// Creates a `.csdmm` fixture using the values pinned in the Task 1 brief.
///
/// Returns the path of the created file inside [directory].
String createFixtureCsdmm(Directory directory) {
  final path = '${directory.path}/$fixtureChecksum.csdmm';
  final database = sqlite3.open(path);
  try {
    database.execute(_schema);

    const meta = <String, String>{
      'checksum': fixtureChecksum,
      'map_name': fixtureMapName,
      'tickrate': '64',
      'tick_count': '1280',
      'game': 'cs2',
      'date': '2026-01-15T20:00:00.000Z',
      'demo_name': 'fixture-demo',
      'duration': '40',
      'format_version': '1',
      'has_positions': 'true',
    };
    for (final entry in meta.entries) {
      database.execute('INSERT INTO match (key, value) VALUES (?, ?)', [
        entry.key,
        entry.value,
      ]);
    }

    database.execute(
      'INSERT INTO players (steam_id, name, team_name, color) VALUES (?, ?, ?, ?)',
      [aliceSteamId, 'Alice', 'TeamA', '0'],
    );
    database.execute(
      'INSERT INTO players (steam_id, name, team_name, color) VALUES (?, ?, ?, ?)',
      [bobSteamId, 'Bob', 'TeamB', '1'],
    );

    database.execute(
      'INSERT INTO rounds (round_number, start_tick, freeze_time_end_tick, end_tick, end_officially_tick, '
      'winner_side, end_reason, score_ct, score_t) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [1, 100, 130, 3000, 3010, 3, 'target_bombed', 1, 0],
    );
    database.execute(
      'INSERT INTO rounds (round_number, start_tick, freeze_time_end_tick, end_tick, end_officially_tick, '
      'winner_side, end_reason, score_ct, score_t) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [2, 3100, 3130, 6000, 6010, 2, 'bomb_exploded', 1, 1],
    );

    final ticks = int32Blob([100, 200]);
    final x = float32Blob([-500.5, 600.25]);
    final y = float32Blob([1200.75, -300.5]);
    final z = float32Blob([64.03125, -16.5]);
    final yaw = float32Blob([90, 359.5]);
    final flash = float32Blob([0, 2.5]);
    final isDucking = uint8Blob([1, 0]);
    final isAirborne = uint8Blob([0, 1]);
    final stateTicks = int32Blob([100]);
    final isAlive = uint8Blob([1]);
    final health = int32Blob([100]);
    final armor = int32Blob([100]);
    final hasHelmet = uint8Blob([1]);
    final hasBomb = uint8Blob([0]);
    final hasDefuseKit = uint8Blob([0]);
    final isScoping = uint8Blob([0]);
    final isDefusing = uint8Blob([0]);
    final isPlanting = uint8Blob([0]);
    final isGrabbingHostage = uint8Blob([0]);

    void insertPositions(
      String steamId,
      String activeWeapon,
      String pistols,
      int stateSide,
      int stateMoney,
    ) {
      database.execute(
        '''INSERT INTO player_positions (
             round_number, player_steam_id,
             ticks, x, y, z, yaw, flash_duration_remaining, is_ducking, is_airborne,
             state_ticks, is_alive, side, money, health, armor, has_helmet, has_bomb,
             has_defuse_kit, is_scoping, is_defusing, is_planting, is_grabbing_hostage,
             active_weapon_name, equipments, grenades, pistols, smgs, rifles, heavy
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          1,
          steamId,
          ticks,
          x,
          y,
          z,
          yaw,
          flash,
          isDucking,
          isAirborne,
          stateTicks,
          isAlive,
          int32Blob([stateSide]),
          int32Blob([stateMoney]),
          health,
          armor,
          hasHelmet,
          hasBomb,
          hasDefuseKit,
          isScoping,
          isDefusing,
          isPlanting,
          isGrabbingHostage,
          activeWeapon,
          'weapon_knife',
          '',
          pistols,
          '',
          activeWeapon,
          '',
        ],
      );
    }

    insertPositions(aliceSteamId, 'weapon_ak47', 'weapon_glock', 2, 4000);
    insertPositions(bobSteamId, 'weapon_m4a1', 'weapon_usp_silencer', 3, 800);

    database.execute(
      'INSERT INTO grenades (round_number, grenade_id, projectile_id, grenade_name, thrower_steam_id, '
      'thrower_side, ticks, x, y, z) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        1,
        'gren-1',
        'proj-1',
        'smoke',
        aliceSteamId,
        3,
        int32Blob([200, 210]),
        float32Blob([-100, -90.5]),
        float32Blob([200, 210.25]),
        float32Blob([70, 70]),
      ],
    );

    database.execute(
      'INSERT INTO infernos (round_number, unique_id, thrower_steam_id, ticks, convex_hulls_2d) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        1,
        'inf-1',
        aliceSteamId,
        int32Blob([300, 320]),
        jsonEncode(['1,2,3,4', '5,6,7.5,8']),
      ],
    );

    database.execute(
      'INSERT INTO kills (round_number, tick, killer_steam_id, victim_steam_id, assister_steam_id, '
      'killer_side, victim_side, weapon_name, headshot, killer_x, killer_y, victim_x, victim_y, '
      'through_smoke, no_scope, penetrated_objects) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        1,
        1500,
        aliceSteamId,
        bobSteamId,
        null,
        3,
        2,
        'weapon_ak47',
        1,
        -500.5,
        1200.75,
        600.25,
        -300.5,
        0,
        0,
        0,
      ],
    );

    database.execute(
      'INSERT INTO shots (round_number, tick, shooter_steam_id, weapon_name, x, y, player_yaw) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [1, 1490, aliceSteamId, 'weapon_ak47', -500.5, 1200.75, 90],
    );

    database.execute(
      'INSERT INTO bomb_events (round_number, tick, type) VALUES (?, ?, ?)',
      [1, 2000, 'planted'],
    );

    database.execute(
      'INSERT INTO grenade_events (round_number, tick, type, x, y, grenade_id) VALUES (?, ?, ?, ?, ?, ?)',
      [1, 1000, 'smoke_start', 10, 20, 'gren-1'],
    );

    database.execute(
      'INSERT INTO map_transform (name, position_x, position_y, scale, threshold_z, game) VALUES (?, ?, ?, ?, ?, ?)',
      [fixtureMapName, 1000, 1000, 5, 10, 'cs2'],
    );
  } finally {
    database.close();
  }

  return path;
}
