import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { InfernoRow } from './rows.js';

/**
 * Fetches infernos (molotov/incendiary fires) for one match. The real csdm
 * column `convex_hulls_2d` is PostgreSQL `text[]` of "x1,y1,x2,y2,..." hull
 * strings; Kysely/pg returns it as string[]. The .csdmm TEXT column stores
 * JSON.stringify(string[]) — the app side JSON.parse's it back.
 */
export async function fetchInfernos(db: Kysely<DB>, checksum: string): Promise<InfernoRow[]> {
  const rows = await db
    .selectFrom('inferno_positions')
    .where('match_checksum', '=', checksum)
    .select(['round_number', 'unique_id', 'thrower_steam_id', 'ticks', 'convex_hulls_2d'])
    .orderBy('round_number')
    .orderBy('unique_id')
    .execute();

  return rows.map((row) => ({
    round_number: row.round_number,
    unique_id: row.unique_id,
    thrower_steam_id: row.thrower_steam_id,
    ticks: row.ticks,
    convex_hulls_2d: JSON.stringify(row.convex_hulls_2d),
  }));
}
