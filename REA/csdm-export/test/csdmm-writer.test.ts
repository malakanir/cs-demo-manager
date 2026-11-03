import { describe, it, expect, afterAll } from 'vitest';
import Database from 'better-sqlite3';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CsdmmWriter } from '../src/export/csdmm-writer.js';

const dir = mkdtempSync(join(tmpdir(), 'csdmm-writer-'));
const dbPath = join(dir, 'fixt.csdmm');

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

const BLOB_COLUMNS = [
  'ticks',
  'x',
  'y',
  'z',
  'yaw',
  'flash_duration_remaining',
  'is_ducking',
  'is_airborne',
  'state_ticks',
  'is_alive',
  'side',
  'money',
  'health',
  'armor',
  'has_helmet',
  'has_bomb',
  'has_defuse_kit',
  'is_scoping',
  'is_defusing',
  'is_planting',
  'is_grabbing_hostage',
] as const;

const TEXT_COLUMNS = [
  'active_weapon_name',
  'equipments',
  'grenades',
  'pistols',
  'smgs',
  'rifles',
  'heavy',
] as const;

function syntheticBuffers(): Record<(typeof BLOB_COLUMNS)[number], Buffer> {
  const buffers = {} as Record<(typeof BLOB_COLUMNS)[number], Buffer>;
  BLOB_COLUMNS.forEach((column, index) => {
    buffers[column] = Buffer.from([index, 1, 2, 3, 4, 5, 6, 7]);
  });
  return buffers;
}

describe('csdmm writer', () => {
  it('creates the §3.1 schema and round-trips meta, players and blobs', () => {
    const writer = CsdmmWriter.open(dbPath);
    writer.setMeta({ format_version: '1', checksum: 'fixt', map_name: 'de_mirage', game: 'cs2' });
    writer.insertPlayers([
      { steam_id: '76561190000000001', name: 'Alice', team_name: 'TeamA', color: '0' },
    ]);
    const blobs = syntheticBuffers();
    writer.insertPlayerPositions([
      {
        round_number: 1,
        player_steam_id: '76561190000000001',
        ...blobs,
        active_weapon_name: 'weapon_ak47,weapon_ak47',
        equipments: 'weapon_knife',
        grenades: '',
        pistols: 'weapon_glock',
        smgs: '',
        rifles: 'weapon_ak47',
        heavy: '',
      },
    ]);
    writer.close();

    const db = new Database(dbPath);
    try {
      const columns = db.pragma('table_info(player_positions)') as Array<{
        name: string;
        type: string;
      }>;
      const typeByName = new Map(columns.map((column) => [column.name, column.type]));
      for (const column of BLOB_COLUMNS) {
        expect(typeByName.get(column), column).toBe('BLOB');
      }

      const row = db
        .prepare(
          `SELECT ${BLOB_COLUMNS.join(', ')} FROM player_positions WHERE player_steam_id = ?`,
        )
        .get('76561190000000001') as Record<(typeof BLOB_COLUMNS)[number], Buffer>;
      for (const column of BLOB_COLUMNS) {
        expect(row[column].equals(blobs[column]), column).toBe(true);
      }

      const version = db.prepare("SELECT value FROM match WHERE key = 'format_version'").get() as {
        value: string;
      };
      expect(version.value).toBe('1');

      // Documented deviation: .csdmm players has no `side` column.
      const playerColumns = db.pragma('table_info(players)') as Array<{ name: string }>;
      expect(playerColumns.map((column) => column.name)).not.toContain('side');
    } finally {
      db.close();
    }
  });
});
