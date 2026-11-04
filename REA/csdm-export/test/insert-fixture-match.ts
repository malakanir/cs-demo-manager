import type { Kysely } from 'kysely';
import type { DB } from '../src/db/types.js';
import { FIXTURE_CHECKSUM, FIXTURE_MAP } from './fixture-tables.js';

// Synthetic match mirroring the binary layout documented in
// REA/viewer-db-schema.md: movement columns are parallel arrays indexed by
// `ticks[i]` (int32 big-endian), state columns by `state_ticks[i]` (uint8).
// All binary values are big-endian (int32 ticks, float32 coordinates).

const ALICE_STEAM_ID = '76561190000000001';
const BOB_STEAM_ID = '76561190000000002';

function int32Buffer(values: number[]): Buffer {
  const buffer = Buffer.alloc(4 * values.length);
  values.forEach((value, index) => buffer.writeInt32BE(value, index * 4));
  return buffer;
}

function float32Buffer(values: number[]): Buffer {
  const buffer = Buffer.alloc(4 * values.length);
  values.forEach((value, index) => buffer.writeFloatBE(value, index * 4));
  return buffer;
}

function uint8Buffer(values: number[]): Buffer {
  return Buffer.from(values);
}

/**
 * Inserts one synthetic match (checksum `fixt`, 2 rounds, 2 players).
 * Returns the inserted checksum.
 */
export async function insertFixtureMatch(db: Kysely<DB>): Promise<string> {
  const checksum = FIXTURE_CHECKSUM;
  const date = new Date('2026-01-15T20:00:00Z');

  await db
    .insertInto('demos')
    .values({
      checksum,
      map_name: FIXTURE_MAP,
      tickrate: 64,
      tick_count: 1280,
      game: 'cs2',
      name: 'fixture-demo',
      date,
      duration: 40,
    })
    .execute();

  await db
    .insertInto('matches')
    .values({
      checksum,
      demo_path: '/tmp/fixture.dem',
      winner_name: 'TeamA',
      winner_side: 3,
      overtime_count: 0,
      max_rounds: 16,
    })
    .execute();

  await db
    .insertInto('players')
    .values([
      { match_checksum: checksum, steam_id: ALICE_STEAM_ID, name: 'Alice', team_name: 'TeamA', color: 0 },
      { match_checksum: checksum, steam_id: BOB_STEAM_ID, name: 'Bob', team_name: 'TeamB', color: 1 },
    ])
    .execute();

  await db
    .insertInto('steam_account_overrides')
    .values({ steam_id: ALICE_STEAM_ID, name: 'AliceOverride' })
    .execute();

  await db
    .insertInto('teams')
    .values([
      { match_checksum: checksum, current_side: 3, name: 'TeamA', letter: 'A', score: 9 },
      { match_checksum: checksum, current_side: 2, name: 'TeamB', letter: 'B', score: 7 },
    ])
    .execute();

  await db
    .insertInto('rounds')
    .values([
      {
        match_checksum: checksum,
        number: 1,
        start_tick: 100,
        freeze_time_end_tick: 130,
        end_tick: 3000,
        end_officially_tick: 3010,
        winner_name: 'TeamA',
        winner_side: 3,
        end_reason: 0,
        team_a_score: 1,
        team_b_score: 0,
      },
      {
        match_checksum: checksum,
        number: 2,
        start_tick: 3100,
        freeze_time_end_tick: 3130,
        end_tick: 6000,
        end_officially_tick: 6010,
        winner_name: 'TeamB',
        winner_side: 2,
        end_reason: 0,
        team_a_score: 1,
        team_b_score: 1,
      },
    ])
    .execute();

  // Two movement ticks; state encoded as a single sample (state_ticks[0]).
  const ticks = int32Buffer([100, 101]);
  const x = float32Buffer([-500.5, 600.25]);
  const y = float32Buffer([1200.75, -300.5]);
  const z = float32Buffer([64.03125, 64.03125]);
  const yaw = float32Buffer([90, 180]);
  const flashDurationRemaining = float32Buffer([0, 2.5]);
  const isDucking = uint8Buffer([1, 0]);
  const isAirborne = uint8Buffer([0, 0]);
  const stateTicks = int32Buffer([100]);
  const isAlive = uint8Buffer([1]);
  const side = int32Buffer([2]);
  const money = int32Buffer([800]);
  const health = int32Buffer([100]);
  const armor = int32Buffer([100]);
  const hasHelmet = uint8Buffer([1]);
  const hasBomb = uint8Buffer([0]);
  const hasDefuseKit = uint8Buffer([0]);
  const isScoping = uint8Buffer([0]);
  const isDefusing = uint8Buffer([0]);
  const isPlanting = uint8Buffer([0]);
  const isGrabbingHostage = uint8Buffer([0]);

  for (const [index, steamId] of [ALICE_STEAM_ID, BOB_STEAM_ID].entries()) {
    await db
      .insertInto('player_positions')
      .values({
        match_checksum: checksum,
        round_number: 1,
        player_steam_id: steamId,
        player_name: index === 0 ? 'Alice' : 'Bob',
        ticks,
        x,
        y,
        z,
        yaw,
        flash_duration_remaining: flashDurationRemaining,
        is_ducking: isDucking,
        is_airborne: isAirborne,
        state_ticks: stateTicks,
        is_alive: isAlive,
        side,
        money,
        health,
        armor,
        has_helmet: hasHelmet,
        has_bomb: hasBomb,
        has_defuse_kit: hasDefuseKit,
        is_scoping: isScoping,
        is_defusing: isDefusing,
        is_planting: isPlanting,
        is_grabbing_hostage: isGrabbingHostage,
        active_weapon_name: ['weapon_ak47', 'weapon_ak47'],
        equipments: ['weapon_knife'],
        grenades: [],
        pistols: ['weapon_glock'],
        smgs: [],
        rifles: ['weapon_ak47'],
        heavy: [],
      })
      .execute();
  }

  await db
    .insertInto('grenade_positions')
    .values({
      match_checksum: checksum,
      round_number: 1,
      grenade_id: 'gren-1',
      projectile_id: 'proj-1',
      grenade_name: 'smoke',
      thrower_steam_id: ALICE_STEAM_ID,
      thrower_name: 'Alice',
      thrower_side: 3,
      ticks: int32Buffer([200, 210]),
      x: float32Buffer([-100.0, -90.5]),
      y: float32Buffer([200.0, 210.25]),
      z: float32Buffer([70.0, 70.0]),
    })
    .execute();

  await db
    .insertInto('inferno_positions')
    .values({
      match_checksum: checksum,
      round_number: 1,
      unique_id: 'inf-1',
      thrower_steam_id: ALICE_STEAM_ID,
      thrower_name: 'Alice',
      x: 1.5,
      y: 2.5,
      z: 3.5,
      ticks: int32Buffer([300, 320]),
      convex_hulls_2d: ['1,2,3,4', '5,6,7,8'],
    })
    .execute();

  await db
    .insertInto('kills')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 1500,
      killer_steam_id: ALICE_STEAM_ID,
      killer_name: 'Alice',
      killer_side: 3,
      victim_steam_id: BOB_STEAM_ID,
      victim_name: 'Bob',
      victim_side: 2,
      assister_steam_id: null,
      assister_name: null,
      assister_side: null,
      weapon_name: 'weapon_ak47',
      is_headshot: true,
      killer_x: -500.5,
      killer_y: 1200.75,
      victim_x: 600.25,
      victim_y: -300.5,
      is_through_smoke: false,
      is_no_scope: false,
      penetrated_objects: 0,
    })
    .execute();

  // Second kill: wallbang without headshot and with an assister, in a later
  // round so round/tick ordering is exercised.
  await db
    .insertInto('kills')
    .values({
      match_checksum: checksum,
      round_number: 2,
      tick: 4700,
      killer_steam_id: BOB_STEAM_ID,
      killer_name: 'Bob',
      killer_side: 2,
      victim_steam_id: ALICE_STEAM_ID,
      victim_name: 'Alice',
      victim_side: 3,
      assister_steam_id: ALICE_STEAM_ID,
      assister_name: 'Alice',
      assister_side: 3,
      weapon_name: 'weapon_awp',
      is_headshot: false,
      killer_x: 10.5,
      killer_y: 20.25,
      victim_x: 30.125,
      victim_y: 40.0625,
      is_through_smoke: true,
      is_no_scope: true,
      penetrated_objects: 2,
    })
    .execute();

  await db
    .insertInto('shots')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 1490,
      player_steam_id: ALICE_STEAM_ID,
      player_name: 'Alice',
      player_side: 3,
      weapon_name: 'weapon_ak47',
      x: -500.5,
      y: 1200.75,
      player_yaw: 90,
    })
    .execute();

  await db
    .insertInto('shots')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 1520,
      player_steam_id: BOB_STEAM_ID,
      player_name: 'Bob',
      player_side: 2,
      weapon_name: 'weapon_deagle',
      x: 600.25,
      y: -300.5,
      player_yaw: 137.5,
    })
    .execute();

  await db
    .insertInto('shots')
    .values({
      match_checksum: checksum,
      round_number: 2,
      tick: 4500,
      player_steam_id: ALICE_STEAM_ID,
      player_name: 'Alice',
      player_side: 3,
      weapon_name: 'weapon_awp',
      x: 10.5,
      y: 20.25,
      player_yaw: 270,
    })
    .execute();

  for (const table of ['smokes_start', 'flashbangs_explode', 'he_grenades_explode', 'decoys_start'] as const) {
    await db
      .insertInto(table)
      .values({
        match_checksum: checksum,
        round_number: 1,
        tick: 1000,
        grenade_id: `gren-${table}`,
        projectile_id: `proj-${table}`,
        x: 10,
        y: 20,
        z: 30,
        thrower_steam_id: ALICE_STEAM_ID,
        thrower_name: 'Alice',
        thrower_side: 3,
      })
      .execute();
  }

  await db
    .insertInto('bombs_planted')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 2000,
      site: 'A',
      x: 1,
      y: 2,
      z: 3,
      planter_steam_id: ALICE_STEAM_ID,
      planter_name: 'Alice',
    })
    .execute();

  await db
    .insertInto('bombs_defused')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 2400,
      site: 'A',
      x: 1,
      y: 2,
      z: 3,
      defuser_steam_id: BOB_STEAM_ID,
      defuser_name: 'Bob',
    })
    .execute();

  await db
    .insertInto('bombs_exploded')
    .values({
      match_checksum: checksum,
      round_number: 2,
      tick: 5000,
      site: 'B',
      x: 4,
      y: 5,
      z: 6,
      planter_steam_id: ALICE_STEAM_ID,
      planter_name: 'Alice',
    })
    .execute();

  await db
    .insertInto('bombs_plant_start')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 1900,
      site: 'A',
      x: 1,
      y: 2,
      z: 3,
      planter_steam_id: ALICE_STEAM_ID,
      planter_name: 'Alice',
    })
    .execute();

  await db
    .insertInto('bombs_defuse_start')
    .values({
      match_checksum: checksum,
      round_number: 1,
      tick: 2300,
      x: 1,
      y: 2,
      z: 3,
      defuser_steam_id: BOB_STEAM_ID,
      defuser_name: 'Bob',
    })
    .execute();

  await db
    .insertInto('maps')
    .values({ name: FIXTURE_MAP, game: 'cs2', position_x: 1000, position_y: 1000, scale: 5, threshold_z: 10 })
    .execute();

  return checksum;
}
