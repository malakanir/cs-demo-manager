# Security Audit — cs-demo-manager

Tanggal: 2026-11-02. Metode: static review source (3 lane paralel: IPC/main, supply-chain/network, exec pipeline). Repo: open source MIT, source = ground truth.

## Ringkasan

| Severity | Count |
|---|---|
| HIGH | 4 |
| MEDIUM | 4 |
| LOW | 7 |
| INFO | 1 (bersih: embedded PostgreSQL, SQL/Kysely, path handling) |

Model ancaman utama: (1) serangan dari LAN lokal — WS server tidak ter-autentikasi dan bind semua interface; (2) kompromi renderer (XSS) yang bereskalasi ke full-Node via preload unsandboxed; (3) supply-chain pada tool biner yang diunduh saat runtime.

## HIGH

1. **WS server bind semua interface** — `src/server/server.ts:77-80`. `new WSServer({ port })` tanpa opsi `host` → `0.0.0.0`/`::`. Daemon kontrol (analisis demo, video, jalankan CS) reachable dari LAN.
2. **WS tanpa autentikasi** — `src/server/server.ts:222-269`. Role client deklarasikan sendiri via `?process=main|renderer|cli|game`. Tanpa token, tanpa `verifyClient`, tanpa cek origin. Client remote bisa klaim `renderer` dan memanggil ~120 handler.
3. **Arbitrary file write** — `src/server/handlers/renderer-process/filesystem/write-base64-file-handler.ts:8`. `writeBase64File(filePath, data)` path & isi dari renderer, tanpa allowlist. Overwrite file mana pun yang bisa ditulis user daemon (autostart, dotfiles, config).
4. **Command injection — keluarga `exec()` string-concat (satu kelas bug)** — `exec()` shell string, bukan argv array. Sanitasi yang ada (`assert-demo-path-is-valid.ts` blok `&;@^`) loloskan `"` `` ` `` `$` `%` → `$(cmd)` jalan di `/bin/sh` (Unix), `%VAR%`/`&` di CS2 Windows:
   - `start-counter-strike.ts:165,169-172,242,265` — `demoPath` + `userLaunchParameters` via `+playdemo "${demoPath}"`.
   - `start-counter-strike-with-hlae.ts:227-229,232` — pola sama.
   - `src/node/video/ffmpeg/execute-ffmpeg.ts:13` — `exec("ffmpeg" ${args.join(' ')})`; caller sisipkan `outputFolderPath`, `inputParameters`, `outputParameters` (`generate-video-with-ffmpeg.ts:118,140,165,182`; `concatenate-videos-from-sequences.ts:20-29`).
   - `src/node/csgo-voice-extractor/start-csgo-voice-extractor.ts:38` — `demoPath`, `outputFolderPath`, `-steam-ids` terinterpolasi.
   - `generate-video-with-virtual-dub.ts:41-65,110` — `"` di path merusak/menyuntik `.jobs` (exec konstanta, dampak rendah tapi pola sama).

## MEDIUM

1. **`shell.openPath`/`showItemInFolder` path tidak divalidasi** — `src/electron-main/register-main-process-listeners.ts:16,28`. `openPath` pada executable/bat = eksekusi via handler OS default.
2. **Preload mengekspos FS sensitif** — `src/preload/preload.ts:105,116,124-132`: `parseSettingsFile` (mengandung DB password `settings.ts:26`, `faceitApiKey:193`), `writeJsonFile` (write path bebas), `pathExists`, `readImageFile` (read bebas). XSS renderer = curi secret + tulis file tanpa lewat IPC.
3. **`sandbox: false`** — `src/electron-main/window-manager.ts:85`. Preload jalan full Node (`fs-extra` di `preload.ts:12`). Renderer escape = full node context.
4. **Bundled native binaries tanpa reproducible build** — `scripts/install-deps.mjs:16-66`. `csda`, `csgove`, `boiler-writter` disalin verbatim dari `node_modules/@akiver/*/dist/bin`. Trust = 3 paket npm satu author.

## LOW

1. **webSecurity inverted** — `window-manager.ts:87`: `webSecurity: IS_PRODUCTION` (nonaktif saat dev). Dev-only, tapi tetap weakening.
2. **Allowlist `openExternal` prefix-match** — `window-manager.ts:171-173`: `url.startsWith(website)`; `https://github.com/` mengizinkan user-content/raw gist path apa pun.
3. **`execAsync` tar tanpa quote + tar-slip** — `src/node/filesystem/download-and-extract-xz-archive.ts:30`: `tar -xJf ${archivePath} -C ${destinationPath} --strip=1` — tanpa quoting; member tar diekstrak tanpa sanitasi → path traversal jika upstream terkompromi; `--strip=1` asumsi layout.
4. **ZIP diekstrak tanpa validasi + biner tak bertanda tangan dieksekusi** — `download-and-extract-zip-archive.ts:25`: `zip.extract(null, ...)` tanpa cek entry-name; sumber HLAE = `release.assets[].browser_download_url` tanpa checksum.
5. **Arbitrary delete via renderer** — `src/node/counter-strike/json-actions-file/delete-json-actions-file.ts:4`: `fs.remove(\`${demoPath}.json\`)`, `demoPath` dari WS payload — gabungan HIGH #1 = delete file dari LAN.
6. **ShutdownDaemon + GetDatabaseConnectionSettings (kredensial DB) bisa dipanggil probe tanpa auth** — `src/server/handlers/cli-handlers-mapping.ts:66-67`.
7. **Setelan pengguna jadi bagian command line** — `playback.launchParameters`, `video.hlae.parameters`, `ffmpegSettings.input/outputParameters`, `cs2SteamRuntimeScriptPath` masuk verbatim ke perintah exec; fitur lokal, tapi bisa diatur remote via WS `UpdateSettings` (rantai HIGH #1).

## Supply chain / unduhan biner (runtime)

- **Tanpa checksum/signature di semua download tool**: `src/node/filesystem/download-and-extract-zip-archive.ts:7`, `download-and-extract-xz-archive.ts:8`; FFmpeg `src/node/video/ffmpeg/install-ffmpeg.ts:32` (BtbN latest, moving target); HLAE `src/node/video/hlae/download-hlae.ts:9-21` (`release.assets[0]` buta dari latest release → dieksekusi); VirtualDub `src/node/video/virtual-dub/download-and-extract-virtual-dub.ts:17` (hardcoded mirror SourceForge); embedded PostgreSQL `scripts/install-deps.mjs:299` (raw fetch npm, termitigasi versi pin + provenance).
- `get-steam-api-key.ts:12-13` crash jika `STEAM_API_KEYS` unset (dev-only).
- `scripts/build.mjs`: `STEAM_API_KEYS`/`FACEIT_API_KEY` di-inline ke `out/server.js` saat build — bisa terekam dari bundle jika builder `.env` terisi.

## Endpoint eksternal

| Tujuan | Endpoint |
|---|---|
| Download biner (tanpa verifikasi) | `github.com/BtbN/FFmpeg-Builds`, `evermeet.cx`, `api.github.com`, `freefr.dl.sourceforge.net`, `registry.npmjs.org` |
| Data match | `api.steampowered.com` (API key user di query URL), `replay*.valve.net`, `open.faceit.com`, `gate.5eplay.com`, `oss-arena.5eplay.com`, `api.renown.gg` |
| IPC lokal | `ws://localhost:<port>` (lihat HIGH #1: sebenarnya bind semua interface) |
| Build-time | `crowdin.com` (token via env, tidak ikut repo — bersih) |
| Telemetry/update | **Tidak ada.** Bersih. |

## Prioritas perbaikan

1. `WSServer({ port, host: 'localhost' })` + shared-secret handshake.
2. Validasi path `writeBase64File` (allowlist direktori demo/output).
3. `execFile` argv array untuk launch CS & `tar`, bukan `exec` string.
4. Pin checksum FFmpeg/HLAE/VirtualDub (atau vendor seperti `csda`).
5. `sandbox: true` bila memungkinkan; minimal pantulkan path di handler `shell.openPath`.

## Catatan RE

App ini open source — audit di atas cukup; tidak perlu RE biner. RE dengan REA relevan hanya untuk memverifikasi build release = source (audit `resources/app.asar` hasil `vp run package`).
