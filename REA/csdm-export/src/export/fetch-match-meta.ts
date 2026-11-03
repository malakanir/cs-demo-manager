import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';

export type MatchMeta = {
  checksum: string;
  mapName: string;
  tickrate: number;
  tickCount: number;
  game: string;
  demoName: string;
  date: Date;
  duration: number;
};

/**
 * Fetches one match's metadata from `matches` joined with `demos` on checksum
 * (map/tickrate/tick_count/game/demo name/date/duration live in `demos`).
 * PostgreSQL snake_case columns are mapped to csdmm camelCase fields here.
 */
export async function fetchMatchMeta(db: Kysely<DB>, checksum: string): Promise<MatchMeta | null> {
  const row = await db
    .selectFrom('matches')
    .innerJoin('demos', 'demos.checksum', 'matches.checksum')
    .where('matches.checksum', '=', checksum)
    .select([
      'matches.checksum',
      'demos.map_name',
      'demos.tickrate',
      'demos.tick_count',
      'demos.game',
      'demos.name',
      'demos.date',
      'demos.duration',
    ])
    .executeTakeFirst();

  if (row === undefined) {
    return null;
  }

  return {
    checksum: row.checksum,
    mapName: row.map_name,
    tickrate: row.tickrate,
    tickCount: row.tick_count,
    game: row.game,
    demoName: row.name,
    date: row.date,
    duration: row.duration,
  };
}
