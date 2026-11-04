# Audit 2D Viewer cs-demo-manager (dasar porting Flutter)

Sumber: audit gen-4, 2026-11-02. Pelengkap: `REA/viewer-db-schema.md` (skema), `REA/mobile-feasibility.md` (arsitektur mobile).

## 1. Lokasi fitur

| Bagian | Path |
|---|---|
| Komponen viewer (59 file) | `src/ui/match/viewer-2d/` |
| Loader + fetch | `viewer-2d-loader.tsx` |
| State playback | `viewer-context.tsx` |
| Loop render canvas | `viewer-2d.tsx` |
| Pan/zoom/transform | `src/ui/hooks/use-interactive-map-canvas.ts` |
| Sub-folder | `audio/`, `drawing/`, `playback-bar/` (18 file), `rounds-bar/`, `teams-panel/` |
| Redux persist (speed, volume, fokus, audio offset) | `viewer-2d-reducer.ts`, `viewer-actions.ts` |

Tidak ada Web Worker / ECharts / SVG — **HTML Canvas 2D murni + requestAnimationFrame**.

## 2. Aliran data

1. Fetch **per ronde** via WS: pesan `'fetch-2d-viewer-data'` → handler `src/server/handlers/renderer-process/match/fetch-2d-viewer-data-handler.ts:72-153` (terdaftar `renderer-handlers-mapping.ts:246,375`). Payload request: `{ checksum, roundNumber, demoFilePath, tickrate }`.
2. Respons: **satu JSON besar berisi SEMUA data 1 ronde sekaligus** (20 query paralel `Promise.all`, line 100-124) — bukan streaming tick.
3. Payload sukses (verbatim `:42-70`): `playerTimelines`, `kills`, `round`, `shots`, `grenadeTimelines`, `infernoTimelines`, `hostagesPickUpStart/PickedUp`, `hostageTimelines`, `chickenTimelines`, bomb events (`bombExploded/Planted/Defused`, `bombsDefuseStart`, `bombsPlantStart`), `heGrenadesExplode`, `flashbangsExplode`, `decoysStart`, `smokesStart`, `audioFilePath`.
4. Audio (opsional): file wav/mp3 sebelah demo, diakses preload `window.csdm.getDemoAudioData` (`src/preload/get-demo-audio-data.ts:14`); offset persist localStorage `2d-audio-offset-{checksum}`.
5. Peta: `maps` DB → `fetch-maps.ts` → `map-row-to-map.ts` (resolve path PNG radar dari filesystem). Tanpa radar → layar "Unsupported map" (`viewer-2d-loader.tsx:231-233`).
6. Match tanpa posisi: `no-positions-found.tsx` → pesan `GenerateMatchPositions` → `generate-match-positions.ts` → analyzer `csda` `analyzePositions:true` → `insert-match-positions.ts` (COPY CSV).

## 3. Format data (ringkas; tipe lengkap di `src/common/types/`)

- `PlayerMovement`: `{ tick, playerSteamId, playerName, x, y, z, yaw, flashDurationRemaining, isDucking, isAirborne }` — **direkam per tick, tapi di-downsample server-side ke 16 Hz** (`sample-player-movements.ts`, `samplesPerSecond=16` line 16; sampel sekitar perubahan state selalu dipertahankan).
- `PlayerState` (delta, hanya saat berubah): alive, side, money, health, armor, helmet, bomb, defuse kit, scoping, defusing, planting, hostage, `activeWeaponName`, inventaris (`equipments/grenades/pistols/smgs/rifles/heavy`).
- `PlayerTimeline = { movements: PlayerMovement[], states: PlayerState[] }` — keduanya sorted by tick.
- `GrenadeTimeline`: id, nama, thrower*, velocity/yaw/pitch thrower, `positions: TimelinePosition[]` (hanya saat bergerak; titik terakhir = proyektil hilang).
- `InfernoTimeline`: convex hull 2D per tick (`points: number[]` "x1,y1,x2,y2...").
- `Kill`, `Shot`: event relasional (lihat `viewer-db-schema.md` §3/§4); `Shot` punya `playerYaw`/`playerPitch` = arah tembakan.
- Unit: koordinat = unit dunia Source (~0.019 m), yaw derajat (0 = +x, CW positif, digambar `angle = -yaw`), tick int, tickrate 64/128.

## 4. Rendering (urutan layer per frame rAF)

1. Radar bawah (alpha+offset) + radar atas — `drawing/use-draw-map-radar.ts:30-60`
2. Pemain — `use-draw-players.ts`: lingkaran r8 warna tim (CT `#378ef0`, T `#f29423`), pie HP merah `#d7373f99` (r7, proporsional), garis yaw putih (panjang +6 saat scoping; segitiga utk knife/grenade), ikon bom SVG 14px, nama font 10 offset 20, arc flash putih (`flashDurationRemaining / 5.25`), arc defuse hijau (5 dtk kit/10 tanpa), plant merah (3.2 dtk), pickup hostage oranye.
3. Hostage (lingkaran coklat r8/4), tembakan (`use-draw-shots.ts`: garis animasi panjang 80, `time += 0.1`/frame, warna tim), inferno (hull fill `rgba(218,123,17,0.5)`), grenade (jalur + lingkaran r4; warna: HE `#268e6c`, Smoke `#737373`, Flash `#f9a43f`, Molotov `#da7b11`, Decoy `#f76d74`; smoke meledak = lingkaran abu r26 + countdown; HE/flash = lingkaran fade 1 dtk), silang kematian X 10px alpha `7f`, bom (pra-plant = posisi carrier terakhir; post-plant ikon 22px/60px saat ledak), ayam (SVG 20px), stroke gambar.
4. Overlay React (bukan canvas): timer `(endOfficiallyTick - currentTick)/tickrate`, kill feed tampil 5 dtk game-time (`motion/react`), panel tim (klik = fokus), rounds bar, playback bar.

## 5. Playback engine

- State tunggal: `currentTick` (init `freezetimeEndTick`), `viewer-context.tsx:170`.
- Advancement via rAF (`viewer-2d.tsx:106-112`): `ticksToAdvance = floor(elapsed/1000 * tickrate * speed)`; residual dihitung agar presisi.
- Akhir ronde: auto-next ronde / pause di akhir.
- Speed 0.5×–4× step 0.5 (Redux persist); audio `playbackRate` ikut.
- Scrub timeline: `newTick = floor(percent * (endOfficiallyTick - startTick)/100 + startTick)`; penanda: kill, freezetime end, bomb planted/exploded.
- Audio sync: `currentTime = tick/tickrate + offset`.
- **Interpolasi client** (`players-timelines.ts`, verbatim di laporan sumber): posisi linear, **yaw circular** (`((to-from)%360+540)%360-180`), flash duration linear; state = step (`findLastIndexAtOrBeforeTick`); **clamp: gap > tickrate (1 dtk) → hold sampel sebelumnya** (pemain mati/putus). `maxInterpolationTickCount = tickrate` (`viewer-context.tsx:187`).
- Bomb carrier: walk movements×states kumpulkan posisi saat `hasBomb` (`players-timelines.ts:94-111`).
- Keyboard: Space play/pause, D/Esc mode gambar, Ctrl+Z/Y undo/redo stroke, Ctrl+X clear.

## 6. Pan/Zoom (`use-interactive-map-canvas.ts`)

- Kanvas = wrapper × devicePixelRatio; `scale = clientHeight/dpr / radarSize`; center via screenOrigin.
- Wheel zoom di kursor, multiplier `1 - sign(delta)*min(0.25, |delta/128|)`, clamp **0.1×–5×**.
- Pan drag menggeser worldOrigin; semua zoom state di `useRef` (tanpa re-render React).

## 7. Peta & transformasi koordinat (VERBATIM)

- 62 peta default: `src/node/database/maps/default-maps.ts` (posX/posY/scale/thresholdZ per peta).
- Radar PNG: `static/images/maps/{cs2,csgo}/radars/{mapName}.png` (51 CS2 + 21 `_lower.png` + 21 CS:GO); runtime folder via `get-maps-radars-folder-path.ts`; override user `{appData}/images/maps/{game}/radars/` diprioritaskan (`get-map-radar-file-path.ts:24-31`).
- `radarSize` 1024/2048 dibaca dari lebar PNG aktual (`map-row-to-map.ts:11-15`).

```ts
// get-scaled-coordinate-x.ts
const xForDefaultRadarWidth = (xFromDemo - map.posX) / map.scale;
const scaledX = (xForDefaultRadarWidth * imageSize) / map.radarSize;

// get-scaled-coordinate-y.ts  — Y DIBALIK
const yForDefaultRadarHeight = (map.posY - yFromDemo) / map.scale;
const scaledY = (yForDefaultRadarHeight * imageSize) / map.radarSize;
```

- Level bawah dipilih per-entitas: `z < map.thresholdZ`; offset X/Y radar bawah = preferensi user (persist localStorage).
- World→screen: `zoomedX = (x - worldOriginX)*scale + screenOriginX` (idem Y); `zoomedSize = floor(size * scale * (radarSize/1024))`.
- Inverse (screen→world, `:95-100`): `(px - screenOriginPixelX)/scale + worldOriginX`.

## 8. Performa (pola yang dipakai)

Downsample 16 Hz server-side; packing `bytea` big-endian; binary search `find-last-index-at-or-before-tick.ts` O(log n); satu loop rAF imperatif; zoom state di ref tanpa re-render; fetch per-ronde; kill filter `shot.tick === currentTick`. Tidak ada worker/streaming — **semua data 1 ronde dimuat sekaligus**.

## 9. Catatan porting Flutter

1. Kontrak data JSON (camelCase) siap pakai → bentuk class Dart.
2. Playback = derive murni dari `currentTick` + `positionsAtTick()` — port `players-timelines.ts` = seluruh engine (interpolasi linear + yaw circular + clamp 1 dtk + state step).
3. Aset radar PNG + parameter `default-maps.ts` harus diekspor/bundled ke app.
4. Radar ganda (atas/bawah via `thresholdZ`) opsional di mobile v1.
5. Semua animasi efek = fungsi `(currentTick - eventTick)/tickrate` → langsung ke `Ticker` Flutter.
6. **Keputusan user: ekspor raw per-tick** (tanpa sampling 16 Hz) → di Flutter tak perlu sampling; interpolasi tetap berguna untuk scrub/smooth.
