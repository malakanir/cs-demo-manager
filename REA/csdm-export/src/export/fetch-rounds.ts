import type { Kysely } from 'kysely';
import type { DB } from '../db/types.js';
import type { RoundRow } from './rows.js';

// Values from @akiver/cs-demo-analyzer (csdm's analyzer); the database stores
// the raw smallint while the .csdmm spec uses the reason name.
const ROUND_END_REASONS: Record<number, string> = {
  0: 'StillInProgress',
  1: 'TargetBombed',
  2: 'VipEscaped',
  3: 'VipKilled',
  4: 'TerroristsEscaped',
  5: 'CounterTerroristsStoppedEscape',
  6: 'TerroristsStopped',
  7: 'BombDefused',
  8: 'CtWin',
  9: 'TerroristWin',
  10: 'Draw',
  11: 'HostagesRescued',
  12: 'TargetSaved',
  13: 'TerroristsNotRescued',
  14: 'TerroristsNotEscaped',
  15: 'VipNotEscaped',
  16: 'GameStart',
  17: 'TerroristsSurrender',
  18: 'CounterTerroristsSurrender',
  19: 'TerroristsPlanted',
  20: 'CounterTerroristsReachedHostage',
};

function roundEndReasonToName(reason: number): string {
  return ROUND_END_REASONS[reason] ?? String(reason);
}

/**
 * Fetches rounds sorted by round number. The csdmm `rounds.end_officially_tick`
 * column is NOT NULL, so a database NULL falls back to `end_tick`.
 */
export async function fetchRounds(db: Kysely<DB>, checksum: string): Promise<RoundRow[]> {
  const rows = await db
    .selectFrom('rounds')
    .where('match_checksum', '=', checksum)
    .select([
      'number',
      'start_tick',
      'freeze_time_end_tick',
      'end_tick',
      'end_officially_tick',
      'winner_side',
      'end_reason',
      'team_a_score',
      'team_b_score',
    ])
    .orderBy('number')
    .execute();

  return rows.map((row) => ({
    round_number: row.number,
    start_tick: row.start_tick,
    freeze_time_end_tick: row.freeze_time_end_tick,
    end_tick: row.end_tick,
    end_officially_tick: row.end_officially_tick ?? row.end_tick,
    winner_side: row.winner_side,
    end_reason: roundEndReasonToName(row.end_reason),
    score_ct: row.team_a_score,
    score_t: row.team_b_score,
  }));
}
