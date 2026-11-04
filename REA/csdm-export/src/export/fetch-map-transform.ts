import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { MapTransformRow } from './rows.js';

/**
 * Fetches the radar transform for one map+game pair. Null means the pair has
 * no stored transform; "unsupported map" handling lives in the app, not here.
 */
export async function fetchMapTransform(
  db: Kysely<DB>,
  mapName: string,
  game: string,
): Promise<MapTransformRow | null> {
  const row = await db
    .selectFrom('maps')
    .where('name', '=', mapName)
    .where('game', '=', game)
    .selectAll()
    .limit(1)
    .executeTakeFirst();

  if (!row) return null;

  return {
    name: row.name,
    game: row.game,
    position_x: row.position_x,
    position_y: row.position_y,
    scale: row.scale,
    threshold_z: row.threshold_z,
  };
}
