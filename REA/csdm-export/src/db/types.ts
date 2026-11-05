import type { ColumnType } from 'kysely';

// cs-demo-manager column shapes, subset needed by the exporter.
// Extended incrementally as export features are added per task.

export type ByteArray = ColumnType<Buffer, Buffer, Buffer>;

export type DemosTable = {
  checksum: string;
  map_name: string;
  tickrate: number;
  tick_count: number;
  game: string;
  name: string;
  date: ColumnType<Date, Date, Date>;
  duration: number;
};

export type MatchesTable = {
  checksum: string;
  demo_path: string;
  winner_name: string | null;
  winner_side: number | null;
  overtime_count: number;
  max_rounds: number;
};

export type PlayersTable = {
  match_checksum: string;
  steam_id: string;
  name: string;
  team_name: string;
  color: number;
};

export type SteamAccountOverridesTable = {
  steam_id: string;
  name: string;
};

export type TeamsTable = {
  match_checksum: string;
  current_side: number;
  name: string;
  letter: string;
  score: number;
};

export type RoundsTable = {
  match_checksum: string;
  number: number;
  start_tick: number;
  freeze_time_end_tick: number;
  end_tick: number;
  end_officially_tick: number;
  winner_name: string | null;
  winner_side: number | null;
  end_reason: number;
  team_a_side: number;
  team_a_score: number;
  team_b_score: number;
};

export type PlayerPositionsTable = {
  match_checksum: string;
  round_number: number;
  player_steam_id: string;
  player_name: string;
  ticks: ByteArray;
  x: ByteArray;
  y: ByteArray;
  z: ByteArray;
  yaw: ByteArray;
  flash_duration_remaining: ByteArray;
  is_ducking: ByteArray;
  is_airborne: ByteArray;
  state_ticks: ByteArray;
  is_alive: ByteArray;
  side: ByteArray;
  money: ByteArray;
  health: ByteArray;
  armor: ByteArray;
  has_helmet: ByteArray;
  has_bomb: ByteArray;
  has_defuse_kit: ByteArray;
  is_scoping: ByteArray;
  is_defusing: ByteArray;
  is_planting: ByteArray;
  is_grabbing_hostage: ByteArray;
  active_weapon_name: string[];
  equipments: string[];
  grenades: string[];
  pistols: string[];
  smgs: string[];
  rifles: string[];
  heavy: string[];
};

export type GrenadePositionsTable = {
  match_checksum: string;
  round_number: number;
  grenade_id: string;
  projectile_id: string;
  grenade_name: string;
  thrower_steam_id: string;
  thrower_name: string;
  thrower_side: number;
  ticks: ByteArray;
  x: ByteArray;
  y: ByteArray;
  z: ByteArray;
};

export type InfernoPositionsTable = {
  match_checksum: string;
  round_number: number;
  unique_id: string;
  thrower_steam_id: string;
  thrower_name: string;
  x: number;
  y: number;
  z: number;
  ticks: ByteArray;
  convex_hulls_2d: string[];
};

export type KillsTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  killer_steam_id: string | null;
  killer_name: string | null;
  killer_side: number | null;
  victim_steam_id: string;
  victim_name: string;
  victim_side: number;
  assister_steam_id: string | null;
  assister_name: string | null;
  assister_side: number | null;
  weapon_name: string;
  is_headshot: boolean;
  killer_x: number;
  killer_y: number;
  victim_x: number;
  victim_y: number;
  is_through_smoke: boolean;
  is_no_scope: boolean;
  penetrated_objects: number;
};

export type ShotsTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  player_steam_id: string;
  player_name: string;
  player_side: number;
  weapon_name: string;
  x: number;
  y: number;
  player_yaw: number;
};

export type GrenadeEventTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  grenade_id: string;
  projectile_id: string;
  x: number;
  y: number;
  z: number;
  thrower_steam_id: string;
  thrower_name: string;
  thrower_side: number;
};

export type BombPlantedTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  site: string;
  x: number;
  y: number;
  z: number;
  planter_steam_id: string;
  planter_name: string;
};

export type BombDefusedTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  site: string;
  x: number;
  y: number;
  z: number;
  defuser_steam_id: string;
  defuser_name: string;
};

export type BombExplodedTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  site: string;
  x: number;
  y: number;
  z: number;
  planter_steam_id: string;
  planter_name: string;
};

export type BombPlantStartTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  site: string;
  x: number;
  y: number;
  z: number;
  planter_steam_id: string;
  planter_name: string;
};

export type BombDefuseStartTable = {
  match_checksum: string;
  round_number: number;
  tick: number;
  x: number;
  y: number;
  z: number;
  defuser_steam_id: string;
  defuser_name: string;
};

export type MapsTable = {
  name: string;
  game: string;
  position_x: number;
  position_y: number;
  scale: number;
  threshold_z: number;
};

export type DB = {
  demos: DemosTable;
  matches: MatchesTable;
  players: PlayersTable;
  steam_account_overrides: SteamAccountOverridesTable;
  teams: TeamsTable;
  rounds: RoundsTable;
  player_positions: PlayerPositionsTable;
  grenade_positions: GrenadePositionsTable;
  inferno_positions: InfernoPositionsTable;
  kills: KillsTable;
  shots: ShotsTable;
  smokes_start: GrenadeEventTable;
  flashbangs_explode: GrenadeEventTable;
  he_grenades_explode: GrenadeEventTable;
  decoys_start: GrenadeEventTable;
  bombs_planted: BombPlantedTable;
  bombs_defused: BombDefusedTable;
  bombs_exploded: BombExplodedTable;
  bombs_plant_start: BombPlantStartTable;
  bombs_defuse_start: BombDefuseStartTable;
  maps: MapsTable;
};
