# Feasibility: cs-demo-manager → Aplikasi Mobile (2D viewer di HP)

Tanggal: 2026-11-02. Sumber riset: @librarian (ses_e65b46bf0ffeVVcw9eKXAjOZoI), terverifikasi live Nov 2026.

## Jawaban singkat

**Parse demo di HP: tidak praktis. Unduh demo dari Steam: bisa, tapi via server.**
Arsitektur yang masuk akal: **parse di server, render 2D di HP, cache hasil parse di SQLite HP.**

## Temuan kunci

### 1. Parsing di mobile tidak layak (2026)

- `saul/demofile` (parser JS lama) **tidak mendukung CS2** — archived Apr 2026, blocker protocol 5 (issue #398). CS:GO only.
- Satu-satunya parser JS yang bisa jalan di browser: **`cs2parser`** (npm, aktif, WASM snappy embedded, full entity mode: posisi/grenade/round; dipakai produksi radar.dust2.org).
- Masalah di React Native: **Hermes tidak punya WebAssembly** → polyfill `webassemblyjs` sangat lambat, atau parse di server.
- Perkiraan di HP modern: **20–90 detik+/demo** (desktop native 1–3 dtk), puncak RAM **1–2 GB** → OOM di demo 300 MB.
- Tidak ada proyek produksi mana pun yang parse CS2 client-side di mobile. radar.dust2.org: parse di server, browser hanya render.

### 2. Download demo dari Steam — alur masih jalan

```
sharecode
  → decode csgo-sharecode
  → Steam Web API ICSGOPlayers_730/GetNextMatchSharingCode
     (butuh: Steam Web API key + match auth code per-akun sebagai steamidkey)
  → http://replayNNN.valve.net/730/....dem.bz2   (GET polos, tanpa auth, kedaluwarsa ~1 minggu)
```

- **GOTV only** — demo POV tidak pernah tersedia via sharecode.
- cs-demo-manager sendiri pakai `boiler-writter` (Steamworks GC, butuh Steam client login) — jalur desktop, bukan mobile.
- **Faceit**: `GET open.faceit.com/data/v4/matches/{id}` → `demo_url` (.dem.gz), butuh Bearer key server-side (jangan pernah di app).

## Arsitektur rekomendasi

```
[HP: app RN/Expo]  ──HTTP──>  [Server backend kecil]  ──>  Steam/Faceit (unduh .dem)
       │                            │
       │  render 2D canvas          │  parse: cs2parser (atau reuse parser csdm di src/node)
       ▼                            ▼
[SQLite HP: hasil parse ringkas] <──JSON ticks/posisi/round──┘
```

- **HP** = renderer 2D (canvas/Skia) + cache SQLite berisi data hasil parse (posisi per tick, events, score) — bukan demo mentah.
- **Server** = unduh (valve.net/Faceit), parse sekali, kirim JSON ringkas. Bisa reuse kode csdm: `src/node/` (valve-match, download) + `@akiver/cs-demo-analyzer`.
- Ukuran payload: pre-compute ringkas per round (~ratusan KB) vs raw ticks (puluhan MB) — pilih resolusi tick yang disimpan.

## Alternatif (kalau insist tanpa server)

1. **Parse native**: Rust (`source2-demo`) + wasm-bindgen/JNI — kerja besar, belum ada yang ship.
2. **MAUI + demofile-net** (C#/AOT, 0.9 dtk/demo di M1 Pro) — keluar dari ekosistem JS/RN.
3. **cs2parser + polyfill WASM di Hermes** — lambat + OOM, hanya layak untuk demo kecil.

## Kesimpulan

Layak dibuat, dengan syarat: parse jangan di HP. Backend kecil (satu VPS / Cloudflare Worker + parser) + app mobile sebagai viewer. Detail keamanan unduhan (API key, auth code) hidup di server — sejalan dengan temuan audit: kredensial jangan pernah masuk client.
