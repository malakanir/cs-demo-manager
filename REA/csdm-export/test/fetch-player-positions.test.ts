import { describe, it, expect, afterAll } from 'vitest';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import { fetchPlayerPositions, hasPositions } from '../src/export/fetch-player-positions.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

// Mirrors the synthetic buffers built in insert-fixture-match.ts.
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

const EXPECTED_BLOBS = {
  ticks: int32Buffer([100, 101]),
  x: float32Buffer([-500.5, 600.25]),
  y: float32Buffer([1200.75, -300.5]),
  z: float32Buffer([64.03125, 64.03125]),
  yaw: float32Buffer([90, 180]),
  flash_duration_remaining: float32Buffer([0, 2.5]),
  is_ducking: uint8Buffer([1, 0]),
  is_airborne: uint8Buffer([0, 0]),
  state_ticks: int32Buffer([100]),
  is_alive: uint8Buffer([1]),
  side: int32Buffer([2]),
  money: int32Buffer([800]),
  health: int32Buffer([100]),
  armor: int32Buffer([100]),
  has_helmet: uint8Buffer([1]),
  has_bomb: uint8Buffer([0]),
  has_defuse_kit: uint8Buffer([0]),
  is_scoping: uint8Buffer([0]),
  is_defusing: uint8Buffer([0]),
  is_planting: uint8Buffer([0]),
  is_grabbing_hostage: uint8Buffer([0]),
} as const;

const BLOB_COLUMNS = Object.keys(EXPECTED_BLOBS) as Array<keyof typeof EXPECTED_BLOBS>;

describe('fetchPlayerPositions', () => {
  it('returns both fixture players with byte-identical blobs and joined inventory', async () => {
    const rows = await fetchPlayerPositions(db, FIXTURE_CHECKSUM);
    expect(rows).toHaveLength(2);

    const alice = rows.find((row) => row.player_steam_id === '76561190000000001');
    expect(alice).toBeDefined();
    expect(Buffer.isBuffer(alice!.ticks)).toBe(true);
    expect(alice!.round_number).toBe(1);

    const bob = rows.find((row) => row.player_steam_id === '76561190000000002');
    expect(bob).toBeDefined();

    for (const row of [alice!, bob!]) {
      for (const column of BLOB_COLUMNS) {
        expect(Buffer.isBuffer(row[column]), column).toBe(true);
        expect(row[column].equals(EXPECTED_BLOBS[column]), column).toBe(true);
      }
    }

    // Parallel-per-state arrays are joined into comma-separated TEXT.
    expect(alice!.active_weapon_name).toBe('weapon_ak47,weapon_ak47');
    expect(alice!.equipments).toBe('weapon_knife');
    expect(alice!.grenades).toBe('');
    expect(alice!.pistols).toBe('weapon_glock');
    expect(alice!.rifles).toBe('weapon_ak47');
    expect(alice!.heavy).toBe('');
    expect(bob!.active_weapon_name).toBe('weapon_ak47,weapon_ak47');
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchPlayerPositions(db, 'nope')).toEqual([]);
  });
});

describe('hasPositions', () => {
  it('is true for the fixture match', async () => {
    expect(await hasPositions(db, FIXTURE_CHECKSUM)).toBe(true);
  });

  it('is false for a checksum without positions', async () => {
    expect(await hasPositions(db, 'nope')).toBe(false);
  });
});
