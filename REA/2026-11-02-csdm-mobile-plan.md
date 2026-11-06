# Flutter Mobile Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Flutter mobile app (M3 playback core → M4 effects → M5 polish) that plays .csdmm replay files exported by the csdm-export tool.

**Architecture:** App = models (decode .csdmm SQLite + big-endian blobs) → playback engine (currentTick + pure derive, port of desktop viewer) → CustomPainter layers (radar/players/effects) → Riverpod 3.x state → screens (pairing/QR, match list, download, viewer) following REA/viewer-mobile-ux.md (landscape-first, auto-hide chrome).

**Tech Stack:** Flutter stable ≥3.47.0 (Dart ^3.13.0), flutter_riverpod 3.4.3, sqlite3 3.8.0 (native bundled, open .csdmm read-only), dio 5.11.1 (download), bonsoir 7.1.6 (mDNS), mobile_scanner 7.5.0 (QR scan), flutter_lints 6.0.0. No state management beyond Riverpod.

**Spec:** `REA/2026-11-02-csdm-mobile-design.md` (§3 format, §5 app) + `REA/viewer-mobile-ux.md` (UX authority) + `REA/viewer-2d-audit.md` (desktop reference behaviors). This plan argues from those documents.

**Workspace:** create the Flutter project at `REA/csdm_mobile/` (separate from csdm repo code; gitignored from csdm repo like `REA/csdm-export/`).

## Global Constraints

- Blob contract (from Plan #1, authoritative): big-endian parallel arrays. Movement columns (`ticks,x,y,z,yaw,flash_duration_remaining,is_ducking,is_airborne`) index per `ticks[i]`; state columns (`state_ticks,is_alive,side,money,health,armor,has_helmet,has_bomb,has_defuse_kit,is_scoping,is_defusing,is_planting,is_grabbing_hostage`) index per `state_ticks[i]`. int32: ticks, state_ticks, side, money, health, armor. float32: x, y, z, yaw, flash_duration_remaining. uint8 bools: direct byte index `bytes[i] == 1`. String arrays: `active_weapon_name, equipments, grenades, pistols, smgs, rifles, heavy` — parallel-indexed by state index.
- `.csdmm` schema: spec §3.1 verbatim. Players table has **NO side column** (Plan #1 ruling) — derive player side from the first state blob (`side` int32 at index 0), fallback teams table order.
- Meta keys exactly: checksum/map_name/tickrate/tick_count/game/date/demo_name/duration + format_version='1' + has_positions='true'/'false'.
- `convex_hulls_2d` is a JSON array-of-strings (each string "x1,y1,x2,y2,...") — `jsonDecode` then parse each string.
- Colors verbatim: CT `#378ef0`, T `#f29423`, HE `#268e6c`, Smoke `#737373`, Flash `#f9a43f`, Molotov `#da7b11`, Decoy `#f76d74`, HP pie `#d7373f99`, inferno fill `rgba(218,123,17,0.5)` (Color(0x50DA7B11) approx → use `Color(0x50DA7B11)`).
- Interpolation (port from desktop, REA/viewer-2d-audit.md §5): linear position; circular yaw `((to - from) % 360 + 540) % 360 - 180`; state = step (last index at-or-before tick, binary search O(log n)); clamp: gap > tickrate → hold last sample; flash linear.
- Playback: init tick = round.freeze_time_end_tick; advance `ticksToAdvance = floor(elapsed/1000 * tickrate * speed)` with fractional residual carried; speed 0.5×–4×.
- Radar transform: `x' = (x - posX) / scale * imageSize / radarSize`, `y' = (posY - y) / scale * imageSize / radarSize` (Y flipped); lower level when `z < threshold_z`.
- UX authority = `REA/viewer-mobile-ux.md`: landscape-first no-lock + rotate banner, non-viewer screens portrait; playback bar 64dp/70% bottom; rounds rail left 56dp; teams panel right 180–220dp collapsible; kill feed top-right ≤45% width max 4 rows, 5s game-time; timer pill top-center always visible; pan/pinch clamp 0.1×–5× zoom-at-touch; tap player focus; fine-scrub drag-up 4× damp; names only >2× zoom, HP pie always, tap-reveal; 16ms budget.
- Strict analysis: `flutter analyze` clean (flutter_lints 6.0.0), no `dynamic` unless SDK-typed.
- Package versions pinned per librarian research (Nov 2025): sqlite3 ^3.8.0, flutter_riverpod ^3.4.3, dio ^5.11.1, bonsoir ^7.1.6, mobile_scanner ^7.5.0. Do not add packages not in this plan without a ledger ruling.
- Tests import `package:flutter_test/flutter_test.dart`; pure-Dart logic tests run on VM without widgets.
- Every task: `flutter test` + `flutter analyze` green before commit; commit messages `feat(app): ...` / `fix(app): ...` / `test(app): ...`.
- Assets: radar PNGs copied from csdm `static/images/maps/cs2/radars/*.png` (51 CS2 maps) + `maps.json` generated from `src/node/database/maps/default-maps.ts` (fields: name, game, position_x, position_y, scale, threshold_z).

## Review Focus

1. **Blob decode fidelity** — a 1-byte Endian mistake silently renders players at wrong positions; decode tests must pin exact values from synthetic blobs (int32/float32/uint8/strings) against hand-computed expectations.
2. **Yaw interpolation wrap** — crossing 359→1 must interpolate +2°, not −358°; test the circular formula directly.
3. **State clamp when player dies** — gap > tickrate must hold last sample (not extrapolate through death); test with synthetic gap.
4. **Side derivation without players.side column** — first state blob side index 0; a match where a player never appears in positions must not crash.
5. **File ingestion errors** — corrupt/truncated .csdmm, wrong format_version, missing map asset → user-facing error, not crash.
6. **Orientation race on iOS** — push viewer → pop rapidly must not leave portrait locked on next push (known engine issue; test both platforms manually in M5).

---

### Task 1: Project scaffold + .csdmm decoder (pure Dart)

**Files:**
- Create: `REA/csdm_mobile/` via `flutter create --project-name csdm_mobile` then strip counterexample counter.
- Create: `lib/models/packed_timeline.dart` — PackedTimeline decode from BLOBs.
- Create: `lib/models/csdmm_database.dart` — openDatabase(path) + typed queries (meta, players, rounds, kills, grenades, infernos, events, map_transform).
- Create: `test/packed_timeline_test.dart`, `test/csdmm_database_test.dart` (uses a fixture .csdmm generated in test setup with package:sqlite3 writing, mirroring csdm-export test values).
- Create: `lib/models/map_params.dart` — loads `assets/maps.json` (name→transform).

**Interfaces:**
- Consumes: .csdmm schema §3.1; blob contract above.
- Produces:
  - `class PackedTimeline` — constructors `PackedTimeline.decodeMovements({ticks,x,y,z,yaw,flashDurationRemaining,isDucking,isAirborne})`, `PackedTimeline.decodeStates({...})`; exposes flat `Float32List xPos/yPos/zPos/yaw/flash`, `Int32List ticks`, `Uint8List isDucking/isAirborne/isAlive/...`, `List<String> activeWeapon[]` etc., `int movementCount/stateCount`.
  - `class CsdmmDatabase` — `CsdmmDatabase.open(String path)`, `Map<String,String> getMeta()`, `List<PlayerRow> getPlayers()`, `List<RoundRow> getRounds()`, `Map<int, List<PlayerPositionRow>> getPositions()`, `List<KillRow> getKills()`, grenade/inferno/event getters; `void close()`.
  - `MatchData` aggregate: meta + players + rounds + positions + kills + effects, built by `MatchData.load(path)`.
  - `MapParams.forMap(String name)` → `{posX, posY, scale, thresholdZ}` or null.

- [x] **Step 1: scaffold** — `flutter create --project-name csdm_mobile .` in REA/csdm_mobile; add deps to pubspec (versions above); add assets maps.json + radars dir placeholder; `flutter analyze` green; commit `chore(app): scaffold flutter project`.
- [x] **Step 2: failing decoder tests** — synthetic blobs built with `ByteData` writes (Endian.big): ticks [100,200], x [-500.5,600.25], yaw [90,359.5], is_ducking [1,0]; state: state_ticks [100], side [2], money [4000], health [100]; strings ["weapon_ak47","weapon_knife"]. Test exact reads back. Also test count mismatch (ticks.len != x.len) throws FormatException.
- [x] **Step 3: run** — `flutter test test/packed_timeline_test.dart` FAIL (class missing).
- [x] **Step 4: implement PackedTimeline** — `ByteData.sublistView`, loops filling flat typed lists; no per-tick objects.
- [x] **Step 5: failing CsdmmDatabase tests** — build fixture .csdmm in setUpAll via sqlite3 writes (CREATE TABLE per §3.1, insert meta/players/rounds/one player_positions row with the synthetic blobs); test getMeta map keys exact, players rows, positions decode round-trip.
- [x] **Step 6: run all** — `flutter test` PASS; `flutter analyze` clean.
- [x] **Step 7: commit** `feat(app): csdmm decoder and typed database access`.

### Task 2: Interpolation + playback math (pure Dart)

**Files:**
- Create: `lib/playback/positions_at_tick.dart`.
- Create: `lib/playback/playback_clock.dart`.
- Test: `test/positions_at_tick_test.dart`, `test/playback_clock_test.dart`.

**Interfaces:**
- Consumes: PackedTimeline (T1).
- Produces:
  - `class RoundTimeline` — built from per-player movements+states; `PlayerAtTick? playerAt(String steamId, int tick)` → {x,y,yaw,flash,ducking,airborne,state:StateAtTick?} or null when absent/dead-clamped.
  - `int findLastIndexAtOrBefore(Int32List ticks, int tick)` — binary search, returns -1 when before first.
  - `double interpolateYaw(double from, double to, double t)` — circular.
  - `class PlaybackClock` — `PlaybackClock(tickrate)`, `void reset(int tick)`, `int advance(int elapsedMs, double speed)` returns new currentTick (residual carried internally), `double get residual`.
- [x] **Step 1: failing tests** — linear position midpoints; yaw 90→270 mid = 180; yaw 350→10 mid = 0 (wraps +20 not −340); state step returns last state at-or-before; clamp: gap 200 ticks @tickrate 64 holds last sample; dead player (positions end at tick 500, query 600) → null (positions ended) vs gap-inside (hole) → hold; clock: advance(500ms, 1.0, tickrate 64) = +32 ticks; residual carry: advance(50,1.0)=3 ticks, residual 0.2; speed 2.0 doubles.
- [x] **Step 2: run** FAIL → **Step 3: implement** → **Step 4: all pass + analyze** → **Step 5: commit** `feat(app): playback interpolation and clock`.

### Task 3: Radar asset + transform + painters (radar + players)

**Files:**
- Create: `assets/maps.json` (script: generate from csdm default-maps.ts — task does a one-off `node -e` transform; commit output).
- Create: `assets/radars/` (copy 51 CS2 PNGs from csdm repo static/images/maps/cs2/radars/).
- Create: `lib/render/map_params.dart` (asset loader), `lib/render/radar_painter.dart`, `lib/render/players_painter.dart`, `lib/render/view_transform.dart`.
- Test: `test/view_transform_test.dart`, `test/players_painter_golden.dart`.

**Interfaces:**
- Consumes: PackedTimeline/RoundTimeline (T2), MapParams, colors.
- Produces:
  - `class ViewTransform` — holds worldOrigin (Offset), scale, radarSize; `Offset worldToRadar(double x, double y)` (formula above); `Offset worldToScreen(Offset world)`; `Offset screenToWorld(Offset screen)`; zoom clamp 0.1–5.
  - `RadarPainter({required ui.Image radar, required ViewTransform})` — draws full radar; `shouldRepaint` on transform identity.
  - `PlayersPainter({required RoundTimeline timeline, required int tick, required ViewTransform vt, required double zoom, required Set<String> focusedIds})` — circle r8 team color, HP pie (state), yaw line, names when zoom>2 (cached TextPainter), HP pie always; kills X at death positions.
  - Player side → color: derive from first state (side 3=CT #378ef0, 2=T #f29423).
- [x] **Step 1: transform unit tests** — de_mirage params from maps.json: known world point → expected pixel (hand-computed); Y-flip assertion; screenToWorld inverse round-trip; clamp bounds.
- [x] **Step 2: implement transform** → pass.
- [x] **Step 3: golden test** — synthetic 2 players + 1 kill frame at fixed transform, `matchesGoldenFile('goldens/players_frame.png')`; run `--update-goldens` once to seed.
- [x] **Step 4: implement painters** → golden passes; analyze clean.
- [x] **Step 5: commit** `feat(app): radar transform and player painters`.

### Task 4: Playback controller + viewer screen core (landscape)

**Files:**
- Create: `lib/playback/playback_controller.dart` (Riverpod Notifier: currentTick, playing, speed, roundIndex; Ticker in provider).
- Create: `lib/ui/viewer/viewer_screen.dart` — Stack: InteractiveViewer-replacement custom gesture layer + painters + minimal chrome (timer pill, playback bar 64dp, rounds rail 56dp).
- Create: `lib/ui/viewer/gestures.dart` — pan/pinch/tap detection; zoom-at-touch.
- Test: `test/playback_controller_test.dart` (pure logic: tick advance end-round stop, round switch resets to freeze_time_end_tick), widget test `test/viewer_screen_test.dart` (pump with fixture MatchData, seek bar renders, tap play toggles icon).

**Interfaces:**
- Consumes: T1–T3.
- Produces: `PlaybackController` Notifier (`tick`, `isPlaying`, `speed`, `selectRound(int)`, `toggle()`, `seekToPercent(double)`, `tickAt(int deltaMs)`), `viewerProvider` family by checksum.
- [x] **Step 1: controller tests** FAIL → implement → pass (ticker fake-async).
- [x] **Step 2: widget test** — viewer renders radar+players from fixture; scrub to 50% sets tick ≈ mid.
- [x] **Step 3: implement screen** — UX: auto-hide chrome after 3s playback (tap canvas toggles), timer pill `(endOfficiallyTick - tick)/tickrate` top-center always visible.
- [x] **Step 4: analyze + tests green → commit** `feat(app): viewer screen with playback core`.

### Task 5: Transfer — pairing + mDNS + download + cache

**Files:**
- Create: `lib/transfer/discovery.dart` (bonsoir browse `_csdmm._tcp`), `lib/transfer/pairing.dart` (parse `http://ip:port/#/token` from mobile_scanner; store last host+token in SharedPreferences-free plain file `csdm_mobile pairing.json` in app docs dir — no new dep), `lib/transfer/downloader.dart` (dio download to `<docs>/{checksum}.csdmm.part` → rename), `lib/transfer/library.dart` (list cached matches by scanning docs dir, open CsdmmDatabase read-only).
- Create: `lib/ui/pairing_screen.dart` (QR scan + manual IP fallback), `lib/ui/matches_screen.dart` (list from /api/matches, download button + progress, cached section), portrait-locked.
- Modify: `lib/main.dart` — routes: Matches → Viewer (landscape-first on push, restore on pop with banner).
- Test: unit tests with dio MockAdapter: download progress + .part rename + cancel; pairing URL parse (invalid URL, missing fragment). Widget test: matches screen renders fixture JSON.

**Interfaces:**
- Consumes: server API GET /api/matches + /export (bearer token).
- Produces: `PairingInfo{baseUrl, token}`, `Downloader.downloadMatch(PairingInfo, checksum, onProgress)`, `Library.listCached()/pathFor(checksum)`.
- [x] **Step 1: failing unit tests** → implement → pass (mockdio or manual adapter).
- [x] **Step 2: screens minimal but UX-compliant** (portrait lock via SystemChrome in initState/dispose).
- [x] **Step 3: analyze + tests → commit** `feat(app): pairing discovery download and library`.

### Task 6: Effects painters — grenades, infernos, shots, kill feed, bomb

**Files:**
- Create: `lib/render/effects_painter.dart` (grenade paths colored per type + smoke ring countdown r26 + HE/flash fade circle 1s + inferno hull fill + shot lines anim len 80 + death X).
- Create: `lib/ui/viewer/kill_feed.dart` (top-right, max 4 rows, 5s game-time window, weapon icon text fallback).
- Modify: viewer_screen stacks effects below players layer; playback bar markers (kills, plant, freezetime end).
- Test: `test/effects_painter_golden.dart` (synthetic grenade path + inferno hull + kill, two goldens: t=event, t=event+1s), `test/kill_feed_test.dart` (window filter, max rows).

**Interfaces:**
- Consumes: KillRow, grenade rows (ticks/x/y/z blobs → PackedTimeline-like), events; colors constraint.
- Produces: `EffectsPainter({grenades, infernos, kills, events, tick, vt, zoom})`.
- [x] **Step 1: golden seeds** → implement → goldens pass at t and t+1s (fade verified).
- [x] **Step 2: kill feed widget test** → pass.
- [x] **Step 3: analyze + commit** `feat(app): effects layer and kill feed`.

### Task 7: UX completion — teams panel, rounds rail full, fine-scrub, labels

**Files:**
- Modify: `viewer_screen.dart` + create `lib/ui/viewer/teams_panel.dart` (right 180–220dp collapsible, tap card expands), `lib/ui/viewer/rounds_rail.dart` (chips + winner dot), `lib/ui/viewer/scrub_gesture.dart` (bar hit-test + drag-up 4× damp fine-scrub), tap-reveal names.
- Test: widget tests — teams panel collapse toggle; rounds rail selects round (controller reset to freeze tick); fine-scrub: drag up 100px → tick delta ≈ raw/4; scrub-vs-pan isolation (drag starting on bar never pans canvas).

**Interfaces:**
- Consumes: controller (T4), RoundRow (winner_side for dot).
- Produces: complete viewer per UX doc.
- [x] **Step 1: widget tests FAIL** → **Step 2: implement** → **Step 3: pass + analyze** → **Step 4: golden refresh if paint changed** → **Step 5: commit** `feat(app): full viewer chrome per ux spec`.

### Task 8: Resilience + orientation + errors

**Files:**
- Modify: `csdmm_database.dart` (format_version check → CsdmmFormatException), `viewer_screen.dart` (unknown map → unsupported screen), `main.dart` (global error widget).
- Create: `lib/ui/unsupported_map_screen.dart`, `lib/models/format_exception.dart`.
- Test: corrupt file (truncated bytes) throws CsdmmFormatException; wrong format_version throws; missing map asset routes to unsupported screen (widget test); orientation test: push viewer sets landscape preferred, pop restores (mock SystemChrome via TestDefaultBinaryMessenger).

**Interfaces:**
- Produces: `CsdmmFormatException(String reason)`; route `/unsupported-map`.
- [x] Steps: tests FAIL → implement → pass → commit `feat(app): error handling and orientation management`.

### Task 9: Performance hardening (16ms budget)

**Files:**
- Modify: painters — pre-cache TextPainter names per player (Map<steamId,TextPainter>), RepaintBoundary wraps, shots cap <1× zoom (skip when zoom<1 per UX), decode positions in `Isolate.run` at load (T1 already pure; wrap MatchData.load decode in isolate).
- Test: `test/decode_isolate_test.dart` (load 100k-sample synthetic blobs completes without UI jank in fake async — assert completion + result equality); painter test asserts names cache reused (identity check).
- [x] Steps: tests → implement → pass → commit `perf(app): decode in isolate and cached text painters`.

### Task 10: E2E manual verification harness + polish

**Files:**
- Create: `tool/gen_fixture_csdmm.dart` (Dart CLI: writes fixture .csdmm mirroring csdm-export fixture values — same synthetic blobs — so device testing has deterministic data).
- Create: `README.md` (ID: run steps, pairing flow, asset regeneration command).
- Modify: app icon/name placeholder (M5-lite; store release out of scope).
- [x] Step 1: gen fixture runs → produces valid file (round-trip via CsdmmDatabase test).
- [ ] Step 2: manual checklist in README (scan QR from real csdm-export serve; play 1 round; scrub; kill feed; grenade; rotate).
- [x] Step 3: full `flutter test` + `flutter analyze` → commit `feat(app): fixture generator and readme`.
