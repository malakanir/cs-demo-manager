import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { BombEventRow, GrenadeEventRow } from './rows.js';

// The four grenade-event tables share one shape; per-table type tag maps to
// the .csdmm `type` value. Events are merged and sorted in TS instead of SQL
// UNION (per plan).
const GRENADE_EVENT_TABLES = [
  { table: 'smokes_start', type: 'smoke_start' },
  { table: 'flashbangs_explode', type: 'flash_explode' },
  { table: 'he_grenades_explode', type: 'he_explode' },
  { table: 'decoys_start', type: 'decoy_start' },
] as const;

const BOMB_EVENT_TABLES = [
  { table: 'bombs_plant_start', type: 'plant_start' },
  { table: 'bombs_planted', type: 'planted' },
  { table: 'bombs_defuse_start', type: 'defuse_start' },
  { table: 'bombs_defused', type: 'defused' },
  { table: 'bombs_exploded', type: 'exploded' },
] as const;

/**
 * Fetches grenade events (smoke starts, flashbang/HE explodes, decoy starts)
 * for one match from the 4 csdm tables, merged and sorted by round_number
 * then tick.
 */
export async function fetchGrenadeEvents(db: Kysely<DB>, checksum: string): Promise<GrenadeEventRow[]> {
  const batches = await Promise.all(
    GRENADE_EVENT_TABLES.map(async ({ table, type }) => {
      const rows = await db
        .selectFrom(table)
        .where('match_checksum', '=', checksum)
        .select(['round_number', 'tick', 'x', 'y', 'grenade_id'])
        .execute();
      return rows.map((row) => ({ ...row, type }));
    }),
  );
  return mergeSortByRoundAndTick(batches.flat());
}

/**
 * Fetches bomb events (plant start/planted, defuse start/defused, exploded)
 * for one match from the 5 csdm tables, merged and sorted by round_number
 * then tick.
 */
export async function fetchBombEvents(db: Kysely<DB>, checksum: string): Promise<BombEventRow[]> {
  const batches = await Promise.all(
    BOMB_EVENT_TABLES.map(async ({ table, type }) => {
      const rows = await db
        .selectFrom(table)
        .where('match_checksum', '=', checksum)
        .select(['round_number', 'tick'])
        .execute();
      return rows.map((row) => ({ ...row, type }));
    }),
  );
  return mergeSortByRoundAndTick(batches.flat());
}

type Sortable = { round_number: number; tick: number };

function mergeSortByRoundAndTick<T extends Sortable>(rows: T[]): T[] {
  return rows.sort((a, b) => a.round_number - b.round_number || a.tick - b.tick);
}
