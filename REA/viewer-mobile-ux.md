# UX Mobile Viewer 2D (Lampiran Spesifikasi csdm-mobile)

Tanggal: 2026-11-02. Status: bagian UX otoritatif, dilampirkan ke `2026-11-02-csdm-mobile-design.md`.
Sumber: spec §5.2–5.3, `viewer-2d-audit.md` §4–§7. Tidak mengubah: warna token, mesin interpolasi, kill feed 5 dtk game-time, speed 0.5×–4×, clamp zoom 0.1×–5×, budget frame 16 ms.

---

## 1. Strategi Orientasi

**Rekomendasi: landscape-first, tanpa lock.** Bukan locked-portrait.

Alasan:

1. Radar persegi (1024/2048). Di portrait, lebar layar (~360–430 dp) membatasi radar ke ~55% luas layar — sisanya jadi ruang kosong vertikal yang hanya bisa diisi bar. Di landscape, radar memakan tinggi layar penuh (~360–400 dp pada ponsel modern) dan playback bar mendapat lebar 700–900 dp — lebar inilah yang dibutuhkan scrub dengan penanda kill/bomb/freezetime (desktop menaruh penanda di bar; penanda bertumpuk bila bar sempit).
2. Penggunaan inti = menonton + scrub. Pola tontonan (video/game), bukan daftar-baca. Standar mental pengguna: konten tontonan → diputar landscape.
3. Parse demo tetap di PC; HP murni konsumen — tidak ada alur input teks panjang di viewer yang menguntungkan portrait.

Kebijakan teknis:

- Layar viewer: `SystemChrome` **auto-rotate penuh** (landscape diutamakan). Saat masuk viewer di portrait, tampilkan banner sekali: "Putar HP untuk pengalaman terbaik" — jangan paksa (pengguna bisa sedikit rebahan; paksa rotasi = anti-pola aksesibilitas).
- Semua layar non-viewer (match list, pairing, download): **portrait lock** — form/daftar lebih ergonomis, beban layout lebih kecil.
- Landscape = layout utama yang didesain dan dites lebih dulu (M4). Portrait = fallback fungsional, bukan warga kelas dua, tapi pemenang fitur lebih sedikit (lihat §2.3).

## 2. Blueprint Layout

### 2.1 Landscape (primer)

Prinsip: meniru anatomi desktop (bar playback bawah, rounds di tepi, panel tim di tepi) tapi semua chrome **mengapung di atas canvas** dan **auto-hide** saat playback berjalan — radar jadi full-bleed.

Zona (persentase dari lebar/tinggi layar):

- Canvas radar: full-bleed, tinggi 100%, di bawah semua overlay.
- Playback bar: bawah, tinggi ~64 dp, lebar ~70%, center, margin bawah aman (home indicator iOS 34 dp / gesture bar Android 24 dp).
- Rounds selector: strip vertikal di tepi KIRI, lebar ~56 dp, tinggi ~60%, center-vertikal. Berbentuk rail chip "12 ▸ 13 ● 14" (angka ronde + dot pemenang). Auto-hide bersama chrome.
- Teams panel: tepi KANAN atas, lebar ~180–220 dp, dua kartu skor (CT/T) + daftar pemain ringkas (nama + HP bar). Collapsible: tap kartu skor = expand/collapse daftar. Auto-hide.
- Kill feed: kanan-ATAS, di bawah area teams panel yang sudah collapse — feed turun dari sudut atas-kanan (paritas desktop), lebar maks ~45% layar.
- Timer ronde + skor ringkas: pill center-ATAS (CT 7 : 8 T · 1:23), selalu tampak (tidak ikut auto-hide — informasi paling sering dilihat sekilas).

```
┌──────────────────────────────────────────────────────────────┐
│ ┌─rounds─┐              ┌ CT 7 : 8 T · 1:23 ┐  ┌─teams────┐ │
│ │ 12     │   (canvas    └───────────────────┘  │ CT  7    │ │
│ │ 13 ●   │    radar     ┌ kill feed ────────┐ │ p1  ██ 87│ │
│ │ 14     │    full-     │ k1  AK-47  v1     │ │ p2  █  42│ │
│ │ ...    │    bleed)    │ k2  AWP    v2     │ │ T   8    │ │
│ │ 24     │              └───────────────────┘ │ p1  ██ 61│ │
│ └────────┘                                    └──────────┘ │
│         ┌─────◀────────●──────▶─────┐  ⏸  1.0×  ⛭        │
│         │ scrub bar + kill/bomb tick │   (playback bar)   │
└─────────┴───────────────────────────┴─────────────────────-┘
```

Auto-hide: chrome (rounds rail, teams panel, playback bar, kill feed) fade-out 300 ms setelah **2 dtk tanpa sentuh DAN playback berjalan**. Sentuh pertama saat tersembunyi = tampilkan chrome saja (tidak diteruskan ke canvas — hindari scrub tak sengaja). Pause → chrome tampil permanen.

### 2.2 Portrait (fallback)

Zona:

- Canvas radar: persegi, atas, lebar 100%, tinggi = lebar (aspek 1:1 dipertahankan — radar persegi diperegang itu distorsi; lebar-100% adalah maksimum tanpa crop).
- Timer + skor pill: baris tipis langsung di bawah radar, tinggi ~32 dp.
- Playback bar: bawah layar fixed, tinggi ~72 dp (target sentuh ≥48 dp, thumb-zone bawah).
- Kill feed: overlay di ATAS canvas, sudut kanan-atas, mengambang di atas radar.
- Teams panel: **bottom sheet** (drag-handle, tinggi snap 25%/50%) — bukan panel samping; tepi samping terlalu sempit di portrait.
- Rounds selector: horizontal scroll strip di antara timer dan playback bar, tinggi ~44 dp (chip "R12 R13● R14…", ronde aktif auto-center).

```
┌────────────────────────┐
│      ┌ kill feed ────┐ │
│ ┌────────────────────┐ │
│ │                    │ │
│ │   radar 1:1        │ │
│ │   (square)         │ │
│ └────────────────────┘ │
│  CT 7 : 8 T   ⏱ 1:23  │
│ ── R12 · [R13●] · R14 ─│
│ ┌──────────────────────┐│
│ │ ◀─────●──────▶  ⏸ 1× ││
│ └──────────────────────┘│
└────────────────────────┘
```

### 2.3 Perbedaan perilaku portrait vs landscape

| Aspek | Landscape | Portrait |
|---|---|---|
| Chrome | Overlay full-bleed + auto-hide | Docked bawah, tidak auto-hide (canvas sudah kecil; chrome tak menutupinya) |
| Teams panel | Kartu samping collapsible | Bottom sheet |
| Rounds | Rail vertikal | Strip horizontal scroll |
| Kill feed | Kanan-atas bawah panel | Kanan-atas di atas radar |

## 3. Peta Gester

| Gester | Zona | Aksi |
|---|---|---|
| Drag 1 jari | Canvas | Pan (geser worldOrigin, paritas desktop) |
| Pinch 2 jari | Canvas | Zoom di titik tengah pinch, clamp **0.1×–5×** |
| Double-tap | Canvas | Toggle zoom 1× ↔ 2.5× (fokus cepat, tanpa pinch berulang) |
| Tap 1x | Canvas, di dekat pemain (radius hit ≥ 24 dp) | Fokus/ikuti pemain itu (kamera mengunci; ikon bingkai kecil; tap lagi/ESC-chip = lepas) |
| Tap 1x | Canvas, area kosong | Lepas fokus / sembunyikan chrome |
| Drag horizontal | Playback bar | Scrub = set `currentTick` (rumus desktop: `floor(percent*(endOfficiallyTick-startTick))+startTick`) |
| Tap | Playback bar | Lompat ke posisi tap |
| Drag vertikal pendek ATAS dari playback bar (≥ 24 dp) | Playback bar | **Fine-scrub**: laju scrub dibagi 4 (gerakan jari 4× = geser 1×) |
| Swipe kiri/kanan | Rounds bar/chip | Ganti ronde; konfirmasi tampil bila playback berjalan (mencegah lompat tak sengaja) — bila pause, langsung pindah |
| Long-press | Canvas di pemain | Tooltip mini statik: nama, HP, senjata aktif |
| Long-press | Kill feed baris | Detail kill (assister, penetrated, through-smoke, no-scope) |

**Konflik scrub vs pan** — sumber bug #1 di viewer sentuh. Resolusinya zona, bukan heuristik:

1. Playback bar punya hit-test sendiri (GestureDetector terpisah, `behavior: opaque`). Gester di bar TIDAK PERNAH diteruskan ke canvas. Bar tinggi ≥ 48 dp + padding sentuh 8 dp — tidak ada zona ambigu.
2. Chrome tersembunyi = tidak ada bar = tidak ada konflik. Aturan "sentuh pertama saat chrome tersembunyi hanya memunculkan chrome" (§2.1) menghilangkan kasus "user mau scrub, kena pan".
3. Canvas: hanya pan/zoom/tap. Tidak ada gester canvas yang berarti scrub.

Ergonomi scrub: bar di bottom-center = thumb-zone kanan (mayoritas pengguna). Fine-scrub drag-atas memakai gerakan yang sudah akrab dari scrubber video. Tambahan: saat scrub, tampilkan preview waktu (mm:ss + nomor ronde internal) mengambang di atas jari.

## 4. Kepadatan Sadar-Zoom (label pemain)

Desktop: nama font 10 selalu-on. Di ponsel (~5 dp/px radar pada zoom 1×) nama 10 dp bertumpuk antar pemain. Strategi berjenjang:

| Kondisi zoom | Pemain | Nama | HP pie (`#d7373f99`) | Garis yaw |
|---|---|---|---|---|
| < 1.0× (zoom-out) | Lingkaran r8 + stroke tim | ❌ | ✅ | ✅ (pendek) |
| 1.0×–2.0× | r8 | ✅ **hanya pemain ter-fokus** + terlibat kill terakhir (3 dtk game-time) | ✅ | ✅ |
| > 2.0× | r8 | ✅ semua, font 10 | ✅ | ✅ (segitiga knife/grenade, +6 saat scope — paritas desktop) |

Tambahan:

- HP pie SELALU tampil di semua level zoom (informasi kritis duel, murah digambar — satu arc).
- Nama on-demand: tap pemain / long-press menampilkan labelnya terlepas dari zoom (chip di atas lingkaran, bukan teks painter).
- Grenade path & label: path selalu; nama granat (teks) hanya > 2.0×.
- Performa (budget 16 ms): < 1.0× → sembunyikan teks nama (painter skip pass teks = penghematan terbesar, teks mahal), shots line dibatasi 24 terakhir; kill X, smoke ring, inferno hull tetap. Dimming: di < 1.0×, alpha layer shots 0.6. Ini keputusan render, bukan keputusan data — payload per-ronde tetap utuh.
- Efek animasi semua tetap fungsi murni `(currentTick - eventTick)/tickrate` — tak berubah.

## 5. Kill Feed & Toast

- Feed tampil 5 dtk **game-time** (bukan wall-clock): timer entri berkurang sesuai `speed` — di 4× entri hilang 4× cepat. Paritas mesin desktop; implementasi: entri = fungsi `currentTick - killTick < 5 * tickrate`, derivatif murni, tanpa timer bernegara. Maks 4 baris; yang lebih lama menggantung terpotong (sesuai tinggi tersedia).
- Posisi: kanan-atas (§2). Baris: `killer [ikon senjata] victim`, warna sisi (#378ef0/#f29423), ✚ kepala = ikon headshot. Font ≥ 12 dp, kontras cukup di atas radar (lapisan scrim gelap 40% di belakang baris).
- Ikon senjata: mapping nama → glyph bundel (set terbatas: rifle/pistol/AWP/knife/grenade/heavy; fallback = teks singkat). Bukan 500 PNG.
- Countdown smoke: lingkaran abu r26 + angka sisa detik di dalam (di > 1.0×; di bawah itu ring saja). Flash arc putih `/5.25` dan arc defuse/plant tetap mengikuti desktop (murni fungsi tick).
- Toast UI (bukan game-event): hapus dari canvas — snack bar bawah di atas playback bar untuk pesan app ("Round 14", "Cache penuh, LRU menghapus match lama" — v1.1).

## 6. Alur

### 6.1 Match list → download → viewer

```
[Pairing: QR scan / pilih host] ─▶ [Match list] ─ tap ─▶ [Sheet detail]
   Sheet detail: map, tanggal, durasi, ukuran (20–60 MB),
   tombol "Unduh & Tonton"
        │
        ▼
[Download progress layar/sheet]: progress bar byte, kecepatan, tombol Batal.
   Selesai ─▶ impor SQLite ─▶ cek has_positions & radar
        │
        ├─ ok ─▶ [Viewer] (landscape dipromosikan)
        ├─ tanpa positions ─▶ baris nonaktif + pesan (spec §4.4)
        └─ peta tak dikenal ─▶ "Unsupported map" (paritas desktop)
```

Aturan:

- Tap match yang **sudah di cache** → langsung Viewer (tanpa sheet download). Badge "offline" di baris.
- Download gagal/PC mati → pesan + cache lama tetap valid (spec §6).
- Viewer buka ronde 1, tick = `freeze_time_end_tick`, speed persist dari sesi terakhir.

### 6.2 Offline cache

- Entry point: tab/bagian "Tersimpan" di layar utama (dua tab: "PC" = daftar dari host aktif; "Tersimpan" = cache lokal).
- Baris cache: map, tanggal, ukuran, badge offline, aksi: Tonton / Hapus.
- Tanpa host aktif, tab "PC" menampilkan empty-state: "Sambungkan PC — scan QR".
- LRU eviction (batas 1 GB): v1 bisa skip per spec §5.4; UI menyediakan hapus manual + tampil total terpakai.

## 7. Yang Sengaja Dipotong dari v1

| Dipotong | Kenapa | Kapan |
|---|---|---|
| Radar bawah interaktif + offset user | Dua lapis statis saja (v1); interaktif = kompleksitas gester ganda | v2 |
| Mode gambar/tulis di canvas (desktop D, Ctrl+Z) | Gester canvas sudah padat (pan/zoom/tap/long-press); tabrakan pasti | v2, butuh mode eksplisit toggle |
| Audio replay + offset sync | Butuh transfer file audio; budget porting besar | v2 (spec §2) |
| Undo/redo, keyboard shortcut | Tidak ada keyboard di HP; YAGNI | tidak dijadwalkan |
| Panel tim lengkap (ekonomi, inventaris per pemain, klik-fokus dari panel) | Klik-fokus dari panel didelegasikan ke tap-di-canvas; inventaris = bottom sheet read-only di v1.1 | v1.1 sheet, v2 sisa |
| Pencarian/filter match list | Skala kecil (per-PC puluhan) | v1.1 |
| Brush timeline per pemain (desktop future) | Belum ada di desktop pun | mengikuti desktop |
| Bookmark/klip berbagi | Butuh format data + UI ekspor | v2 |
| Overlay editor posisi kill feed / tema | Chrome fixed; pengaturan speed+quality saja | tidak dijadwalkan |

---

**Konfirmasi file tertulis**: dokumen ini ditulis ke `REA/viewer-mobile-ux.md`, siap dilampirkan sebagai bagian UX mobile otoritatif pada spec `2026-11-02-csdm-mobile-design.md`.
