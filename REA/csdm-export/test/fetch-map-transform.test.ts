import { describe, it, expect, afterAll } from 'vitest';
import { createFixture, FIXTURE_MAP } from './fixture.js';
import { fetchMapTransform } from '../src/export/fetch-map-transform.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

describe('fetchMapTransform', () => {
  it('returns the fixture de_mirage cs2 transform with exact values', async () => {
    const transform = await fetchMapTransform(db, FIXTURE_MAP, 'cs2');
    expect(transform).toEqual({
      name: 'de_mirage',
      game: 'cs2',
      position_x: 1000,
      position_y: 1000,
      scale: 5,
      threshold_z: 10,
    });
  });

  it('returns null for an unknown map', async () => {
    expect(await fetchMapTransform(db, 'de_nuke', 'cs2')).toBeNull();
  });

  it('returns null for a known map with the wrong game', async () => {
    expect(await fetchMapTransform(db, FIXTURE_MAP, 'csgo')).toBeNull();
  });
});
