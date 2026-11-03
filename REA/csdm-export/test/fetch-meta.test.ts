import { describe, it, expect, afterAll } from 'vitest';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import { fetchMatchMeta } from '../src/export/fetch-match-meta.js';
import { fetchRounds } from '../src/export/fetch-rounds.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

describe('fetchMatchMeta', () => {
  it('returns the fixture match meta with csdmm field names', async () => {
    const meta = await fetchMatchMeta(db, FIXTURE_CHECKSUM);
    expect(meta).not.toBeNull();
    expect(meta!.checksum).toBe('fixt');
    expect(meta!.mapName).toBe('de_mirage');
    expect(meta!.tickrate).toBe(64);
    expect(meta!.tickCount).toBe(1280);
    expect(meta!.game).toBe('cs2');
    expect(meta!.demoName).toBe('fixture-demo');
    expect(meta!.date).toBeInstanceOf(Date);
    expect(meta!.duration).toBe(40);
  });

  it('returns null for an unknown checksum', async () => {
    const meta = await fetchMatchMeta(db, 'nope');
    expect(meta).toBeNull();
  });
});

describe('fetchRounds', () => {
  it('returns the two fixture rounds sorted by round number', async () => {
    const rounds = await fetchRounds(db, FIXTURE_CHECKSUM);
    expect(rounds).toHaveLength(2);
    expect(rounds.map((round) => round.round_number)).toEqual([1, 2]);

    const first = rounds[0]!;
    expect(first.start_tick).toBe(100);
    expect(first.freeze_time_end_tick).toBe(130);
    expect(first.end_tick).toBe(3000);
    expect(first.end_officially_tick).toBe(3010);
    expect(first.winner_side).toBe(3);
    expect(first.end_reason).toBe('StillInProgress');

    const second = rounds[1]!;
    expect(second.start_tick).toBe(3100);
    // Null end_officially_tick falls back to end_tick (csdmm column is NOT NULL).
    expect(second.end_officially_tick).toBe(6000);
  });

  it('returns an empty list for an unknown checksum', async () => {
    const rounds = await fetchRounds(db, 'nope');
    expect(rounds).toEqual([]);
  });
});
