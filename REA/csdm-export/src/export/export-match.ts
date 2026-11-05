import { mkdir, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import { CsdmmWriter } from './csdmm-writer.js';
import { fetchMatchMeta } from './fetch-match-meta.js';
import { fetchPlayerPositions, hasPositions } from './fetch-player-positions.js';
import { fetchPlayers } from './fetch-players.js';
import { fetchRounds } from './fetch-rounds.js';
import { fetchGrenades } from './fetch-grenades.js';
import { fetchInfernos } from './fetch-infernos.js';
import { fetchKills } from './fetch-kills.js';
import { fetchShots } from './fetch-shots.js';
import { fetchGrenadeEvents, fetchBombEvents } from './fetch-events.js';
import { fetchMapTransform } from './fetch-map-transform.js';

/**
 * Exports one match to `{outDir}/{checksum}.csdmm` (atomic via a `.tmp` file
 * + rename). All independent fetchers run concurrently; the map transform is
 * fetched after the meta (its mapName/game are needed). A match without any
 * player_positions row still exports, with meta `has_positions='false'`.
 * Null map transform skips the map_transform row — unsupported-map handling
 * lives in the viewer app.
 */
export async function exportMatch(
  db: Kysely<DB>,
  checksum: string,
  outDir: string,
): Promise<{ filePath: string; hasPositions: boolean }> {
  const meta = await fetchMatchMeta(db, checksum);
  if (meta === null) {
    throw new Error(`Match not found: ${checksum}`);
  }

  const [players, rounds, positions, grenades, infernos, kills, shots, grenadeEvents, bombEvents, mapTransform, matchHasPositions] =
    await Promise.all([
      fetchPlayers(db, checksum),
      fetchRounds(db, checksum),
      fetchPlayerPositions(db, checksum),
      fetchGrenades(db, checksum),
      fetchInfernos(db, checksum),
      fetchKills(db, checksum),
      fetchShots(db, checksum),
      fetchGrenadeEvents(db, checksum),
      fetchBombEvents(db, checksum),
      fetchMapTransform(db, meta.mapName, meta.game),
      hasPositions(db, checksum),
    ]);

  await mkdir(outDir, { recursive: true });

  const filePath = join(outDir, `${checksum}.csdmm`);
  const tmpPath = `${filePath}.tmp`;
  // A leftover .tmp (crash, Ctrl-C, disk-full mid-write) would make the writer
  // open the stale SQLite file and fail on SCHEMA; also defuses concurrent
  // exporters racing on the same path.
  await rm(tmpPath, { force: true, recursive: true });
  const writer = CsdmmWriter.open(tmpPath);
  try {
    writer.setMeta({
      format_version: '1',
      checksum,
      map_name: meta.mapName,
      game: meta.game,
      tickrate: String(meta.tickrate),
      tick_count: String(meta.tickCount),
      demo_name: meta.demoName,
      date: meta.date.toISOString(),
      duration: String(meta.duration),
      has_positions: matchHasPositions ? 'true' : 'false',
    });
    writer.insertPlayers(players);
    writer.insertRounds(rounds);
    writer.insertPlayerPositions(positions);
    writer.insertGrenades(grenades);
    writer.insertInfernos(infernos);
    writer.insertKills(kills);
    writer.insertShots(shots);
    writer.insertGrenadeEvents(grenadeEvents);
    writer.insertBombEvents(bombEvents);
    writer.insertMapTransform(mapTransform);
  } catch (error) {
    await rm(tmpPath, { force: true, recursive: true });
    throw error;
  } finally {
    writer.close();
  }
  await rename(tmpPath, filePath);

  return { filePath, hasPositions: matchHasPositions };
}
