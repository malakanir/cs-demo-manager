import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { KillRow } from './rows.js';

// .csdmm stores the boolean kill flags as 0/1 integers.
function boolToInt(value: boolean): number {
  return value ? 1 : 0;
}

/**
 * Fetches kills for one match, ordered by round number then tick. Maps the
 * real csdm column names to the .csdmm schema (is_headshot → headshot,
 * is_through_smoke → through_smoke, is_no_scope → no_scope). Nullable
 * killer/assister steam ids are passed through as null.
 */
export async function fetchKills(db: Kysely<DB>, checksum: string): Promise<KillRow[]> {
  const rows = await db
    .selectFrom('kills')
    .where('match_checksum', '=', checksum)
    .selectAll()
    .orderBy('round_number')
    .orderBy('tick')
    .execute();

  return rows.map((row) => ({
    round_number: row.round_number,
    tick: row.tick,
    killer_steam_id: row.killer_steam_id,
    victim_steam_id: row.victim_steam_id,
    assister_steam_id: row.assister_steam_id,
    killer_side: row.killer_side,
    victim_side: row.victim_side,
    weapon_name: row.weapon_name,
    headshot: boolToInt(row.is_headshot),
    killer_x: row.killer_x,
    killer_y: row.killer_y,
    victim_x: row.victim_x,
    victim_y: row.victim_y,
    through_smoke: boolToInt(row.is_through_smoke),
    no_scope: boolToInt(row.is_no_scope),
    penetrated_objects: row.penetrated_objects,
  }));
}
