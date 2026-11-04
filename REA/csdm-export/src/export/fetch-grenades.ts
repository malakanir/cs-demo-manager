import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { GrenadeRow } from './rows.js';

/**
 * Fetches grenade trajectories for one match. The packed movement columns
 * (ticks/x/y/z bytea) are passed through byte-identically; the app decodes
 * them (int32 big-endian ticks, float32 coordinates).
 */
export async function fetchGrenades(db: Kysely<DB>, checksum: string): Promise<GrenadeRow[]> {
  const rows = await db
    .selectFrom('grenade_positions')
    .where('match_checksum', '=', checksum)
    .select([
      'round_number',
      'grenade_id',
      'projectile_id',
      'grenade_name',
      'thrower_steam_id',
      'thrower_side',
      'ticks',
      'x',
      'y',
      'z',
    ])
    .orderBy('round_number')
    .orderBy('grenade_id')
    .execute();

  return rows.map((row) => ({
    round_number: row.round_number,
    grenade_id: row.grenade_id,
    projectile_id: row.projectile_id,
    grenade_name: row.grenade_name,
    thrower_steam_id: row.thrower_steam_id,
    thrower_side: row.thrower_side,
    ticks: row.ticks,
    x: row.x,
    y: row.y,
    z: row.z,
  }));
}
