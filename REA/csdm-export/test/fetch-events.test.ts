import { describe, it, expect, afterAll } from 'vitest';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import { fetchKills } from '../src/export/fetch-kills.js';
import { fetchShots } from '../src/export/fetch-shots.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

const ALICE = '76561190000000001';
const BOB = '76561190000000002';

describe('fetchKills', () => {
  it('maps every column from real csdm names to .csdmm names, field by field', async () => {
    const kills = await fetchKills(db, FIXTURE_CHECKSUM);
    expect(kills).toHaveLength(2);

    const [round1, round2] = kills;

    // Round 1 headshot kill: Alice kills Bob, no assister.
    expect(round1!.round_number).toBe(1);
    expect(round1!.tick).toBe(1500);
    expect(round1!.killer_steam_id).toBe(ALICE);
    expect(round1!.victim_steam_id).toBe(BOB);
    expect(round1!.assister_steam_id).toBeNull();
    expect(round1!.killer_side).toBe(3);
    expect(round1!.victim_side).toBe(2);
    expect(round1!.weapon_name).toBe('weapon_ak47');
    expect(round1!.headshot).toBe(1);
    expect(round1!.killer_x).toBeCloseTo(-500.5, 5);
    expect(round1!.killer_y).toBeCloseTo(1200.75, 5);
    expect(round1!.victim_x).toBeCloseTo(600.25, 5);
    expect(round1!.victim_y).toBeCloseTo(-300.5, 5);
    expect(round1!.through_smoke).toBe(0);
    expect(round1!.no_scope).toBe(0);
    expect(round1!.penetrated_objects).toBe(0);

    // Round 2 wallbang kill: Bob kills Alice with an assister, booleans → 0/1.
    expect(round2!.round_number).toBe(2);
    expect(round2!.tick).toBe(4700);
    expect(round2!.killer_steam_id).toBe(BOB);
    expect(round2!.victim_steam_id).toBe(ALICE);
    expect(round2!.assister_steam_id).toBe(ALICE);
    expect(round2!.killer_side).toBe(2);
    expect(round2!.victim_side).toBe(3);
    expect(round2!.weapon_name).toBe('weapon_awp');
    expect(round2!.headshot).toBe(0);
    expect(round2!.killer_x).toBeCloseTo(10.5, 5);
    expect(round2!.killer_y).toBeCloseTo(20.25, 5);
    expect(round2!.victim_x).toBeCloseTo(30.125, 5);
    expect(round2!.victim_y).toBeCloseTo(40.0625, 5);
    expect(round2!.through_smoke).toBe(1);
    expect(round2!.no_scope).toBe(1);
    expect(round2!.penetrated_objects).toBe(2);
  });

  it('sorts by round_number then tick', async () => {
    const kills = await fetchKills(db, FIXTURE_CHECKSUM);
    const order = kills.map((kill) => [kill.round_number, kill.tick]);
    expect(order).toEqual([
      [1, 1500],
      [2, 4700],
    ]);
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchKills(db, 'nope')).toEqual([]);
  });
});

describe('fetchShots', () => {
  it('maps every column including player_steam_id → shooter_steam_id', async () => {
    const shots = await fetchShots(db, FIXTURE_CHECKSUM);
    expect(shots).toHaveLength(3);

    const [first, second, third] = shots;

    expect(first!.round_number).toBe(1);
    expect(first!.tick).toBe(1490);
    expect(first!.shooter_steam_id).toBe(ALICE);
    expect(first!.weapon_name).toBe('weapon_ak47');
    expect(first!.x).toBeCloseTo(-500.5, 5);
    expect(first!.y).toBeCloseTo(1200.75, 5);
    expect(first!.player_yaw).toBeCloseTo(90, 5);

    expect(second!.round_number).toBe(1);
    expect(second!.tick).toBe(1520);
    expect(second!.shooter_steam_id).toBe(BOB);
    expect(second!.weapon_name).toBe('weapon_deagle');
    expect(second!.x).toBeCloseTo(600.25, 5);
    expect(second!.y).toBeCloseTo(-300.5, 5);
    expect(second!.player_yaw).toBeCloseTo(137.5, 5);

    expect(third!.round_number).toBe(2);
    expect(third!.tick).toBe(4500);
    expect(third!.shooter_steam_id).toBe(ALICE);
    expect(third!.weapon_name).toBe('weapon_awp');
    expect(third!.x).toBeCloseTo(10.5, 5);
    expect(third!.y).toBeCloseTo(20.25, 5);
    expect(third!.player_yaw).toBeCloseTo(270, 5);
  });

  it('sorts by round_number then tick', async () => {
    const shots = await fetchShots(db, FIXTURE_CHECKSUM);
    const order = shots.map((shot) => [shot.round_number, shot.tick]);
    expect(order).toEqual([
      [1, 1490],
      [1, 1520],
      [2, 4500],
    ]);
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchShots(db, 'nope')).toEqual([]);
  });
});
