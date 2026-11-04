import { describe, it, expect, afterAll } from 'vitest';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import { fetchGrenades } from '../src/export/fetch-grenades.js';
import { fetchInfernos } from '../src/export/fetch-infernos.js';
import { fetchGrenadeEvents, fetchBombEvents } from '../src/export/fetch-events.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

const ALICE = '76561190000000001';

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

describe('fetchGrenades', () => {
  it('maps columns and passes packed buffers through byte-identically', async () => {
    const grenades = await fetchGrenades(db, FIXTURE_CHECKSUM);
    expect(grenades).toHaveLength(1);

    const grenade = grenades[0]!;
    expect(grenade.round_number).toBe(1);
    expect(grenade.grenade_id).toBe('gren-1');
    expect(grenade.projectile_id).toBe('proj-1');
    expect(grenade.grenade_name).toBe('smoke');
    expect(grenade.thrower_steam_id).toBe(ALICE);
    expect(grenade.thrower_side).toBe(3);

    // Blob identity: the .csdmm writer stores these buffers verbatim, so the
    // fetched bytes must equal the packed fixture bytes exactly.
    expect(grenade.ticks.equals(int32Buffer([200, 210]))).toBe(true);
    expect(grenade.x.equals(float32Buffer([-100.0, -90.5]))).toBe(true);
    expect(grenade.y.equals(float32Buffer([200.0, 210.25]))).toBe(true);
    expect(grenade.z.equals(float32Buffer([70.0, 70.0]))).toBe(true);
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchGrenades(db, 'nope')).toEqual([]);
  });
});

describe('fetchInfernos', () => {
  it('passes ticks through byte-identically and JSON-encodes convex_hulls_2d', async () => {
    const infernos = await fetchInfernos(db, FIXTURE_CHECKSUM);
    expect(infernos).toHaveLength(1);

    const inferno = infernos[0]!;
    expect(inferno.round_number).toBe(1);
    expect(inferno.unique_id).toBe('inf-1');
    expect(inferno.thrower_steam_id).toBe(ALICE);
    expect(inferno.ticks.equals(int32Buffer([300, 320]))).toBe(true);
    // text[] arrives as string[]; stored in .csdmm TEXT as JSON.
    expect(inferno.convex_hulls_2d).toBe(JSON.stringify(['1,2,3,4', '5,6,7,8']));
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchInfernos(db, 'nope')).toEqual([]);
  });
});

describe('fetchGrenadeEvents', () => {
  it('unions the 4 tables with correct type mapping, sorted by tick', async () => {
    const events = await fetchGrenadeEvents(db, FIXTURE_CHECKSUM);
    expect(events).toHaveLength(4);

    // Insertion order interleaved ticks across tables; output must be sorted.
    expect(events.map((event) => [event.tick, event.type])).toEqual([
      [800, 'decoy_start'],
      [900, 'flash_explode'],
      [1000, 'smoke_start'],
      [1100, 'he_explode'],
    ]);

    const smoke = events.find((event) => event.type === 'smoke_start')!;
    expect(smoke.round_number).toBe(1);
    expect(smoke.x).toBeCloseTo(10, 5);
    expect(smoke.y).toBeCloseTo(20, 5);
    expect(smoke.grenade_id).toBe('gren-smokes_start');
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchGrenadeEvents(db, 'nope')).toEqual([]);
  });
});

describe('fetchBombEvents', () => {
  it('unions the 5 tables with correct type mapping, sorted by round then tick', async () => {
    const events = await fetchBombEvents(db, FIXTURE_CHECKSUM);
    expect(events).toHaveLength(5);
    expect(events.map((event) => [event.round_number, event.tick, event.type])).toEqual([
      [1, 1900, 'plant_start'],
      [1, 2000, 'planted'],
      [1, 2300, 'defuse_start'],
      [1, 2400, 'defused'],
      [2, 5000, 'exploded'],
    ]);
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchBombEvents(db, 'nope')).toEqual([]);
  });
});
