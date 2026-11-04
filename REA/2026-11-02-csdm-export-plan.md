# csdm-export Tool Implementation Plan (Plan #1 dari spec csdm-mobile)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tool PC terpisah yang membaca PostgreSQL cs-demo-manager (read-only) dan mengekspor satu match menjadi file SQLite `.csdmm`, dilayani ke HP via HTTP LAN dengan QR+token pairing dan mDNS discovery.

**Architecture:** Node.js/TypeScript CLI. Data layer = Kysely read-only ke PostgreSQL csdm; writer = better-sqlite3 menghasilkan `.csdmm` (skema spec §3.1, BLOB disalin byte-identik); server = Fastify + token auth + qrcode-terminal + bonjour-service (mDNS). Proyek baru di `REA/csdm-export/` — csdm tidak disentuh.

**Tech Stack:** TypeScript 5.x, Node 20+, kysely + pg (read-only), better-sqlite3, fastify, qrcode + qrcode-terminal, bonjour-service, vitest, tsx.

**Spec:** `REA/2026-11-02-csdm-mobile-design.md` (§3 format, §4 protokol). Referensi pendukung: `REA/viewer-db-schema.md` (skema PostgreSQL), decoder verbatim di bawah.

## Global Constraints

- csdm **tidak dimodifikasi** — tool hidup di `REA/csdm-export/`, koneksi DB read-only (string koneksi via env `CSDM_DATABASE_URL`).
- Kolom BLOB (`ticks, x, y, z, yaw, flash_duration_remaining, is_ducking, is_airborne, state_ticks, is_alive, side, money, health, armor, has_helmet, has_bomb, has_defuse_kit, is_scoping, is_defusing, is_planting, is_grabbing_hostage`) **disalin byte-identik** — tanpa transformasi, tanpa sampling. Semua big-endian (lihat decoder referensi di bawah).
- Semua endpoint `/api/*` wajib `Authorization: Bearer <token>`; server bind ke **IP LAN aktif**, bukan `0.0.0.0`.
- `format_version` = `1` ditulis di tabel `match` setiap ekspor.
- Match tanpa positions (`analyzePositions:false`) tetap diekspor: tabel positions kosong + `has_positions=false`. Jangan crash.
- Peta tak dikenal (tidak ada di tabel `maps`) → `map_transform` kosong, ekspor tetap sukses (app yang menampilkan "unsupported").
- Bahasa kode: Inggris; komentar/README: Inggris. Conventional commits. Tanpa `any` (strict TS).
- Test butuh PostgreSQL berjalan (user punya DB csdm). Fixture = skema subset dibuat via `test/fixture.ts` (kysely `schema` builder) — jangan sentuh DB asli; fixture pakai database terpisah (env `CSDM_TEST_DATABASE_URL`, fallback buat db `csdm_export_test`).

**Decoder referensi (verbatim dari csdm, port referensi):**
```ts
// src/node/database/decode-packed-positions.ts — big-endian, count = ticks.byteLength/4, offset i*4
// getInt32 → tick; getFloat32 → x/y/z (idem yaw, flash_duration_remaining)
// uint8 bools diakses langsung: packed.is_ducking[index] === 1 (bukan DataView)
// state cols per state_ticks[i]: side/money/health/armor = int32 via DataView;
// is_alive, has_helmet, has_bomb, has_defuse_kit, is_scoping, is_defusing, is_planting, is_grabbing_hostage = uint8 langsung
// string arrays paralel per state index: active_weapon_name, equipments, grenades, pistols, smgs, rifles, heavy
```

## Review Focus

1. **Blob byte-identity** — satu byte pun berubah = replay rusak. Uji: bandingkan Buffer fixture vs BLOB hasil ekspor (`Buffer.equals`). (Task 4/8)
2. **Nama pemain authoritative** — `players.name` + override `steam_account_overrides` (COALESCE); salah nama tampil permanen di viewer. (Task 7)
3. **Match tanpa positions** — harus sukses + flag; saat ini UI csdm trigger re-analyze (di luar lingkup). (Task 4, Task 9)
4. **Auth & bind** — endpoint tanpa token = kebocoran seluruh riwayat match; bind 0.0.0.0 = mengulang celah csdm. (Task 10)
5. **Peta tak dikenal** — ekspor jangan gagal; app menangani ketiadaan transform. (Task 8)

---

### Task 1: Scaffold proyek + fixture PostgreSQL

**Files:**
- Create: `REA/csdm-export/package.json`, `tsconfig.json`, `.gitignore`
- Create: `REA/csdm-export/src/db/connect.ts`
- Test: `REA/csdm-export/test/fixture.ts`

**Interfaces:**
- Produces: `connectDatabase(url: string): Kysely<DB>` (lazy, read-only intent), `createFixtureTables(db: Kysely<any>): Promise<void>`, `insertFixtureMatch(db: Kysely<any>): Promise<string>` (returns checksum), `destroyDatabase(db): Promise<void>`. Types `DB` didefinisikan incremental per task di `src/db/types.ts`.

- [ ] **Step 1: Scaffold**

```bash
mkdir -p REA/csdm-export/src/db REA/csdm-export/src/export REA/csdm-export/src/serve REA/csdm-export/test
cd REA/csdm-export
npm init -y
npm i kysely pg better-sqlite3 fastify qrcode bonjour-service
npm i -D typescript vitest tsx @types/node @types/pg @types/better-sqlite3
npx tsc --init --strict --module NodeNext --moduleResolution NodeNext --outDir dist --skipLibCheck
```

`.gitignore`: `node_modules/`, `dist/`, `*.csdmm`, `.env`

`package.json` scripts:
```json
{ "test": "vitest run", "typecheck": "tsc --noEmit", "cli": "tsx src/cli.ts" }
```

- [ ] **Step 2: Fixture (buat tabel subset PostgreSQL + data sintetis)**

`test/fixture.ts` — buat tabel persis nama/kolom csdm yang dibutuhkan (subset; kolom boleh diambil dari `src/node/database/<entity>/<entity>-table.ts` csdm):

Tabel: `demos(checksum pk, map_name, tickrate, tick_count, game, name, date, duration)`, `matches(checksum pk, demo_path, winner_name, winner_side, overtime_count, max_rounds)`, `players(match_checksum, steam_id, name, team_name, color)`, `steam_account_overrides(steam_id pk, name)`, `teams(match_checksum, side, name, letter, score)`, `rounds(match_checksum, round_number, start_tick, freeze_time_end_tick, end_tick, end_officially_tick, winner_side, end_reason, score_ct, score_t)`, `player_positions(match_checksum, round_number, player_steam_id, player_name, ticks bytea, x bytea, y bytea, z bytea, yaw bytea, flash_duration_remaining bytea, is_ducking bytea, is_airborne bytea, state_ticks bytea, is_alive bytea, side bytea, money bytea, health bytea, armor bytea, has_helmet bytea, has_bomb bytea, has_defuse_kit bytea, is_scoping bytea, is_defusing bytea, is_planting bytea, is_grabbing_hostage bytea, active_weapon_name text[], equipments text[], grenades text[], pistols text[], smgs text[], rifles text[], heavy text[])`, `grenade_positions(match_checksum, round_number, grenade_id, projectile_id, grenade_name, thrower_steam_id, thrower_side, ticks bytea, x bytea, y bytea, z bytea)`, `inferno_positions(match_checksum, round_number, unique_id, thrower_steam_id, ticks bytea, convex_hulls_2d text[])`, `kills(match_checksum, round_number, tick, killer_steam_id, killer_name, killer_side, victim_steam_id, victim_name, victim_side, assister_steam_id, assister_name, assister_side, weapon_name, headshot, killer_x, killer_y, victim_x, victim_y, through_smoke, no_scope, penetrated_objects)`, `shots(match_checksum, round_number, tick, shooter_steam_id, shooter_name, shooter_side, weapon_name, x, y, player_yaw)`, event tables (`smokes_start, flashbangs_explode, he_grenades_explode, decoys_start`: match_checksum, round_number, tick, grenade_id, projectile_id, x, y, z, thrower_steam_id, thrower_side), bomb tables (`bombs_planted, bombs_defused, bombs_exploded, bombs_plant_start, bombs_defuse_start`: match_checksum, round_number, tick, site, x, y, z, planter_steam_id/defuser_steam_id), `maps(name, game, position_x, position_y, scale, threshold_z)`.

`insertFixtureMatch` mengisi 1 match sintetis: checksum `'fixt'`, map `de_mirage`, tickrate 64, 2 ronde, 2 pemain (`76561190000000001` name `Alice` dengan override `AliceOverride`, `76561190000000002` `Bob`), blob sintetis via `Buffer`:
```ts
const ticks = Buffer.alloc(4 * 2); ticks.writeInt32BE(100, 0); ticks.writeInt32BE(101, 4);
const x = Buffer.alloc(4 * 2); x.writeFloatBE(-500.5, 0); x.writeFloatBE(600.25, 4);
// ... idem y/z/yaw/flash; is_ducking = Buffer.from([1,0]); state_ticks 1 sampel; side int32BE 2; dst.
```
Nama fixture DB: `csdm_export_test` (fixture drop/create dulu). Koneksi: `CSDM_TEST_DATABASE_URL` default `postgres://postgres:postgres@localhost:5432/csdm_export_test`.

- [ ] **Step 3: Smoke test** — `test/fixture.test.ts`: panggil fixture, assert `select from demos` mengembalikan checksum `'fixt'`. Run: `npm test`. Expected PASS (butuh PG jalan).
- [ ] **Step 4: Commit** — `git add -A && git commit -m "chore(csdm-export): scaffold tool with postgres fixture"`

### Task 2: Writer `.csdmm` (better-sqlite3)

**Files:**
- Create: `src/export/csdmm-writer.ts`
- Test: `test/csdmm-writer.test.ts`

**Interfaces:**
- Produces: `class CsdmmWriter { static open(path: string): CsdmmWriter; setMeta(pairs: Record<string,string>): void; insertPlayers(rows: PlayerRow[]): void; insertRounds(rows: RoundRow[]): void; insertPlayerPositions(rows: PlayerPositionRow[]): void; insertGrenades(rows: GrenadeRow[]): void; insertInfernos(rows: InfernoRow[]): void; insertKills(rows: KillRow[]): void; insertShots(rows: ShotRow[]): void; insertBombEvents(rows: BombEventRow[]): void; insertGrenadeEvents(rows: GrenadeEventRow[]): void; insertMapTransform(row: MapTransformRow | null): void; close(): void }`. Baris = objek plain dengan properti persis skema spec §3.1 (`REA/2026-11-02-csdm-mobile-design.md`). **Deviasi terdokumentasi dari spec §3.1:** tabel `players` TANPA kolom `side` (terverifikasi: `MatchPlayerTable` csdm tidak punya `side`; side otoritatif ada di blob state `player_positions`, didekode app). Viewer menurunkan side dari state pertama.

- [ ] **Step 1: Failing test** — buka writer, isi meta `{format_version:'1', checksum:'fixt', ...}`, 1 pemain, 1 baris positions dengan Buffer sintetis, close; buka ulang dengan better-sqlite3 baru, assert: `PRAGMA table_info(player_positions)` berisi semua kolom BLOB; `SELECT ticks` mengembalikan Buffer yang `equals` fixture; `SELECT value FROM match WHERE key='format_version'` = `'1'`.
- [ ] **Step 2:** Run `npm test` → FAIL (modul belum ada).
- [ ] **Step 3: Implement** — better-sqlite3; `db.exec` CREATE TABLE persis spec §3.1 (tanpa `players.side`); prepared statements `INSERT`; `close()` menutup koneksi. Kolom array string disimpan TEXT apa adanya (format csdm `"a,b"` / `"x1,y1,x2,y2"`).
- [ ] **Step 4:** Run `npm test` → PASS.
- [ ] **Step 5: Commit** — `git commit -am "feat(csdm-export): csdmm sqlite writer with byte-identical blobs"`

### Task 3: Fetcher meta + rounds (PostgreSQL → struct)

**Files:**
- Create: `src/db/types.ts` (Kysely `Tables` interface subset), `src/export/fetch-match-meta.ts`, `src/export/fetch-rounds.ts`
- Test: `test/fetch-meta.test.ts`

**Interfaces:**
- Consumes: `connectDatabase` (Task 1).
- Produces: `fetchMatchMeta(db, checksum): Promise<MatchMeta | null>` — `{checksum, mapName, tickrate, tickCount, game, demoName, date, duration}` dari `matches ⋈ demos` (join `checksum`; map/tickrate/duration/tick_count/game/name live di `demos`). `fetchRounds(db, checksum): Promise<RoundRow[]>` sorted by round_number.

- [ ] **Step 1: Failing test** — fixture → `fetchMatchMeta` = `{checksum:'fixt', mapName:'de_mirage', tickrate:64, ...}`; `fetchRounds` length 2, ronde 1 punya `startTick` dsb. `fetchMatchMeta(db,'nope')` → null.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Implement** — dua query kysely biasa.
- [ ] **Step 4:** Run → PASS. Commit: `feat(csdm-export): match meta and rounds fetchers`

### Task 4: Fetcher positions (raw bytea) + hasPositions

**Files:**
- Create: `src/export/fetch-player-positions.ts`
- Test: `test/fetch-positions.test.ts`

**Interfaces:**
- Consumes: fixture blobs (Task 1).
- Produces: `fetchPlayerPositions(db, checksum): Promise<PlayerPositionRow[]>` — kolom blob sebagai `Buffer` mentah (pg mengembalikan bytea sebagai Buffer); `hasPositions(db, checksum): Promise<boolean>` (EXISTS 1 row).

- [ ] **Step 1: Failing test** — assert length 2 (2 pemain), row Alice: `Buffer.isBuffer(row.ticks)`, `row.ticks.equals(fixtureTicks)`, `row.x.equals(fixtureX)`, `row.activeWeaponName` array paralel per state, dst. **Byte-identity check** semua 22 kolom blob vs fixture.
- [ ] **Step 2:** Run → FAIL. **Step 3:** implement `db.selectFrom('player_positions').where('match_checksum','=',checksum).selectAll()`. **Step 4:** PASS.
- [ ] **Step 5: Commit** — `feat(csdm-export): raw player positions fetcher`

### Task 5: Fetcher kills + shots

**Files:**
- Create: `src/export/fetch-kills.ts`, `src/export/fetch-shots.ts`
- Test: `test/fetch-events.test.ts`

**Interfaces:**
- Produces: `fetchKills(db, checksum): Promise<KillRow[]>`, `fetchShots(db, checksum): Promise<ShotRow[]>` — kolom persis skema `.csdmm` (Task 2): kills (round_number, tick, killer/victim/assister steam_id, sides, weapon_name, headshot, posisi xy, through_smoke, no_scope, penetrated_objects), shots (round_number, tick, shooter_steam_id, weapon_name, x, y, player_yaw).

- [ ] **Step 1: Failing test** — fixture: 2 kills (1 headshot), 3 shots; assert mapping field-by-field. **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(csdm-export): kills and shots fetchers`

### Task 6: Fetcher grenades + infernos + events

**Files:**
- Create: `src/export/fetch-grenades.ts`, `src/export/fetch-infernos.ts`, `src/export/fetch-events.ts`
- Test: `test/fetch-grenades.test.ts`

**Interfaces:**
- Produces: `fetchGrenades` (blob ticks/x/y/z mentah + grenade_name, thrower_steam_id, thrower_side), `fetchInfernos` (ticks blob + convex_hulls_2d text[]), `fetchGrenadeEvents(db, checksum): Promise<GrenadeEventRow[]>` — UNION ALL 4 tabel (`smokes_start` type `'smoke_start'`, `flashbangs_explode` → `'flash_explode'`, `he_grenades_explode` → `'he_explode'`, `decoys_start` → `'decoy_start'`) diproyeksikan ke (round_number, tick, type, x, y, grenade_id), sorted tick. `fetchBombEvents(db, checksum): Promise<BombEventRow[]>` — 5 tabel (`bombs_plant_start`→`'plant_start'`, `bombs_planted`→`'planted'`, `bombs_defuse_start`→`'defuse_start'`, `bombs_defused`→`'defused'`, `bombs_exploded`→`'exploded'`) diproyeksikan (round_number, tick, type), sorted tick.

- [ ] **Step 1: Failing test** — fixture berisi masing-masing 1 event; assert union benar, type mapping benar, urutan tick benar. **Step 2:** FAIL. **Step 3:** implement (kysely `union` atau 4 query + merge sort di TS — pilih merge di TS, lebih sederhana). **Step 4:** PASS. **Step 5:** commit `feat(csdm-export): grenade, inferno, event fetchers`

### Task 7: Fetcher players (nama authoritative) + teams

**Files:**
- Create: `src/export/fetch-players.ts`
- Test: `test/fetch-players.test.ts`

**Interfaces:**
- Produces: `fetchPlayers(db, checksum): Promise<PlayerRow[]>` — `SELECT p.steam_id, COALESCE(o.name, p.name) as name, p.team_name, p.color FROM players p LEFT JOIN steam_account_overrides o ON o.steam_id = p.steam_id WHERE p.match_checksum = ?` (tanpa kolom `side` — deviasi Task 2).

- [ ] **Step 1: Failing test** — Alice tampil sebagai `AliceOverride` (override menang), Bob tetap `Bob`. **Step 2:** FAIL. **Step 3:** implement query COALESCE. **Step 4:** PASS. **Step 5:** commit `feat(csdm-export): authoritative player names with overrides`

### Task 8: Fetcher map transform

**Files:**
- Create: `src/export/fetch-map-transform.ts`
- Test: `test/fetch-map-transform.test.ts`

**Interfaces:**
- Produces: `fetchMapTransform(db, mapName, game): Promise<MapTransformRow | null>` — dari `maps WHERE name=? AND game=?`; null → penanganan "unsupported" ada di app.

- [ ] **Step 1: Failing test** — fixture punya `de_mirage` cs2 → row terisi; `de_nuke` → null (fixture tidak menambahkan). **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(csdm-export): map transform fetcher`

### Task 9: Orchestrator exportMatch

**Files:**
- Create: `src/export/export-match.ts`
- Test: `test/export-match.test.ts`

**Interfaces:**
- Consumes: semua fetcher (Task 3–8) + `CsdmmWriter` (Task 2).
- Produces: `exportMatch(db: Kysely<DB>, checksum: string, outDir: string): Promise<{ filePath: string; hasPositions: boolean }>` — kumpulkan semua fetcher `Promise.all`, tulis via writer ke `{outDir}/{checksum}.csdmm.tmp`, lalu `fs.rename` atomik. Match tanpa positions → positions kosong, `hasPositions=false`, meta `has_positions='false'`.

- [ ] **Step 1: Failing test** — export fixture → file ada; buka hasil: jumlah row semua tabel benar; **blob player_positions hasil ekspor `equals` fixture buffer** (identity end-to-end); meta `tickrate='64'`; test kedua: hapus semua row `player_positions` fixture → export sukses, `has_positions='false'`.
- [ ] **Step 2:** FAIL. **Step 3:** implement orchestrator. **Step 4:** PASS (kedua skenario). **Step 5:** commit `feat(csdm-export): exportMatch orchestrator writing atomic .csdmm`

### Task 10: Fastify server + token auth

**Files:**
- Create: `src/serve/server.ts`
- Test: `test/server.test.ts`

**Interfaces:**
- Consumes: `exportMatch`, `connectDatabase`.
- Produces: `createServer(opts: { db, token, outDir }): FastifyInstance` dengan route: `GET /api/matches` → JSON `{checksum, mapName, date, duration, tickrate, hasPositions}[]` (query EXISTS positions per match); `GET /api/matches/:checksum/export` → stream `{outDir}/{checksum}.csdmm` (Content-Type `application/octet-stream`, Content-Length; 404 + auto-`exportMatch` sekali bila file belum ada). Hook `onRequest`: semua `/api/*` wajib `Authorization: Bearer {token}` else 401.

- [ ] **Step 1: Failing test** — `fastify.inject`: tanpa token → 401; token salah → 401; `GET /api/matches` dengan token → 200 berisi fixture; `GET /api/matches/fixt/export` → 200, body bytes = isi file fixture (export dulu via orchestrator), Content-Length benar; checksum tak dikenal → 404.
- [ ] **Step 2:** FAIL. **Step 3:** implement fastify (plugin `@fastify/*` minimal; stream via `fs.createReadStream`). `npm i -D @types/... sudah ada`. **Step 4:** PASS. **Step 5:** commit `feat(csdm-export): lan http server with bearer auth and export streaming`

### Task 11: LAN IP + QR + mDNS

**Files:**
- Create: `src/serve/network.ts`
- Test: `test/network.test.ts`

**Interfaces:**
- Produces: `getLanIpv4(): string | null` — iterasi `os.networkInterfaces()`, filter IPv4 non-internal, prefer range 192.168/10./172.16–31; null bila offline. `printPairingQr(url: string): Promise<void>` — `qrcode` → SVG string → log + `qrcode-terminal` fallback kecil. `advertiseService(name: string, port: number): void` / `stopAdvertise(): void` via `bonjour-service` (`Bonjour.publish({name, type:'csdmm', port, txt:{v:'1'}})`).

- [ ] **Step 1: Failing test** — `getLanIpv4()` mengembalikan string non-null di env test dengan interface loopback tetap diabaikan (assert bukan `127.0.0.1`); `advertiseService` start/stop tanpa throw; URL QR mengandung token.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(csdm-export): lan detection, qr pairing, mdns advertise`

### Task 12: CLI + README

**Files:**
- Create: `src/cli.ts`, `README.md`

**Interfaces:**
- Consumes: semua di atas.
- Produces: `npm run cli -- export --checksum X [--out DIR]` dan `npm run cli -- serve [--port 7323] [--out DIR]`. `serve` = connectDatabase(CSDM_DATABASE_URL) → createServer → listen di `getLanIpv4()` → print QR `http://{lanIp}:{port}/#{token}` → advertise mDNS → SIGINT clean shutdown.

- [ ] **Step 1: Implement CLI** (commander tidak perlu — parse argv manual cukup; YAGNI): `process.argv[2]` switch. Token di-generate `crypto.randomBytes(24).toString('base64url')` per start serve.
- [ ] **Step 2: Manual verify** (syarat: DB csdm asli berisi match dengan positions): `CSDM_DATABASE_URL=... npm run cli -- export --checksum <real>` lalu `sqlite3 <file> "select count(*) from player_positions"` — row > 0; lalu `serve` → QR muncul di terminal → curl dengan token → unduhan `.csdmm` valid.
- [ ] **Step 3: README** — cara pakai (env var, kedua perintah, keamanan token, catatan `analyzePositions`).
- [ ] **Step 4: Final gate** — `npm run typecheck && npm test` semua PASS. Commit: `feat(csdm-export): cli and readme`

---

## Self-Review

- **Spec coverage §3 (format):** Task 2 (writer skema) + Task 4–8 (semua tabel) + Task 9 (meta/format_version/has_positions) ✓ — deviasi `players.side` terdokumentasi di Task 2 (alasan: `MatchPlayerTable` tidak punya side; blob state otoritatif).
- **Spec coverage §4 (protokol):** Task 10 (API + auth), Task 11 (QR/mDNS/LAN bind), Task 12 (CLI serve) ✓ — WS events opsional v1: tidak dibuat (YAGNI, app v1 pakai polling `/api/matches`).
- **Placeholder scan:** tidak ada TBD; semua step punya kode/assert konkret ✓.
- **Type consistency:** `PlayerRow/RoundRow/KillRow/...` konsisten Task 2→9; checksum `string`, blob `Buffer` ✓.
- **Review Focus ↔ tests:** byte-identity (Task 4 + 9), COALESCE nama (Task 7), tanpa positions (Task 9), auth/bind (Task 10), peta tak dikenal (Task 8 + 9) ✓.
