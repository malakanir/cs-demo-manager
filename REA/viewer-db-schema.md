# Audit Skema DB cs-demo-manager (untuk export tool mobile)

Sumber: audit gen-5, 2026-11-02. Target: tool ekspor baca PostgreSQL → SQLite per-match untuk viewer Flutter.

## 1. Struktur skema

- Tipe Kysely: `src/node/database/<entity>/<entity>-table.ts`, registrasi di `src/node/database/schema.ts` (54 tabel).
- Migrasi: `src/node/database/migrations/` (v1 baseline + v2–v15). Versi skema: **15**.
- v15 penting: hapus kolom `frame` di 22 tabel event ("ticks are enough"), ubah `player_positions` dari 1-row-per-tick → **binary packed `bytea`**.
- Ingestion: analyzer → CSV → `COPY` (`src/node/database/copy-csv-into-table.ts`), orkestrasi `insert-match.ts` + `insert-match-positions.ts`.
- `matches` sejak v12 hanya kolom non-overlap dengan `demos` (nama/tanggal/map/tickrate pindah ke `demos`; join via `checksum`).

## 2. Data posisi per-tick: ADA di DB, bukan re-parse

- Disimpan **hanya jika demo dianalisis dengan `analyzePositions: true`** (opsi settings, default false — `src/node/settings/default-settings.ts:50`).
- Fallback: UI trigger `GenerateMatchPositions` → `generate-match-positions.ts` → re-panggil analyzer `csda` (`src/node/demo-analyzer/run-demo-analyzer.ts`) + re-insert.
- Tabel timeline:
  - `player_positions` — 1 row / pemain / round; movement per tick, state hanya saat berubah.
  - `grenade_positions` — 1 row / projectile; titik hanya saat berubah.
  - `inferno_positions` — hull 2D molotov per perubahan.
  - `hostage_positions`, `chicken_positions` — pola sama.
- Kolom `frame` sudah dihapus (v15).

## 3. Tipe tabel kunci (verbatim, ringkas)

`player_positions` (`src/node/database/player-position/player-position-table.ts`):
```ts
export type PlayerPositionTable = {
  match_checksum: string;
  round_number: number;
  player_steam_id: string;
  player_name: string;
  ticks: Buffer; x: Buffer; y: Buffer; z: Buffer; yaw: Buffer;
  flash_duration_remaining: Buffer; is_ducking: Buffer; is_airborne: Buffer;
  state_ticks: Buffer; is_alive: Buffer; side: Buffer; money: Buffer;
  health: Buffer; armor: Buffer; has_helmet: Buffer; has_bomb: Buffer;
  has_defuse_kit: Buffer; is_scoping: Buffer; is_defusing: Buffer;
  is_planting: Buffer; is_grabbing_hostage: Buffer;
  active_weapon_name: string[]; equipments: string[]; grenades: string[];
  pistols: string[]; smgs: string[]; rifles: string[]; heavy: string[];
};
```
Semantik: kolom movement = parallel array per `ticks[i]`; kolom state = parallel array per `state_ticks[i]` (berlaku sampai state berikutnya). Boolean = uint8. Semua binary **big-endian** (int32 tick, float32 nilai).

`grenade_positions`:
```ts
export type GrenadePositionTable = {
  match_checksum: string; round_number: number;
  grenade_id: string; projectile_id: string; grenade_name: GrenadeName;
  thrower_steam_id: string; thrower_name: string; thrower_side: TeamNumber;
  thrower_team_name: string;
  thrower_velocity_x: number; thrower_velocity_y: number; thrower_velocity_z: number;
  thrower_yaw: number; thrower_pitch: number;
  ticks: Buffer; x: Buffer; y: Buffer; z: Buffer;
};
```

`inferno_positions`: `unique_id`, `thrower_*`, `x/y/z`, `ticks: Buffer`, `convex_hulls_2d: string[]` (format "x1,y1,x2,y2...", kosong saat tak ada api aktif).

`grenade_bounces`: event pantulan (tick, posisi, velocity thrower, `grenade_id`/`projectile_id` penghubung).

Dekoder referensi: `src/node/database/decode-packed-positions.ts` (DataView big-endian `getInt32`/`getFloat32`) + `player-position/decode-player-positions.ts`. Sampling 16 Hz tersedia: `player-position/sample-player-movements.ts` (viewer menginterpolasi).

## 4. Tabel kontekstual

- `matches` (join `demos` via checksum): checksum, demo_path, game_type/mode, K/D/A/shot counts, winner_name/side, overtime_count, max_rounds, is_ranked, has_vac_live_ban.
- `demos`: name, game, source, date, tick_count, **tickrate, framerate**, duration, **map_name**, share_code, server_name.
- `rounds`: number, start_tick, freeze_time_end_tick, end_tick, end_officially_tick, skor per tim, side, money/equipment/economy, winner, end_reason, overtime_number.
- `kills`: tick, round_number, killer/victim/assister (steam_id, nama, side, posisi xyz), headshot, penetrated_objects, weapon_name/type, trade flags, through_smoke, no_scope, distance.
- `players` (fisik; tipe `MatchPlayerTable`): statistik per pemain per match (K/D/A, ADR, KAST, rating 2.0, mvps, color, team_name...).
- `teams`: side, name, letter, score, first/second half.
- `shots`: setiap tembakan (tick, weapon, posisi, velocity player, recoil/punch).
- `maps`: **koordinat radar viewer** — `name`, `game`, `position_x`, `position_y`, `threshold_z`, `scale`.
- Event grenade: `smokes_start`, `flashbangs_explode`, `he_grenades_explode`, `decoys_start`, `player_blinds`, bomb: `bombs_planted|defused|exploded|plant_start|defuse_start`.

## 5. Rekonstruksi timeline

Handler referensi: `src/server/handlers/renderer-process/match/fetch-2d-viewer-data-handler.ts` — payload per round: playerTimelines, kills, round, shots, grenadeTimelines, infernoTimelines, hostage/chicken, bomb events, smoke/flash/he/decoy events.

Join minimal: `demos ←→ matches` (checksum) → `rounds` → tabel posisi/event per `(match_checksum, round_number)` → `maps` (transform radar).

**Volume (match CS2 tipikal, 64 tick, 30 round):**
- `player_positions`: ~2 juta+ sampel movement (packed, puluhan MB/match); setelah sampling 16 Hz: ~550 rb.
- Grenade: ~40–60/round × ratusan titik.
- Kills: ~1.500–2.500 row; shots: puluhan ribu.

## 6. Implikasi ekspor SQLite

**KEPUTUSAN (user): ekspor per-tick MENTAH** — salin `bytea` → SQLite `BLOB` tanpa transformasi, dekode di Flutter (`ByteData` big-endian, port kecil dari `decode-packed-positions.ts`). Tanpa sampling. Ukuran ~20–60 MB/match, butuh cache management di HP. Playback 64 tick penuh tanpa interpolasi.

Detail teknis:
1. Kolom movement/state disalin apa adanya sebagai `BLOB`; semantik parallel-array tetap sama.
2. Match tanpa `analyzePositions` → tandai atau trigger re-analyze via tool (jalankan `csda` lagi).
3. Nama pemain authoritative: `players` + `steam_account_overrides` (coalesce), bukan `player_positions.player_name`.
4. Transform radar: pakai kolom `maps` (position_x/y, scale, threshold_z) — formula di laporan viewer (gen-4).
5. Kompresi (zstd) = opsi v2, bukan v1.

## 7. Cakupan utilities & arah tembakan (sudah tersimpan)

- Utilities: trajektori penuh per-tick di `grenade_positions` (semua tipe), pantulan di `grenade_bounces`, area api `inferno_positions` (hull 2D), event `smokes_start` / `flashbangs_explode` / `he_grenades_explode` / `decoys_start` / `player_blinds`; durasi flash per pemain ada di `player_positions.flash_duration_remaining`.
- Arah tembakan: `shots.player_yaw` + `shots.player_pitch` (+ velocity, recoil, aim/view punch) per tembakan; arah lempar: `thrower_yaw`/`thrower_pitch` di tabel grenade.
