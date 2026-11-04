import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { join } from 'node:path';
import Fastify, { type FastifyInstance } from 'fastify';
import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import { exportMatch } from '../export/export-match.js';

export type ServerOptions = {
  db: Kysely<DB>;
  token: string;
  outDir: string;
};

/**
 * LAN HTTP server exposing the csdm database as .csdmm exports.
 * Auth is mandatory on every /api/* route (the csdm WS server binds all
 * interfaces unauthenticated — this one must not repeat that). Listen is
 * intentionally NOT called here; the caller decides host/port.
 */
export async function createServer(opts: ServerOptions): Promise<FastifyInstance> {
  const server = Fastify();

  server.addHook('onRequest', async (request, reply) => {
    if (!request.url.startsWith('/api/')) {
      return;
    }
    // Exact match is fine: LAN-only, token rotates on every serve start.
    if (request.headers.authorization !== `Bearer ${opts.token}`) {
      return reply.code(401).send({ error: 'Unauthorized' });
    }
  });

  server.get('/api/matches', async () => {
    const rows = await opts.db
      .selectFrom('matches')
      .innerJoin('demos', 'demos.checksum', 'matches.checksum')
      .select((eb) => [
        'matches.checksum',
        'demos.map_name',
        'demos.date',
        'demos.duration',
        'demos.tickrate',
        eb
          .exists(
            eb
              .selectFrom('player_positions')
              .whereRef('player_positions.match_checksum', '=', 'matches.checksum')
              .select('player_steam_id'),
          )
          .as('has_positions'),
      ])
      .orderBy('demos.date', 'desc')
      .execute();

    return rows.map((row) => ({
      checksum: row.checksum,
      mapName: row.map_name,
      date: row.date.toISOString(),
      duration: row.duration,
      tickrate: row.tickrate,
      hasPositions: row.has_positions,
    }));
  });

  server.get<{ Params: { checksum: string } }>('/api/matches/:checksum/export', async (request, reply) => {
    const { checksum } = request.params;
    // Demos checksums are crc64 hex (≤16 chars, see csdm get-demo-checksum-from-file-stats.ts).
    // Anything else can escape outDir — reject before touching the filesystem.
    if (!/^[a-f0-9]{1,16}$/i.test(checksum)) {
      return reply.code(404).send({ error: 'Not found' });
    }
    const filePath = join(opts.outDir, `${checksum}.csdmm`);

    let fileStat;
    try {
      fileStat = await stat(filePath);
    } catch {
      // Auto-export once on miss (spec §4.1); unknown checksum → 404.
      try {
        await exportMatch(opts.db, checksum, opts.outDir);
      } catch {
        return reply.code(404).send({ error: 'Not found' });
      }
      try {
        fileStat = await stat(filePath);
      } catch {
        return reply.code(404).send({ error: 'Not found' });
      }
    }

    return reply
      .header('content-type', 'application/octet-stream')
      .header('content-length', fileStat.size)
      .send(createReadStream(filePath));
  });

  return server;
}
