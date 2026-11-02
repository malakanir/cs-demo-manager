import { describe, it, expect, afterAll } from 'vitest';
import { sql } from 'kysely';
import { createFixture, FIXTURE_CHECKSUM, TEST_DATABASE_URL } from './fixture.js';

const fixture = await createFixture();
const { db } = fixture;

afterAll(async () => {
  await fixture.teardown();
});

describe('postgres fixture', () => {
  it('creates the test database with csdm tables and a synthetic match', async () => {
    const demos = await db.selectFrom('demos').selectAll().execute();
    expect(demos).toHaveLength(1);
    expect(demos[0]?.checksum).toBe(FIXTURE_CHECKSUM);
    expect(demos[0]?.map_name).toBe('de_mirage');
    expect(demos[0]?.tickrate).toBe(64);
  });

  it('exposes the raw packed position buffers as bytea', async () => {
    const rows = await db.selectFrom('player_positions').selectAll().execute();
    expect(rows).toHaveLength(2);
    const ticks = rows[0]!['ticks'];
    expect(ticks).toBeInstanceOf(Buffer);
    expect(ticks.readInt32BE(0)).toBe(100);
    expect(ticks.readInt32BE(4)).toBe(101);
    expect(rows[0]!['x'].readFloatBE(0)).toBeCloseTo(-500.5, 5);
    expect(rows[1]!['player_steam_id']).toBe('76561190000000002');
  });

  it('allows nullable killer and assister columns', async () => {
    const kill = await db.selectFrom('kills').selectAll().executeTakeFirstOrThrow();
    expect(kill.assister_steam_id).toBeNull();
    expect(kill.assister_name).toBeNull();
    expect(kill.is_headshot).toBe(true);
  });

  it('uses real csdm column names for rounds, teams and shots', async () => {
    const round = await db.selectFrom('rounds').selectAll().executeTakeFirstOrThrow();
    expect(round.number).toBe(1);
    expect(round.team_a_score).toBe(1);
    const team = await db.selectFrom('teams').selectAll().executeTakeFirstOrThrow();
    expect(team.current_side).toBe(3);
    const shot = await db.selectFrom('shots').selectAll().executeTakeFirstOrThrow();
    expect(shot.player_steam_id).toBe('76561190000000001');
    expect(shot.player_yaw).toBeCloseTo(90, 5);
  });

  it('stores the steam account override', async () => {
    const overrides = await db.selectFrom('steam_account_overrides').selectAll().execute();
    expect(overrides).toEqual([{ steam_id: '76561190000000001', name: 'AliceOverride' }]);
  });

  it('connects to the expected database', async () => {
    const result = await sql<{ datname: string }>`SELECT current_database() AS datname`.execute(db);
    expect(result.rows[0]?.datname).toBe(TEST_DATABASE_URL.split('/').pop());
  });
});
