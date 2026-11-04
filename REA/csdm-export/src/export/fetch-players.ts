import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { PlayerRow } from './rows.js';

/**
 * Fetches players for one match. Names are authoritative: a steam account
 * override (LEFT JOIN on steam_id) wins over the in-match player name via
 * COALESCE. No `side` column — documented deviation, side comes from blob
 * states.
 */
export async function fetchPlayers(db: Kysely<DB>, checksum: string): Promise<PlayerRow[]> {
  const rows = await db
    .selectFrom('players as p')
    .leftJoin('steam_account_overrides as o', 'o.steam_id', 'p.steam_id')
    .where('p.match_checksum', '=', checksum)
    .select(['p.steam_id', 'p.name', 'p.team_name', 'p.color'])
    .select(({ fn, ref }) => [fn.coalesce(ref('o.name'), ref('p.name')).as('name')])
    .execute();

  return rows.map((row) => ({
    steam_id: row.steam_id,
    name: row.name,
    team_name: row.team_name,
    color: String(row.color),
  }));
}
