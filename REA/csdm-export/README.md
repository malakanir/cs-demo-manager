# csdm-export

Read-only exporter dari database PostgreSQL cs-demo-manager ke file SQLite
per-match (`.csdmm`) untuk viewer 2D di HP, plus server LAN kecil untuk
mengunduh hasil ekspor dari HP lewat QR pairing.

## Prasyarat

- PostgreSQL milik cs-demo-manager yang sudah berisi match (hasil analisis
  demo).
- **Positions hanya ada jika demo dianalisis dengan `analyzePositions: true`
  di cs-demo-manager** (default-nya false). Tanpa itu, file tetap terekspor
  tapi `has_positions=false` dan playback 2D tidak bisa berjalan — analisis
  ulang demonya di csdm terlebih dahulu.
- Node.js >= 22.

## Environment variable

- `CSDM_DATABASE_URL` — URL koneksi PostgreSQL, misal
  `postgres://postgres:postgres@localhost:5432/csdm`. Bisa juga dilewatkan
  per-perintah dengan `--database`.

## Perintah

```sh
npm install

# Ekspor satu match menjadi ./exports/{checksum}.csdmm
npm run cli -- export --checksum <checksum> [--out DIR]

# Jalankan server LAN + QR pairing (default port 7323)
npm run cli -- serve [--port 7323] [--out DIR]
```

`serve` mencetak QR di terminal; HP (atau laptop) yang memindainya dapat
mengunduh match dari `GET /api/matches/{checksum}/export`.

## Keamanan

- **Token per start**: setiap kali `serve` dijalankan, token baru dibuat dan
  hanya dibagikan lewat QR (`http://{ip}:{port}/#{token}`). Semua endpoint
  `/api/*` wajib `Authorization: Bearer {token}`.
- **Bind LAN/private saja**: server bind ke IP privat yang terdeteksi
  (192.168.* / 10.* / 172.16–31.*). Jika tidak ada, fallback ke `127.0.0.1`
  (local only) dengan peringatan.
- **Read-only**: tool hanya membaca PostgreSQL; tidak ada endpoint tulis dan
  tidak ada kredensial apa pun yang disimpan.
- Service diiklankan via mDNS `_csdmm._tcp` agar app bisa menemukan host
  tanpa input IP manual.

## Format `.csdmm`

Satu match = satu file SQLite bernama `{checksum}.csdmm`: tabel `match`
(metadata key/value, termasuk `format_version` dan `has_positions`), lalu
`players`, `rounds`, `player_positions`, `grenades`, `infernos`, `kills`,
`shots`, `bomb_events`, `grenade_events`, dan `map_transform`. Kolom timeline
disimpan sebagai BLOB big-endian mentah per-tick (disalin apa adanya dari
`player_positions`/`grenade_positions` PostgreSQL), ukuran ~20–60 MB per
match.

Aplikasi mobile mengonsumsinya sesuai spec `REA/2026-11-02-csdm-mobile-design.md`
§3: unduh file lewat endpoint `/api/matches/{checksum}/export` (dengan token
dari QR), impor utuh ke SQLite lokal sebagai cache offline, dekode BLOB
big-endian dengan kelas `PackedTimeline` (port dari
`src/node/database/decode-packed-positions.ts` — satu-satunya logika biner di
app), lalu render playback 2D per-tick. Versi format diverifikasi lewat
`match.format_version`; peta tanpa radar ditolak ke layar "Unsupported map".

## Development

```sh
npm test        # butuh PostgreSQL yang bisa dijangkau (lihat bawah)
npm run typecheck
```

Tests membuat dan menghapus database `csdm_export_test` di server yang
ditunjuk `CSDM_TEST_DATABASE_URL`
(default `postgres://postgres:postgres@localhost:5432/csdm_export_test`).
Tidak ada di luar database itu yang disentuh.
