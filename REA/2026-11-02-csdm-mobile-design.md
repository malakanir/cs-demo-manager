# Spec Desain: CS2 Mobile 2D Viewer ("csdm-mobile")

Tanggal: 2026-11-02
Status: Draft untuk review
Materi sumber: `REA/viewer-db-schema.md` (skema DB), `REA/viewer-2d-audit.md` (viewer desktop), `REA/mobile-feasibility.md` (riset mobile), `REA/audit-report.md` (keamanan).
Lampiran UX otoritatif: `REA/viewer-mobile-ux.md` (orientasi landscape-first, blueprint layout, gesture map, label bertingkat zoom) — layar viewer mengikuti dokumen tersebut.

---

## 0. Ringkasan

Aplikasi mobile (Flutter, iOS + Android) untuk memutar ulang replay 2D match CS2. Parsing demo tetap terjadi di PC (cs-demo-manager + PostgreSQL); sebuah tool PC terpisah (`csdm-export`) mengekspor satu match menjadi file SQLite ringkas dan menyajikannya ke HP melalui HTTP di LAN. HP merender playback 2D penuh dari data mentah per-tick, dengan cache lokal untuk akses offline.

**Tidak memodifikasi cs-demo-manager sama sekali.**

Keputusan produk (disepakati user):

| Keputusan | Pilihan |
|---|---|
| Target | Produk publik (Play Store / App Store) |
| Ingesti demo | Manual dulu (v1 via tool PC; upload/URL = v2) |
| Transfer PC→HP | P2P LAN langsung |
| Stack mobile | **Flutter** |
| Lingkup v1 | 2D replay penuh (posisi, grenade, kill feed, scrub, pilih round) |
| Sisi PC | Tool terpisah, csdm tak tersentuh |
| Format ekspor | Raw per-tick (blob bytea disalin apa adanya, ~20–60 MB/match) |
| Keamanan | QR + token pairing, bind LAN, read-only |
| v2+ | Kompresi zstd, cloud sync, NAT traversal lintas internet |

## 1. Arsitektur

```
┌────────────────────────────── PC ──────────────────────────────┐
│  cs-demo-manager + PostgreSQL (tidak diubah)                   │
│        ↑ read-only (Kysely read)                               │
│  csdm-export (Node.js/TS, tool terpisah)                       │
│   • eksportir: PostgreSQL → SQLite per-match (.csdmm)          │
│   • server LAN: HTTP + WS, mDNS _csdmm._tcp, QR pairing        │
└──────────────────────────┬─────────────────────────────────────┘
                           │ Wi-Fi sama, HTTP + token
┌──────────────────────────▼─────────────────────────────────────┐
│  App Flutter (iOS/Android)                                     │
│   • discovery + pairing (QR / daftar host)                     │
│   • download match → cache SQLite lokal (driftwood: sqflite)   │
│   • playback engine (port dari viewer desktop)                 │
│   • render CustomPainter + Ticker                              │
└────────────────────────────────────────────────────────────────┘
```

Tiga unit, satu tanggung jawab per unit:

1. **csdm-export** — membaca DB csdm, menghasilkan `.csdmm`, melayankannya. Tidak tahu apa-apa tentang Flutter.
2. **App** — konsumsi `.csdmm`, memutar replay. Tidak membaca PostgreSQL, tidak menyentuh demo mentah.
3. **Kontrak** — format `.csdmm` (§3) + protokol LAN (§4). Dua unit di atas hanya bertemu di sini.

## 2. Lingkup v1 (dan yang sengaja tidak)

**Ada di v1:**
- Playback 2D penuh: pemain (posisi/yaw/nama/HP/warna tim), grenade (lintasan + efek ledakan/smoke), inferno (hull), kill feed, bom (carrier/planth/ledakan), shots (garis animasi).
- Timeline scrub + play/pause + speed 0.5×–4× + pilih ronde.
- Pan/zoom sentuh (pinch), clamp 0.1×–5×.
- Cache offline: match yang pernah dibuka bisa diputar ulang tanpa PC.
- Radar CS2 (atas; level bawah opsional), bundling aset di app.
- Pairing QR + token, mDNS discovery.

**Tidak ada di v1 (YAGNI, tersimpan untuk v2+):**
- Kompresi zstd; audio sync (butuh transfer file audio); radar bawah interaktif; mode gambar/tulisan di atas peta; upload demo dari HP; Faceit/Steam ingest; cloud sync; NAT traversal; hostage/chicken timelines (render saja jika mudah, jangan blokir rilis); CSGO radar set (bundling CS2 saja dulu).

## 3. Format `.csdmm` (SQLite per-match)

Satu match = satu file SQLite. Nama: `{checksum}.csdmm`.

### 3.1 Skema

```sql
-- metadata tunggal
CREATE TABLE match (
  key TEXT PRIMARY KEY,          -- 'checksum','map_name','tickrate','tick_count','game','date','demo_name','duration'
  value TEXT NOT NULL
);

-- nama authoritative: players COALESCE steam_account_overrides (lihat viewer-db-schema.md §3)
CREATE TABLE players (
  steam_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  side INTEGER NOT NULL,         -- 2=T 3=CT
  team_name TEXT,
  color TEXT
);

CREATE TABLE rounds (
  round_number INTEGER PRIMARY KEY,
  start_tick INTEGER NOT NULL,
  freeze_time_end_tick INTEGER NOT NULL,
  end_tick INTEGER NOT NULL,
  end_officially_tick INTEGER NOT NULL,
  winner_side INTEGER, end_reason TEXT, score_ct INTEGER, score_t INTEGER
);

-- timeline pemain: BLOB mentah disalin dari player_positions (bytea → BLOB, big-endian, semantik parallel-array tetap)
CREATE TABLE player_positions (
  round_number INTEGER NOT NULL,
  player_steam_id TEXT NOT NULL,
  ticks BLOB NOT NULL, x BLOB NOT NULL, y BLOB NOT NULL, z BLOB NOT NULL, yaw BLOB NOT NULL,
  flash_duration_remaining BLOB NOT NULL, is_ducking BLOB NOT NULL, is_airborne BLOB NOT NULL,
  state_ticks BLOB NOT NULL, is_alive BLOB NOT NULL, side BLOB NOT NULL, money BLOB NOT NULL,
  health BLOB NOT NULL, armor BLOB NOT NULL, has_helmet BLOB NOT NULL, has_bomb BLOB NOT NULL,
  has_defuse_kit BLOB NOT NULL, is_scoping BLOB NOT NULL, is_defusing BLOB NOT NULL,
  is_planting BLOB NOT NULL, is_grabbing_hostage BLOB NOT NULL,
  active_weapon_name TEXT NOT NULL, equipments TEXT NOT NULL, grenades TEXT NOT NULL,
  pistols TEXT NOT NULL, smgs TEXT NOT NULL, rifles TEXT NOT NULL, heavy TEXT NOT NULL,
  PRIMARY KEY (round_number, player_steam_id)
);

CREATE TABLE grenades (           -- dari grenade_positions
  round_number INTEGER NOT NULL,
  grenade_id TEXT NOT NULL, projectile_id TEXT NOT NULL, grenade_name TEXT NOT NULL,
  thrower_steam_id TEXT NOT NULL, thrower_side INTEGER NOT NULL,
  ticks BLOB NOT NULL, x BLOB NOT NULL, y BLOB NOT NULL, z BLOB NOT NULL,
  PRIMARY KEY (round_number, grenade_id)
);

CREATE TABLE infernos (           -- dari inferno_positions
  round_number INTEGER NOT NULL, unique_id TEXT NOT NULL, thrower_steam_id TEXT NOT NULL,
  ticks BLOB NOT NULL, convex_hulls_2d TEXT NOT NULL,   -- "x1,y1,x2,y2,..."
  PRIMARY KEY (round_number, unique_id)
);

CREATE TABLE kills (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  killer_steam_id TEXT, victim_steam_id TEXT NOT NULL, assister_steam_id TEXT,
  killer_side INTEGER, victim_side INTEGER NOT NULL,
  weapon_name TEXT NOT NULL, headshot INTEGER NOT NULL,
  killer_x REAL, killer_y REAL, victim_x REAL, victim_y REAL,
  through_smoke INTEGER, no_scope INTEGER, penetrated_objects INTEGER
);

CREATE TABLE shots (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  shooter_steam_id TEXT NOT NULL, weapon_name TEXT NOT NULL,
  x REAL NOT NULL, y REAL NOT NULL, player_yaw REAL NOT NULL
);

CREATE TABLE bomb_events (
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  type TEXT NOT NULL              -- 'plant_start','planted','defuse_start','defused','exploded'
);

CREATE TABLE grenade_events (     -- smokes_start, flashbangs_explode, he_grenades_explode, decoys_start
  round_number INTEGER NOT NULL, tick INTEGER NOT NULL,
  type TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL, grenade_id TEXT
);

-- parameter transform radar per match (satu baris, dari tabel maps csdm)
CREATE TABLE map_transform (
  name TEXT NOT NULL, position_x REAL NOT NULL, position_y REAL NOT NULL,
  scale REAL NOT NULL, threshold_z REAL NOT NULL, game TEXT NOT NULL
);

CREATE INDEX idx_kills_round ON kills(round_number, tick);
CREATE INDEX idx_shots_round ON shots(round_number, tick);
```

Catatan skema mengikuti laporan `viewer-db-schema.md`; keputusan raw per-tick (tanpa sampling 16 Hz) = §6 poin 1 di laporan itu.

### 3.2 Dekoder blob (port ke Dart)

Semua BLOB big-endian, paralel: kolom movement per `ticks[i]`, kolom state per `state_ticks[i]`. Referensi dekoder: `src/node/database/decode-packed-positions.ts`. Port Dart: kelas `PackedTimeline` dengan `ByteData.getInt32(..., Endian.big)` / `getFloat32`. Ini port kecil (< 100 baris) dan **satu-satunya logika biner di app**.

## 4. Protokol LAN (csdm-export)

### 4.1 Endpoint HTTP

- `GET /` — halaman daftar match (HTML minimal; berguna juga untuk debugging di browser PC).
- `GET /api/matches` — JSON daftar match (checksum, map, tanggal, duration, has_positions).
- `GET /api/matches/{checksum}/export` — unduh `.csdmm` (Content-Length + streaming; 20–60 MB harusnya bisa resume via Range — nice-to-have, bukan syarat).
- `WS /api/events` — (opsional v1) notifikasi "match baru selesai diekspor".

### 4.2 Keamanan (pelajaran dari audit-report.md)

- **Bind hanya ke antarmuka LAN** (bukan 0.0.0.0 tanpa batas — pilih IP LAN aktif; csdm gagal di sini: `server.ts:77` bind semua antarmuka tanpa auth).
- **Wajib token**: semua endpoint (kecuali halaman QR) butuh header `Authorization: Bearer {token}`; QR berisi `http://{ip}:{port}/#/{token}`. Token di-generate saat tool start, tampil sebagai QR.
- Tool **read-only** terhadap PostgreSQL: satu string koneksi read-only, tanpa endpoint tulis.
- Tanpa kredensial Steam/Faceit di app — tool tidak punya kredensial apa pun.

### 4.3 Discovery

- mDNS advertise `_csdmm._tcp` (nama host + port + checksum instance). App: paket `bonsoir` (mDNS Dart). Fallback: input IP manual.

### 4.4 Match tanpa positions

`player_positions` hanya ada jika demo dianalisis `analyzePositions:true` (default false). Tool menandai `has_positions=false` di daftar; men-trigger re-analyze = **di luar lingkup v1** (user jalankan analisis dari csdm dulu). Tersimpan sebagai batasan yang didokumentasikan.

## 5. App Flutter

### 5.1 Struktur paket

```
csdm_mobile/
  lib/
    models/        # PackedTimeline, Round, Kill, GrenadeTimeline... (dari §3)
    playback/      # playback_controller.dart (Riverpod), positions_at_tick.dart
    render/        # map_painter.dart, players_painter.dart, effects_painter.dart
    transfer/      # discovery (bonsoir), pairing, download, cache (sqflite)
    ui/            # screens: matches, viewer, rounds_bar, playback_bar, teams_panel
  assets/
    radars/cs2/{map}.png        # dari static/images/maps/cs2/radars/ (51 buah)
    maps.json                   # dari src/node/database/maps/default-maps.ts
```

State: `Riverpod`. Tidak ada state management lain.

### 5.2 Playback engine (port dari viewer desktop)

Port langsung dari `src/ui/match/viewer-2d/` (detail di `viewer-2d-audit.md` §5):

- State tunggal: `currentTick` (init `freeze_time_end_tick` ronde aktif).
- `Ticker` (flutter): `ticksToAdvance = elapsed * tickrate * speed`; sisa fraksional dibawa ke frame berikutnya (presisi sama dengan implementasi desktop).
- **Interpolasi** (`positions_at_tick.dart`, port `players-timelines.ts`): posisi linear; **yaw circular** `((to-from)%360+540)%360-180`; flash linear; state = step function (`findLastIndexAtOrBeforeTick`, binary search O(log n)); **clamp: gap > tickrate → hold sampel sebelumnya** (pemain mati/putus).
- Meski ekspor raw per-tick, interpolasi tetap diperlukan untuk scrub halus + speed rendah.

### 5.3 Render

- `CustomPainter` per layer, urutan sama seperti desktop (`viewer-2d-audit.md` §4): radar → inferno → grenade paths → players → shots → efek (smoke ring, flash arc, kill X, bom ikon).
- Warna tokennya disalin: CT `#378ef0`, T `#f29423`; HE `#268e6c`, Smoke `#737373`, Flash `#f9a43f`, Molotov `#da7b11`, Decoy `#f76d74`; pie HP `#d7373f99`; inferno fill `rgba(218,123,17,0.5)`.
- Semua animasi efek = fungsi murni `(currentTick - eventTick) / tickrate` — tidak ada animasi bernegara.
- Transform koordinat (verbatim, dari `viewer-2d-audit.md` §7):
  ```
  x' = (x - posX) / scale * imageSize / radarSize
  y' = (posY - y) / scale * imageSize / radarSize   // Y dibalik
  ```
  `radarSize` dari lebar PNG aktual; lower level saat `z < threshold_z` (v1: render dua lapis radar statis, switch per-pemain boleh mengikuti desktop).
- Gestur: pan satu jari + pinch zoom (clamp 0.1×–5×), zoom di titik sentuh.
- Overlay (di luar canvas): kill feed (tampil 5 dtk game-time), timer ronde `(endOfficiallyTick - currentTick)/tickrate`, bar playback dengan penanda kill/bomb/freezetime.

### 5.4 Cache offline

- `sqflite`: file `.csdmm` yang diunduh diimpor utuh ke DB app per-match (key: checksum).
- Batas cache default 1 GB, LRU eviction (skip jika trivial — bisa v1.1).

## 6. Penanganan error

| Kasus | Perilaku |
|---|---|
| PC/matikan server saat transfer | Download dibatalkan dengan pesan; cache lama tetap valid |
| Match tanpa positions | Baris dinonaktifkan + tooltip "analisis positions di csdm dulu" (§4.4) |
| Peta tak dikenal (tanpa radar) | Layar "Unsupported map" (paritas dengan desktop `viewer-2d-loader.tsx:231`) |
| Token salah/ditolak | Minta scan ulang QR; tidak ada retry otomatis |
| Blob rusak/versi format beda | Tolak impor dengan pesan versi; format punya `format_version` di tabel `match` |

## 7. Testing

- **csdm-export**: unit test transformasi PostgreSQL→SQLite dengan fixture mini (2 pemain, 2 ronde, blob sintetis); verifikasi byte-identik untuk kolom BLOB.
- **App**:
  - unit: `PackedTimeline` (golden bytes → nilai), `positions_at_tick` (interpolasi linear/yaw circular/clamp — port test dari kasus desktop), scrub math.
  - golden test painter: 1 frame ronde dengan 2 pemain + 1 grenade + 1 kill, dibanding PNG emas.
  - widget test: playback bar scrub, round switch.
- **E2E manual (syarat rilis v1)**: 1 match riil de_mirage dengan positions — export → transfer → playback 30 ronde 60 fps di HP kelas menengah, scrub penuh, kill feed, grenade effects.
- Benchmark: playback 64 tick tanpa jank (target frame budget 16 ms; ukur dengan DevTools timeline).

## 8. Roadmap

| Fase | Isi |
|---|---|
| **M1: format + export tool** | Skema §3, eksportir, unit test, CLI `csdm-export serve` |
| **M2: transfer** | HTTP API + QR + mDNS; app: discovery, download, cache |
| **M3: playback inti** | PackedTimeline, positionsAtTick, ticker, painter pemain+radar |
| **M4: efek lengkap** | Grenade/inferno/shots/kill feed/bomb, pan/zoom, bar playback |
| **M5: polish + rilis** | Golden tests, benchmark jank, ikon/branding, build store |

(v2+: zstd, audio, radar interaktif, upload dari HP, cloud sync.)

## 9. Risiko

1. **Ukuran transfer 20–60 MB/match** — raw per-tick adalah keputusan sadar; Wi-Fi LAN ~10–30 MB/s → 2–6 dtk/match. Acceptable. Mitigasi v2: zstd.
2. **Paritas visual dengan desktop** — banyak detail efek; M4 bisa mundur. Mitigasi: urutan layer + warna sudah terdokumentasi verbatim; golden tests mencegah regresi.
3. **Jank di HP kelas bawah** — satu ronde per payload (bukan match), painter di-isolate per layer; tick 64 dengan < 20 entitas tergambar per frame = beban ringan.
4. **Format blob berubah di csdm** (migrasi v16+) — tool harus pin-versi skema yang didukung + tolak DB lebih baru dengan pesan jelas.
