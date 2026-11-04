import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Kysely } from 'kysely';
import { createFixture, FIXTURE_CHECKSUM } from './fixture.js';
import type { DB } from '../src/db/types.js';
import { exportMatch } from '../src/export/export-match.js';
import { createServer } from '../src/serve/server.js';

const TOKEN = 'test-token';

describe('createServer', () => {
  let db: Kysely<DB>;
  let teardown: () => Promise<void>;
  let outDir: string;

  beforeAll(async () => {
    const fixture = await createFixture();
    db = fixture.db;
    teardown = fixture.teardown;
    outDir = await mkdtemp(join(tmpdir(), 'csdmm-serve-'));
  });

  afterAll(async () => {
    await rm(outDir, { recursive: true, force: true });
    await teardown();
  });

  it('rejects missing token with 401', async () => {
    const server = await createServer({ db, token: TOKEN, outDir });
    const response = await server.inject({ method: 'GET', url: '/api/matches' });
    expect(response.statusCode).toBe(401);
  });

  it('rejects wrong token with 401', async () => {
    const server = await createServer({ db, token: TOKEN, outDir });
    const response = await server.inject({
      method: 'GET',
      url: '/api/matches',
      headers: { authorization: 'Bearer wrong' },
    });
    expect(response.statusCode).toBe(401);
  });

  it('lists matches with token', async () => {
    const server = await createServer({ db, token: TOKEN, outDir });
    const response = await server.inject({
      method: 'GET',
      url: '/api/matches',
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(response.statusCode).toBe(200);
    const matches = response.json() as Array<{ checksum: string; hasPositions: boolean }>;
    const fixture = matches.find((match) => match.checksum === FIXTURE_CHECKSUM);
    expect(fixture).toBeDefined();
    expect(fixture?.hasPositions).toBe(true);
  });

  it('streams the exported file with matching bytes and Content-Length', async () => {
    const { filePath } = await exportMatch(db, FIXTURE_CHECKSUM, outDir);
    const expected = await readFile(filePath);

    const server = await createServer({ db, token: TOKEN, outDir });
    const response = await server.inject({
      method: 'GET',
      url: `/api/matches/${FIXTURE_CHECKSUM}/export`,
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(response.statusCode).toBe(200);
    expect(response.headers['content-type']).toBe('application/octet-stream');
    expect(Number(response.headers['content-length'])).toBe(expected.length);
    expect(Buffer.from(response.rawPayload)).toEqual(expected);
  });

  it('returns 404 for an unknown checksum', async () => {
    const server = await createServer({ db, token: TOKEN, outDir });
    const response = await server.inject({
      method: 'GET',
      url: '/api/matches/nope/export',
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(response.statusCode).toBe(404);
  });

  it('auto-exports on missing file then serves 200', async () => {
    const freshOutDir = await mkdtemp(join(tmpdir(), 'csdmm-fresh-'));
    try {
      const server = await createServer({ db, token: TOKEN, outDir: freshOutDir });
      const response = await server.inject({
        method: 'GET',
        url: `/api/matches/${FIXTURE_CHECKSUM}/export`,
        headers: { authorization: `Bearer ${TOKEN}` },
      });
      expect(response.statusCode).toBe(200);
      const onDisk = await readFile(join(freshOutDir, `${FIXTURE_CHECKSUM}.csdmm`));
      expect(Buffer.from(response.rawPayload)).toEqual(onDisk);
    } finally {
      await rm(freshOutDir, { recursive: true, force: true });
    }
  });
});
