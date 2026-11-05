import 'dart:io';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/playback/playback_controller.dart';
import 'package:csdm_mobile/ui/viewer/playback_bar.dart';
import 'package:csdm_mobile/ui/viewer/viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/csdmm_fixture.dart';

void main() {
  late Directory directory;
  late MatchData data;
  late ProviderContainer container;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    directory = Directory.systemTemp.createTempSync('csdmm_t4_widget');
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

  /// Pumps the viewer and settles the async radar-image load. The image
  /// decode runs on a real event loop, so give it real time via runAsync.
  /// The playback ticker is muted while paused, so pumpAndSettle terminates.
  Future<void> pumpViewer(WidgetTester tester) async {
    // Landscape surface, like the real usage (portrait tests are T5+).
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
      // Wait until the radar image future resolves (or bail after ~2 s).
      for (var i = 0; i < 40; i++) {
        if (container.read(radarImageProvider).value != null) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('renders radar, players and chrome', (tester) async {
    await pumpViewer(tester);

    expect(find.byType(CustomPaint), findsWidgets);
    // Timer pill: (end 3010 - tick 130)/64 = 45 s -> 0:45.
    expect(find.text('0:45'), findsOneWidget);
    // Rounds rail shows both rounds.
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('tap play icon toggles playback', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('playing advances the tick through the ticker', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.byIcon(Icons.play_arrow));
    // Ticker needs a warm-up frame (first callback establishes the elapsed
    // baseline); ~100 ms of frames at 64 tick/s advances well past 130.
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(
      container.read(playbackControllerProvider).tick,
      greaterThan(130),
    );
  });

  testWidgets('dragging the scrub bar seeks the tick', (tester) async {
    await pumpViewer(tester);

    final barFinder = find.byKey(playbackBarKey);
    final barTop = tester.getTopLeft(barFinder);
    final barSize = tester.getSize(barFinder);
    // Land on the track like a real thumb: 60% across it.
    final trackX = barTop.dx + 48 + (barSize.width - 48 - 70) * 0.6;
    final gesture = await tester.startGesture(
      Offset(trackX, barTop.dy + barSize.height / 2),
    );
    // First move is consumed by the gesture arena (slop); the second
    // delivers actual drag updates.
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final tick = container.read(playbackControllerProvider).tick;
    // Drag geometry is approximate; assert the seek clearly left the
    // freeze-end region but did not hit the round end.
    expect(tick, greaterThan(1500));
    expect(tick, lessThan(3010));
  });

  testWidgets('selecting another round resets the tick', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();

    final state = container.read(playbackControllerProvider);
    expect(state.roundNumber, 2);
    expect(state.tick, 3130);
  });
}
