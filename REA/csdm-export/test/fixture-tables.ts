import { Kysely, sql } from 'kysely';
import pg from 'pg';
import type { DB } from '../src/db/types.js';

// Creates a throwaway PostgreSQL database `csdm_export_test` with a subset of
// cs-demo-manager tables (exact names/columns) and one synthetic match.
// Requires a reachable PostgreSQL server; the target database is dropped and
// recreated on every run.

export const FIXTURE_DB_NAME = 'csdm_export_test';
export const FIXTURE_CHECKSUM = 'fixt';
export const FIXTURE_MAP = 'de_mirage';

function quoteIdent(name: string): string {
  return '"' + name.replaceAll('"', '""') + '"';
}

/**
 * Drops the test database if it exists and recreates it.
 * Connects to the maintenance database `postgres` for the DDL.
 */
export async function createTestDatabase(url: string): Promise<void> {
  const adminUrl = new URL(url);
  const dbName = adminUrl.pathname.replace(/^\//, '');
  if (dbName.length === 0) {
    throw new Error(`No database name in URL: ${url}`);
  }
  adminUrl.pathname = '/postgres';

  const pool = new pg.Pool({ connectionString: adminUrl.toString(), max: 1 });
  try {
    const existing = await pool.query<{ datname: string }>(
      'SELECT datname FROM pg_database WHERE datname = $1',
      [dbName],
    );
    if ((existing.rowCount ?? 0) > 0) {
      // Terminate lingering connections so the drop cannot fail.
      await pool.query(
        `SELECT pg_terminate_backend(pid) FROM pg_stat_activity
         WHERE datname = $1 AND pid <> pg_backend_pid()`,
        [dbName],
      );
      await pool.query(`DROP DATABASE ${quoteIdent(dbName)}`);
    }
    await pool.query(`CREATE DATABASE ${quoteIdent(dbName)}`);
  } finally {
    await pool.end();
  }
}

/** Creates all csdm tables needed by the exporter. */
export async function createFixtureTables(db: Kysely<DB>): Promise<void> {
  await sql`CREATE TABLE demos (
    checksum varchar(64) PRIMARY KEY,
    map_name varchar(64) NOT NULL,
    tickrate real NOT NULL,
    tick_count integer NOT NULL,
    game varchar(32) NOT NULL,
    name text NOT NULL,
    date timestamp NOT NULL,
    duration integer NOT NULL
  )`.execute(db);

  await sql`CREATE TABLE matches (
    checksum varchar(64) PRIMARY KEY,
    demo_path text NOT NULL,
    winner_name varchar(64),
    winner_side smallint,
    overtime_count integer NOT NULL DEFAULT 0,
    max_rounds integer NOT NULL DEFAULT 0
  )`.execute(db);

  await sql`CREATE TABLE players (
    match_checksum varchar(64) NOT NULL,
    steam_id varchar(20) NOT NULL,
    name varchar(64) NOT NULL,
    team_name varchar(64) NOT NULL,
    color varchar(16)
  )`.execute(db);

  await sql`CREATE TABLE steam_account_overrides (
    steam_id varchar(20) PRIMARY KEY,
    name varchar(64) NOT NULL
  )`.execute(db);

  await sql`CREATE TABLE teams (
    match_checksum varchar(64) NOT NULL,
    side smallint NOT NULL,
    name varchar(64) NOT NULL,
    letter varchar(4) NOT NULL,
    score integer NOT NULL
  )`.execute(db);

  await sql`CREATE TABLE rounds (
    match_checksum varchar(64) NOT NULL,
    round_number integer NOT NULL,
    start_tick integer NOT NULL,
    freeze_time_end_tick integer NOT NULL,
    end_tick integer NOT NULL,
    end_officially_tick integer,
    winner_side smallint,
    end_reason varchar(32),
    score_ct integer NOT NULL,
    score_t integer NOT NULL,
    PRIMARY KEY (match_checksum, round_number)
  )`.execute(db);

  await sql`CREATE TABLE player_positions (
    match_checksum varchar(64) NOT NULL,
    round_number integer NOT NULL,
    player_steam_id varchar(20) NOT NULL,
    player_name varchar(64) NOT NULL,
    ticks bytea NOT NULL,
    x bytea NOT NULL,
    y bytea NOT NULL,
    z bytea NOT NULL,
    yaw bytea NOT NULL,
    flash_duration_remaining bytea NOT NULL,
    is_ducking bytea NOT NULL,
    is_airborne bytea NOT NULL,
    state_ticks bytea NOT NULL,
    is_alive bytea NOT NULL,
    side bytea NOT NULL,
    money bytea NOT NULL,
    health bytea NOT NULL,
    armor bytea NOT NULL,
    has_helmet bytea NOT NULL,
    has_bomb bytea NOT NULL,
    has_defuse_kit bytea NOT NULL,
    is_scoping bytea NOT NULL,
    is_defusing bytea NOT NULL,
    is_planting bytea NOT NULL,
    is_grabbing_hostage bytea NOT NULL,
    active_weapon_name text[] NOT NULL,
    equipments text[] NOT NULL,
    grenades text[] NOT NULL,
    pistols text[] NOT NULL,
    smgs text[] NOT NULL,
    rifles text[] NOT NULL,
    heavy text[] NOT NULL,
    PRIMARY KEY (match_checksum, round_number, player_steam_id)
  )`.execute(db);

  await sql`CREATE TABLE grenade_positions (
    match_checksum varchar(64) NOT NULL,
    round_number integer NOT NULL,
    grenade_id varchar(64) NOT NULL,
    projectile_id varchar(64) NOT NULL,
    grenade_name varchar(64) NOT NULL,
    thrower_steam_id varchar(20) NOT NULL,
    thrower_side smallint NOT NULL,
    ticks bytea NOT NULL,
    x bytea NOT NULL,
    y bytea NOT NULL,
    z bytea NOT NULL,
    PRIMARY KEY (match_checksum, round_number, grenade_id)
  )`.execute(db);

  await sql`CREATE TABLE inferno_positions (
    match_checksum varchar(64) NOT NULL,
    round_number integer NOT NULL,
    unique_id varchar(64) NOT NULL,
    thrower_steam_id varchar(20) NOT NULL,
    ticks bytea NOT NULL,
    convex_hulls_2d text[] NOT NULL,
    PRIMARY KEY (match_checksum, round_number, unique_id)
  )`.execute(db);

  await sql`CREATE TABLE kills (
    match_checksum varchar(64) NOT NULL,
    round_number integer NOT NULL,
    tick integer NOT NULL,
    killer_steam_id varchar(20) NOT NULL,
    killer_name varchar(64) NOT NULL,
    killer_side smallint,
    victim_steam_id varchar(20) NOT NULL,
    victim_name varchar(64) NOT NULL,
    victim_side smallint,
    assister_steam_id varchar(20),
    assister_name varchar(64),
    assister_side smallint,
    weapon_name varchar(64) NOT NULL,
    headshot boolean NOT NULL,
    killer_x real NOT NULL,
    killer_y real NOT NULL,
    victim_x real NOT NULL,
    victim_y real NOT NULL,
    through_smoke boolean NOT NULL,
    no_scope boolean NOT NULL,
    penetrated_objects integer NOT NULL
  )`.execute(db);

  await sql`CREATE TABLE shots (
    match_checksum varchar(64) NOT NULL,
    round_number integer NOT NULL,
    tick integer NOT NULL,
    shooter_steam_id varchar(20) NOT NULL,
    shooter_name varchar(64) NOT NULL,
    shooter_side smallint,
    weapon_name varchar(64) NOT NULL,
    x real NOT NULL,
    y real NOT NULL,
    player_yaw real NOT NULL
  )`.execute(db);

  for (const table of ['smokes_start', 'flashbangs_explode', 'he_grenades_explode', 'decoys_start']) {
    await sql`CREATE TABLE ${sql.raw(table)} (
      match_checksum varchar(64) NOT NULL,
      round_number integer NOT NULL,
      tick integer NOT NULL,
      grenade_id varchar(64) NOT NULL,
      projectile_id varchar(64) NOT NULL,
      x real NOT NULL,
      y real NOT NULL,
      z real NOT NULL,
      thrower_steam_id varchar(20) NOT NULL,
      thrower_side smallint
    )`.execute(db);
  }

  for (const table of ['bombs_planted', 'bombs_defused', 'bombs_exploded', 'bombs_plant_start', 'bombs_defuse_start']) {
    await sql`CREATE TABLE ${sql.raw(table)} (
      match_checksum varchar(64) NOT NULL,
      round_number integer NOT NULL,
      tick integer NOT NULL,
      site smallint NOT NULL,
      x real NOT NULL,
      y real NOT NULL,
      z real NOT NULL,
      planter_steam_id varchar(20),
      defuser_steam_id varchar(20)
    )`.execute(db);
  }

  await sql`CREATE TABLE maps (
    name varchar(64) NOT NULL,
    game varchar(32) NOT NULL,
    position_x real NOT NULL,
    position_y real NOT NULL,
    scale real NOT NULL,
    threshold_z real NOT NULL,
    PRIMARY KEY (name, game)
  )`.execute(db);
}
