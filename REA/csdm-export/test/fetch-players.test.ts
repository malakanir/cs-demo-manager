import { describe, it, expect, afterAll } from 'vitest';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import { fetchPlayers } from '../src/export/fetch-players.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

describe('fetchPlayers', () => {
  it('applies the steam account override to the name and covers both players', async () => {
    const players = await fetchPlayers(db, FIXTURE_CHECKSUM);
    expect(players).toHaveLength(2);

    const alice = players.find((player) => player.steam_id === '76561190000000001')!;
    // Override wins.
    expect(alice.name).toBe('AliceOverride');
    expect(alice.team_name).toBe('TeamA');
    expect(alice.color).toBe('0');

    const bob = players.find((player) => player.steam_id === '76561190000000002')!;
    // No override row: in-match name passes through.
    expect(bob.name).toBe('Bob');
    expect(bob.team_name).toBe('TeamB');
    expect(bob.color).toBe('1');
  });

  it('returns an empty list for an unknown checksum', async () => {
    expect(await fetchPlayers(db, 'nope')).toEqual([]);
  });
});
