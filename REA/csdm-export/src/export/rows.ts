// Row shapes for the `.csdmm` output schema (REA/2026-11-02-csdm-mobile-design.md §3.1).
// The fetcher tasks (T3–T8) map PostgreSQL column names to these shapes; the
// writer only receives plain row objects. Blob columns carry raw big-endian
// buffers copied byte-for-byte from the source database.

export type PlayerRow = {
  steam_id: string;
  name: string;
  team_name: string;
  color: string;
};

export type RoundRow = {
  round_number: number;
  start_tick: number;
  freeze_time_end_tick: number;
  end_tick: number;
  end_officially_tick: number;
  winner_side: number | null;
  end_reason: string | null;
  score_ct: number | null;
  score_t: number | null;
};

export type PlayerPositionRow = {
  round_number: number;
  player_steam_id: string;
  ticks: Buffer;
  x: Buffer;
  y: Buffer;
  z: Buffer;
  yaw: Buffer;
  flash_duration_remaining: Buffer;
  is_ducking: Buffer;
  is_airborne: Buffer;
  state_ticks: Buffer;
  is_alive: Buffer;
  side: Buffer;
  money: Buffer;
  health: Buffer;
  armor: Buffer;
  has_helmet: Buffer;
  has_bomb: Buffer;
  has_defuse_kit: Buffer;
  is_scoping: Buffer;
  is_defusing: Buffer;
  is_planting: Buffer;
  is_grabbing_hostage: Buffer;
  active_weapon_name: string;
  equipments: string;
  grenades: string;
  pistols: string;
  smgs: string;
  rifles: string;
  heavy: string;
};

export type GrenadeRow = {
  round_number: number;
  grenade_id: string;
  projectile_id: string;
  grenade_name: string;
  thrower_steam_id: string;
  thrower_side: number;
  ticks: Buffer;
  x: Buffer;
  y: Buffer;
  z: Buffer;
};

export type InfernoRow = {
  round_number: number;
  unique_id: string;
  thrower_steam_id: string;
  ticks: Buffer;
  convex_hulls_2d: string;
};

export type KillRow = {
  round_number: number;
  tick: number;
  killer_steam_id: string | null;
  victim_steam_id: string;
  assister_steam_id: string | null;
  killer_side: number | null;
  victim_side: number;
  weapon_name: string;
  headshot: number;
  killer_x: number | null;
  killer_y: number | null;
  victim_x: number | null;
  victim_y: number | null;
  through_smoke: number | null;
  no_scope: number | null;
  penetrated_objects: number | null;
};

export type ShotRow = {
  round_number: number;
  tick: number;
  shooter_steam_id: string;
  weapon_name: string;
  x: number;
  y: number;
  player_yaw: number;
};

export type BombEventRow = {
  round_number: number;
  tick: number;
  type: 'plant_start' | 'planted' | 'defuse_start' | 'defused' | 'exploded';
};

export type GrenadeEventRow = {
  round_number: number;
  tick: number;
  type: string;
  x: number;
  y: number;
  grenade_id: string | null;
};

export type MapTransformRow = {
  name: string;
  game: string;
  position_x: number;
  position_y: number;
  scale: number;
  threshold_z: number;
};
