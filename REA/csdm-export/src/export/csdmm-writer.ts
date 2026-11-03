import Database from 'better-sqlite3';
import type {
  BombEventRow,
  GrenadeEventRow,
  GrenadeRow,
  InfernoRow,
  KillRow,
  MapTransformRow,
  PlayerPositionRow,
  PlayerRow,
  RoundRow,
  ShotRow,
} from './rows.js';


// Writer for the `.csdmm` per-match SQLite file.
// Schema: REA/2026-11-02-csdm-mobile-design.md §3.1, with one documented
// deviation: the `players` table has NO `side` column (side is authoritative
// in the player_positions state blobs; the viewer derives it).

const SCHEMA = `
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
`;

function insertAll<Row extends Record<string, unknown>>(
  database: Database.Database,
  sql: string,
  rows: Row[],
): void {
  if (rows.length === 0) {
    return;
  }
  // better-sqlite3 accepts Buffer directly for BLOB columns.
  const statement = database.prepare<Row>(sql);
  const insert = database.transaction((batch: Row[]) => {
    for (const row of batch) {
      statement.run(row);
    }
  });
  insert(rows);
}

export class CsdmmWriter {
  private readonly database: Database.Database;

  private constructor(database: Database.Database) {
    this.database = database;
  }

  static open(path: string): CsdmmWriter {
    const database = new Database(path);
    database.exec(SCHEMA);
    return new CsdmmWriter(database);
  }

  setMeta(pairs: Record<string, string>): void {
    const statement = this.database.prepare(
      'INSERT INTO match (key, value) VALUES (?, ?)',
    );
    const insert = this.database.transaction((entries: Array<[string, string]>) => {
      for (const [key, value] of entries) {
        statement.run(key, value);
      }
    });
    insert(Object.entries(pairs));
  }

  insertPlayers(rows: PlayerRow[]): void {
    insertAll(
      this.database,
      'INSERT INTO players (steam_id, name, team_name, color) VALUES (@steam_id, @name, @team_name, @color)',
      rows,
    );
  }

  insertRounds(rows: RoundRow[]): void {
    insertAll(
      this.database,
      `INSERT INTO rounds (round_number, start_tick, freeze_time_end_tick, end_tick, end_officially_tick, winner_side, end_reason, score_ct, score_t)
       VALUES (@round_number, @start_tick, @freeze_time_end_tick, @end_tick, @end_officially_tick, @winner_side, @end_reason, @score_ct, @score_t)`,
      rows,
    );
  }

  insertPlayerPositions(rows: PlayerPositionRow[]): void {
    insertAll(
      this.database,
      `INSERT INTO player_positions (
         round_number, player_steam_id,
         ticks, x, y, z, yaw, flash_duration_remaining, is_ducking, is_airborne,
         state_ticks, is_alive, side, money, health, armor, has_helmet, has_bomb,
         has_defuse_kit, is_scoping, is_defusing, is_planting, is_grabbing_hostage,
         active_weapon_name, equipments, grenades, pistols, smgs, rifles, heavy
       ) VALUES (
         @round_number, @player_steam_id,
         @ticks, @x, @y, @z, @yaw, @flash_duration_remaining, @is_ducking, @is_airborne,
         @state_ticks, @is_alive, @side, @money, @health, @armor, @has_helmet, @has_bomb,
         @has_defuse_kit, @is_scoping, @is_defusing, @is_planting, @is_grabbing_hostage,
         @active_weapon_name, @equipments, @grenades, @pistols, @smgs, @rifles, @heavy
       )`,
      rows,
    );
  }

  insertGrenades(rows: GrenadeRow[]): void {
    insertAll(
      this.database,
      `INSERT INTO grenades (round_number, grenade_id, projectile_id, grenade_name, thrower_steam_id, thrower_side, ticks, x, y, z)
       VALUES (@round_number, @grenade_id, @projectile_id, @grenade_name, @thrower_steam_id, @thrower_side, @ticks, @x, @y, @z)`,
      rows,
    );
  }

  insertInfernos(rows: InfernoRow[]): void {
    insertAll(
      this.database,
      `INSERT INTO infernos (round_number, unique_id, thrower_steam_id, ticks, convex_hulls_2d)
       VALUES (@round_number, @unique_id, @thrower_steam_id, @ticks, @convex_hulls_2d)`,
      rows,
    );
  }

  insertKills(rows: KillRow[]): void {
    insertAll(
      this.database,
      `INSERT INTO kills (round_number, tick, killer_steam_id, victim_steam_id, assister_steam_id, killer_side, victim_side, weapon_name, headshot, killer_x, killer_y, victim_x, victim_y, through_smoke, no_scope, penetrated_objects)
       VALUES (@round_number, @tick, @killer_steam_id, @victim_steam_id, @assister_steam_id, @killer_side, @victim_side, @weapon_name, @headshot, @killer_x, @killer_y, @victim_x, @victim_y, @through_smoke, @no_scope, @penetrated_objects)`,
      rows,
    );
  }

  insertShots(rows: ShotRow[]): void {
    insertAll(
      this.database,
      `INSERT INTO shots (round_number, tick, shooter_steam_id, weapon_name, x, y, player_yaw)
       VALUES (@round_number, @tick, @shooter_steam_id, @weapon_name, @x, @y, @player_yaw)`,
      rows,
    );
  }

  insertBombEvents(rows: BombEventRow[]): void {
    insertAll(
      this.database,
      'INSERT INTO bomb_events (round_number, tick, type) VALUES (@round_number, @tick, @type)',
      rows,
    );
  }

  insertGrenadeEvents(rows: GrenadeEventRow[]): void {
    insertAll(
      this.database,
      'INSERT INTO grenade_events (round_number, tick, type, x, y, grenade_id) VALUES (@round_number, @tick, @type, @x, @y, @grenade_id)',
      rows,
    );
  }

  insertMapTransform(row: MapTransformRow | null): void {
    if (row === null) {
      return;
    }
    this.database
      .prepare(
        `INSERT INTO map_transform (name, game, position_x, position_y, scale, threshold_z)
         VALUES (@name, @game, @position_x, @position_y, @scale, @threshold_z)`,
      )
      .run(row);
  }

  close(): void {
    this.database.close();
  }
}
