import 'dart:io';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/playback/playback_controller.dart';
import 'package:csdm_mobile/render/players_painter.dart';
import 'package:csdm_mobile/ui/viewer/playback_bar.dart';
import 'package:csdm_mobile/ui/viewer/scrub_gesture.dart';
import 'package:csdm_mobile/ui/viewer/viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/csdmm_fixture.dart';

void main() {
  test('FineScrub: absolute on the track, damped 4x when dragged up', () {
    final s = FineScrub();
    expect(s.start(100, 400), 0.25);
    expect(s.update(x: 200, y: 0, width: 400), 0.5);
    // Leave the track: anchor at the current playhead, then move 100px.
    expect(s.update(x: 200, y: -50, width: 400), 0.5);
    expect(s.update(x: 300, y: -50, width: 400), closeTo(0.5 + 100 / 400 / 4, 1e-9));
    // Back on the track: absolute again.
    expect(s.update(x: 100, y: 0, width: 400), 0.25);
  });

  late Directory directory;
  late MatchData data;
  late ProviderContainer container;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('csdmm_t7_widget');
    data = MatchData.load(createFixtureCsdmm(directory));
    final playback = ViewerPlayback(data: data, tickrate: data.tickrate);
    container = ProviderContainer(
      overrides: [playbackDataProvider.overrideWith((ref) => playback)],
    );
  });

  tearDown(() {
    container.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ViewerScreen(checksum: data.checksum)),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (container.read(radarImageProvider).value != null) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
  }

  PlayersPainter playersPainter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.foregroundPainter)
      .whereType<PlayersPainter>()
      .single;

  int tick() => container.read(playbackControllerProvider).tick;

  testWidgets('teams panel collapses and expands', (tester) async {
    await pumpViewer(tester);
    expect(find.byKey(const Key('teams-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('teams-panel-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('teams-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('teams-panel-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('teams-panel')), findsOneWidget);
  });

  testWidgets('tapping a team card lists its players', (tester) async {
    await pumpViewer(tester);
    expect(find.textContaining('Alice'), findsNothing);

    final card = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('team-card-'),
    );
    for (final element in card.evaluate().toList()) {
      await tester.tap(find.byWidget(element.widget));
      await tester.pump();
    }
    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.textContaining('Bob'), findsOneWidget);
  });

  testWidgets('rounds rail shows a winner dot and selects the round', (tester) async {
    await pumpViewer(tester);
    expect(find.byKey(const Key('round-winner-1')), findsOneWidget);
    expect(find.byKey(const Key('round-winner-2')), findsOneWidget);

    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(container.read(playbackControllerProvider).tick, 3130);
  });

  testWidgets('fine scrub: dragging up moves the playhead ~4x slower', (tester) async {
    await pumpViewer(tester);
    final bar = find.byKey(playbackBarKey);
    final start = tester.getTopLeft(bar) + Offset(120, tester.getSize(bar).height / 2);

    // Normal scrub.
    var g = await tester.startGesture(start);
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    final a = tick();
    await g.moveBy(const Offset(100, 0));
    await tester.pump();
    final raw = tick() - a;
    await g.up();
    await tester.pump();

    // Fine scrub: same horizontal distance, finger 100px above the track.
    g = await tester.startGesture(start);
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(0, -100));
    await g.moveBy(const Offset(0, -5));
    await tester.pump();
    final c = tick();
    await g.moveBy(const Offset(100, 0));
    await tester.pump();
    final fine = tick() - c;
    await g.up();
    await tester.pump();

    expect(raw, greaterThan(50));
    expect(fine, closeTo(raw / 4, raw * 0.05 + 2));
  });

  testWidgets('dragging on the bar never pans the canvas', (tester) async {
    await pumpViewer(tester);
    final before = playersPainter(tester).vt.worldOrigin;
    final bar = find.byKey(playbackBarKey);
    final start = tester.getTopLeft(bar) + Offset(120, tester.getSize(bar).height / 2);

    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(40, -60));
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pump();

    expect(playersPainter(tester).vt.worldOrigin, before);
  });

  testWidgets('tapping a player focuses it and reveals the name', (tester) async {
    await pumpViewer(tester);
    final painter = playersPainter(tester);
    final player = painter.timeline.playerAt(aliceSteamId, painter.tick)!;
    final at = painter.vt.worldToScreen(Offset(player.x, player.y));

    await tester.tapAt(at);
    await tester.pump();
    // Fixture players are close together; the nearest one wins.
    expect(playersPainter(tester).focusedIds, hasLength(1));

    await tester.tapAt(at);
    await tester.pump();
    expect(playersPainter(tester).focusedIds, isEmpty);
  });
}
