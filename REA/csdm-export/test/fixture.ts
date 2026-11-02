import type { Kysely } from 'kysely';
import { connectDatabase, destroyDatabase } from '../src/db/connect.js';
import { createTestDatabase, createFixtureTables } from './fixture-tables.js';
import { insertFixtureMatch } from './insert-fixture-match.js';
import type { DB } from '../src/db/types.js';

export const TEST_DATABASE_URL =
  process.env['CSDM_TEST_DATABASE_URL'] ?? 'postgres://postgres:postgres@localhost:5432/csdm_export_test';

export { FIXTURE_CHECKSUM, FIXTURE_MAP, FIXTURE_DB_NAME } from './fixture-tables.js';
export { insertFixtureMatch } from './insert-fixture-match.js';

/**
 * Full fixture: drop/create `csdm_export_test`, create tables, insert one
 * synthetic match. Returns a connected Kysely instance and the fixture
 * checksum; call `teardown` when done.
 */
export async function createFixture(): Promise<{
  db: Kysely<DB>;
  checksum: string;
  teardown: () => Promise<void>;
}> {
  await createTestDatabase(TEST_DATABASE_URL);
  const db = connectDatabase(TEST_DATABASE_URL);
  try {
    await createFixtureTables(db);
    const checksum = await insertFixtureMatch(db);
    return {
      db,
      checksum,
      teardown: () => destroyDatabase(db),
    };
  } catch (error) {
    // Never leak the pg pool when table creation or insertion fails.
    await destroyDatabase(db);
    throw error;
  }
}
