import Database from 'better-sqlite3';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Kysely } from 'kysely';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import type { DB } from '../src/db/types.js';
import { exportMatch } from '../src/export/export-match.js';

// Mirrors the synthetic buffers built in insert-fixture-match.ts; the exported
// .csdmm blobs must be byte-identical end-to-end.
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

const FIXTURE_COUNTS = {
  players: 2,
  rounds: 2,
  player_positions: 2,
  grenades: 1,
  infernos: 1,
  kills: 2,
  shots: 3,
  grenade_events: 4,
  bomb_events: 5,
  map_transform: 1,
} as const;

describe('exportMatch', () => {
  let db: Kysely<DB>;
  let teardown: () => Promise<void>;
  let outDir: string;

  beforeAll(async () => {
    const fixture = await createFixture();
    db = fixture.db;
    teardown = fixture.teardown;
    outDir = await mkdtemp(join(tmpdir(), 'csdmm-export-'));
  });

  afterAll(async () => {
    await rm(outDir, { recursive: true, force: true });
    await teardown();
  });

  it('exports the fixture match to an atomic .csdmm with exact rows and blob identity', async () => {
    const { filePath, hasPositions } = await exportMatch(db, FIXTURE_CHECKSUM, outDir);
    expect(hasPositions).toBe(true);
    expect(filePath).toBe(join(outDir, `${FIXTURE_CHECKSUM}.csdmm`));

    // Atomic rename: only the final file exists, no .tmp left behind.
    const files = await readdir(outDir);
    expect(files).toEqual([`${FIXTURE_CHECKSUM}.csdmm`]);

    const sqlite = new Database(filePath);
    try {
      const meta = new Map(
        (sqlite.prepare('SELECT key, value FROM match').all() as Array<{ key: string; value: string }>).map(
          (row) => [row.key, row.value],
        ),
      );
      expect(meta.get('checksum')).toBe(FIXTURE_CHECKSUM);
      expect(meta.get('map_name')).toBe('de_mirage');
      expect(meta.get('game')).toBe('cs2');
      expect(meta.get('tickrate')).toBe('64');
      expect(meta.get('has_positions')).toBe('true');

      const count = (table: string): number =>
        (sqlite.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get() as { count: number }).count;
      for (const [table, expected] of Object.entries(FIXTURE_COUNTS)) {
        expect(count(table), table).toBe(expected);
      }

      // Blob identity end-to-end: every movement/state BLOB equals the
      // fixture synthetic buffer byte-for-byte.
      const positionRows = sqlite
        .prepare('SELECT * FROM player_positions ORDER BY player_steam_id')
        .all() as Array<Record<string, unknown>>;
      expect(positionRows).toHaveLength(2);
      for (const row of positionRows) {
        for (const column of BLOB_COLUMNS) {
          expect(Buffer.isBuffer(row[column]), column).toBe(true);
          expect((row[column] as Buffer).equals(EXPECTED_BLOBS[column]), column).toBe(true);
        }
      }
    } finally {
      sqlite.close();
    }
  });

  it('exports a match without positions as has_positions=false', async () => {
    await db.deleteFrom('player_positions').where('match_checksum', '=', FIXTURE_CHECKSUM).execute();

    const { hasPositions } = await exportMatch(db, FIXTURE_CHECKSUM, outDir);
    expect(hasPositions).toBe(false);

    const sqlite = new Database(join(outDir, `${FIXTURE_CHECKSUM}.csdmm`));
    try {
      const hasPositionsMeta = sqlite.prepare("SELECT value FROM match WHERE key = 'has_positions'").get() as {
        value: string;
      };
      expect(hasPositionsMeta.value).toBe('false');
      const count = sqlite.prepare('SELECT COUNT(*) AS count FROM player_positions').get() as { count: number };
      expect(count.count).toBe(0);
    } finally {
      sqlite.close();
    }
  });

  it('throws for an unknown checksum', async () => {
    await expect(exportMatch(db, 'nope', outDir)).rejects.toThrow('Match not found');
  });
});
