import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { PlayerPositionRow } from './rows.js';

// csdm stores the 7 per-state inventory columns as PostgreSQL text[] arrays;
// the .csdmm schema keeps them as parallel-per-state-index TEXT joined with
// '\n'. A newline can never appear inside a weapon name (each PG array element
// is already a comma-joined category), so per-state boundaries stay unambiguous.
function joinArray(values: string[]): string {
  return values.join('\n');
}

/**
 * Fetches all player positions (raw movement/state bytea buffers) for one
 * match, ordered by round number then player. Buffers are passed through
 * byte-for-byte; any decoding is the viewer's job.
 */
export async function fetchPlayerPositions(db: Kysely<DB>, checksum: string): Promise<PlayerPositionRow[]> {
  const rows = await db
    .selectFrom('player_positions')
    .where('match_checksum', '=', checksum)
    .selectAll()
    .orderBy('round_number')
    .orderBy('player_steam_id')
    .execute();

  return rows.map((row) => ({
    round_number: row.round_number,
    player_steam_id: row.player_steam_id,
    ticks: row.ticks,
    x: row.x,
    y: row.y,
    z: row.z,
    yaw: row.yaw,
    flash_duration_remaining: row.flash_duration_remaining,
    is_ducking: row.is_ducking,
    is_airborne: row.is_airborne,
    state_ticks: row.state_ticks,
    is_alive: row.is_alive,
    side: row.side,
    money: row.money,
    health: row.health,
    armor: row.armor,
    has_helmet: row.has_helmet,
    has_bomb: row.has_bomb,
    has_defuse_kit: row.has_defuse_kit,
    is_scoping: row.is_scoping,
    is_defusing: row.is_defusing,
    is_planting: row.is_planting,
    is_grabbing_hostage: row.is_grabbing_hostage,
    active_weapon_name: joinArray(row.active_weapon_name),
    equipments: joinArray(row.equipments),
    grenades: joinArray(row.grenades),
    pistols: joinArray(row.pistols),
    smgs: joinArray(row.smgs),
    rifles: joinArray(row.rifles),
    heavy: joinArray(row.heavy),
  }));
}

/**
 * True when the match has at least one player_positions row.
 */
export async function hasPositions(db: Kysely<DB>, checksum: string): Promise<boolean> {
  const row = await db
    .selectNoFrom((eb) =>
      eb
        .exists(eb.selectFrom('player_positions').where('match_checksum', '=', checksum).select('player_steam_id'))
        .as('has'),
    )
    .executeTakeFirst();

  return row?.has === true;
}
