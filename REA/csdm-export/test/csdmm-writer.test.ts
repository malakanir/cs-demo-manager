import { describe, it, expect, afterAll } from 'vitest';
import Database from 'better-sqlite3';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CsdmmWriter } from '../src/export/csdmm-writer.js';
import { FIXTURE_CHECKSUM } from './fixture-tables.js';

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
    writer.setMeta({ format_version: '1', checksum: FIXTURE_CHECKSUM, map_name: 'de_mirage', game: 'cs2' });
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

  it('accepts synthetic rows through every insert method without SQL errors', () => {
    const path = join(dir, 'all-tables.csdmm');
    const writer = CsdmmWriter.open(path);
    writer.setMeta({ format_version: '1', checksum: FIXTURE_CHECKSUM });
    writer.insertPlayers([
      { steam_id: '76561190000000001', name: 'Alice', team_name: 'TeamA', color: '0' },
      { steam_id: '76561190000000002', name: 'Bob', team_name: null, color: null },
    ]);
    writer.insertRounds([
      {
        round_number: 1,
        start_tick: 100,
        freeze_time_end_tick: 130,
        end_tick: 3000,
        end_officially_tick: 3010,
        winner_side: 3,
        end_reason: null,
        score_ct: 1,
        score_t: 0,
      },
    ]);
    writer.insertGrenades([
      {
        round_number: 1,
        grenade_id: 'gren-1',
        projectile_id: 'proj-1',
        grenade_name: 'smoke',
        thrower_steam_id: '76561190000000001',
        thrower_side: 3,
        ticks: Buffer.from([0, 0, 0, 200]),
        x: Buffer.from([66, 200, 0, 0]),
        y: Buffer.from([67, 72, 0, 0]),
        z: Buffer.from([66, 140, 0, 0]),
      },
    ]);
    writer.insertInfernos([
      {
        round_number: 1,
        unique_id: 'inf-1',
        thrower_steam_id: '76561190000000001',
        ticks: Buffer.from([0, 0, 1, 44]),
        convex_hulls_2d: '1,2,3,4',
      },
    ]);
    writer.insertKills([
      {
        round_number: 1,
        tick: 1500,
        killer_steam_id: '76561190000000001',
        victim_steam_id: '76561190000000002',
        assister_steam_id: null,
        killer_side: 3,
        victim_side: 2,
        weapon_name: 'weapon_ak47',
        headshot: 1,
        killer_x: -500.5,
        killer_y: 1200.75,
        victim_x: 600.25,
        victim_y: -300.5,
        through_smoke: 0,
        no_scope: 0,
        penetrated_objects: 0,
      },
    ]);
    writer.insertShots([
      {
        round_number: 1,
        tick: 1490,
        shooter_steam_id: '76561190000000001',
        weapon_name: 'weapon_ak47',
        x: -500.5,
        y: 1200.75,
        player_yaw: 90,
      },
    ]);
    writer.insertBombEvents([{ round_number: 1, tick: 2000, type: 'planted' }]);
    writer.insertGrenadeEvents([
      { round_number: 1, tick: 1000, type: 'smoke', x: 10, y: 20, grenade_id: 'gren-1' },
    ]);
    writer.insertMapTransform({
      name: 'de_mirage',
      game: 'cs2',
      position_x: 1000,
      position_y: 1000,
      scale: 5,
      threshold_z: 10,
    });
    writer.close();

    const db = new Database(path);
    try {
      // Renamed columns make these counts fail via SQL errors or zero rows.
      const counts = {
        players: 2,
        rounds: 1,
        grenades: 1,
        infernos: 1,
        kills: 1,
        shots: 1,
        bomb_events: 1,
        grenade_events: 1,
        map_transform: 1,
      } as const;
      for (const [table, expected] of Object.entries(counts)) {
        const result = db.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get() as {
          count: number;
        };
        expect(result.count, table).toBe(expected);
      }
      const round = db.prepare('SELECT winner_side, score_ct FROM rounds').get() as {
        winner_side: number;
        score_ct: number;
      };
      expect(round.winner_side).toBe(3);
      expect(round.score_ct).toBe(1);
      const shot = db.prepare('SELECT shooter_steam_id FROM shots').get() as {
        shooter_steam_id: string;
      };
      expect(shot.shooter_steam_id).toBe('76561190000000001');
      // insertMapTransform(null) is a no-op on a fresh file: one row total.
      const transform = db.prepare('SELECT name, game FROM map_transform').get() as {
        name: string;
        game: string;
      };
      expect(transform.name).toBe('de_mirage');
    } finally {
      db.close();
    }
  });

  it('skips map_transform insertion when the row is null', () => {
    const path = join(dir, 'null-transform.csdmm');
    const writer = CsdmmWriter.open(path);
    writer.insertMapTransform(null);
    writer.close();
    const db = new Database(path);
    try {
      const result = db.prepare('SELECT COUNT(*) AS count FROM map_transform').get() as {
        count: number;
      };
      expect(result.count).toBe(0);
    } finally {
      db.close();
    }
  });
});
