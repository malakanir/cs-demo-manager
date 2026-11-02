import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';
import type { DB } from './types.js';

export function connectDatabase(url: string): Kysely<DB> {
  const pool = new pg.Pool({ connectionString: url, max: 4 });
  return new Kysely<DB>({
    dialect: new PostgresDialect({ pool }),
  });
}

export async function destroyDatabase(db: Kysely<DB>): Promise<void> {
  await db.destroy();
}
