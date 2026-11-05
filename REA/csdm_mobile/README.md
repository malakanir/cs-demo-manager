# csdm_mobile

Flutter app that plays `.csdmm` replay files exported by `REA/csdm-export`
(2D round viewer, landscape-first). Specs: `REA/2026-11-02-csdm-mobile-design.md`,
`REA/viewer-mobile-ux.md`.

## Run

```bash
flutter pub get
flutter run            # pick a device/emulator
flutter test
flutter analyze
```

Requires Flutter >= 3.47 (Dart ^3.13).

## Pairing flow

1. On the desktop, run the export server from `REA/csdm-export`:
   `npm run cli -- serve` — it prints a QR code (`http://<lan-ip>:7323/#/<token>`).
2. In the app, open **Matches** → scan icon → scan the QR (or paste the URL).
3. The match list loads from the desktop. Tap the download icon; the file is
   stored in the app documents folder, then tap it to open the viewer.

The token changes every time `serve` restarts, so re-pair after a restart.
Phone and laptop must be on the same LAN.

## Test data without a csdm database

```bash
dart run tool/gen_fixture_csdmm.dart ./out
```

Writes the deterministic fixture match (`de_mirage`, 2 rounds, 2 players) used by
the unit tests. The app only lists files in its own documents folder
(`matches/`), which is private on a phone, so copying it there works on a
desktop/emulator build (e.g. `flutter run -d linux`) or via `adb run-as`; on a
real phone use pairing instead.

## Regenerating assets

`assets/maps.json` comes from csdm's map table (CS2 maps only). Radar PNGs are
copied from `static/images/maps/cs2/radars/` in the csdm repo into
`assets/radars/cs2/`. From this folder:

```bash
node tool/gen_maps.mjs ../../src/node/database/maps/default-maps.ts > assets/maps.json
cp ../../static/images/maps/cs2/radars/*.png assets/radars/cs2/
```

## Manual device checklist

- [ ] Scan the QR from a real `csdm-export serve`; the match list appears.
- [ ] Download a match; progress shows and it moves to **Downloaded**.
- [ ] Open it: viewer is landscape; players, radar and timer pill render.
- [ ] Play one round at 1×; scrub the bar; drag the finger up and confirm fine scrub is slower.
- [ ] A kill shows in the kill feed (about 5 s) and leaves an X on the map.
- [ ] A grenade shows its path, smoke ring / burst / fire.
- [ ] Pinch zoom and pan; names appear above 2× zoom; tap a player to focus it.
- [ ] Teams panel collapses and expands; tapping a card lists players.
- [ ] Back to the match list returns to portrait. Repeat push/pop quickly on iOS and Android.
- [ ] A match on a map without a radar shows the unsupported-map screen.
- [ ] A truncated `.csdmm` shows an error message instead of crashing.

## Not done (out of scope)

App icon and store release. App name is a placeholder (`CS2 Replays`).
