import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { ShotRow } from './rows.js';

/**
 * Fetches shots for one match, ordered by round number then tick. Maps the
 * real csdm column `player_steam_id` to the .csdmm name `shooter_steam_id`.
 */
export async function fetchShots(db: Kysely<DB>, checksum: string): Promise<ShotRow[]> {
  const rows = await db
    .selectFrom('shots')
    .where('match_checksum', '=', checksum)
    .selectAll()
    .orderBy('round_number')
    .orderBy('tick')
    .execute();

  return rows.map((row) => ({
    round_number: row.round_number,
    tick: row.tick,
    shooter_steam_id: row.player_steam_id,
    weapon_name: row.weapon_name,
    x: row.x,
    y: row.y,
    player_yaw: row.player_yaw,
  }));
}
