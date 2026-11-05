import 'dart:io';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/playback/playback_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/csdmm_fixture.dart';

/// Round 1: start 100, freeze end 130, end officially 3010, tickrate 64.
void main() {
  late String path;
  late ProviderContainer container;

  setUp(() {
    path = createFixtureCsdmm(Directory.systemTemp.createTempSync('csdmm_t4'));
    final data = MatchData.load(path);
    final playback = ViewerPlayback(data: data, tickrate: data.tickrate);
    final overrides = [
      playbackDataProvider.overrideWith((ref) => playback),
      playbackControllerProvider.overrideWith(
        PlaybackController.new,
      ),
    ];
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    addTearDown(() {
      final dir = File(path).parent;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  PlaybackController controller() =>
      container.read(playbackControllerProvider.notifier);
  PlaybackState state() => container.read(playbackControllerProvider);

  test('initial state sits at freeze_time_end_tick of round 1, paused', () {
    final s = state();
    expect(s.roundNumber, 1);
    expect(s.tick, 130);
    expect(s.isPlaying, isFalse);
    expect(s.speed, 1.0);
    expect(s.atRoundEnd, isFalse);
  });

  test('toggle starts and pauses playback', () {
    controller().toggle();
    expect(state().isPlaying, isTrue);
    controller().toggle();
    expect(state().isPlaying, isFalse);
  });

  test('tickAt advances tick by elapsed*speed*tickrate with carry', () {
    controller().toggle();
    // 1 s at 1x, 64 tick/s -> 64 ticks (130 -> 194), no residual.
    controller().tickAt(1000);
    expect(state().tick, 194);
    // 7.8125 ms = half a tick: residual is carried, tick unchanged.
    controller().tickAt(8);
    expect(state().tick, 194);
    // Another half tick completes it.
    controller().tickAt(8);
    expect(state().tick, 195);
  });

  test('pause stops the tick', () {
    controller().toggle();
    controller().tickAt(1000);
    controller().toggle();
    controller().tickAt(1000);
    expect(state().tick, 194);
    expect(state().isPlaying, isFalse);
  });

  test('reaching end_officially_tick pauses playback', () {
    controller().toggle();
    controller().tickAt(100000);
    final s = state();
    expect(s.isPlaying, isFalse);
    expect(s.atRoundEnd, isTrue);
    expect(s.tick, 3010);
    // Stopped: further frames are ignored.
    controller().tickAt(100000);
    expect(s.tick, 3010);
  });

  test('seekToPercent maps to startTick..endOfficiallyTick', () {
    // 50% of [100..3010] -> floor(0.5 * 2910) + 100 = 1555.
    controller().seekToPercent(0.5);
    expect(state().tick, 1555);
    controller().seekToPercent(0.0);
    expect(state().tick, 100);
    controller().seekToPercent(1.0);
    expect(state().tick, 3010);
    expect(state().atRoundEnd, isTrue);
    // Seeking away from the end resumes possibility of playback.
    controller().seekToPercent(0.5);
    expect(state().atRoundEnd, isFalse);
  });

  test('selectRound resets tick to freeze_time_end_tick and clears end', () {
    controller().seekToPercent(1.0);
    expect(state().atRoundEnd, isTrue);
    controller().selectRound(2);
    final s = state();
    expect(s.roundNumber, 2);
    expect(s.tick, 3130);
    expect(s.atRoundEnd, isFalse);
  });

  test('setSpeed steps are kept in 0.5x-4x', () {
    controller().setSpeed(2.0);
    expect(state().speed, 2.0);
    // Advanced 1 s at 2x -> 128 ticks.
    controller().toggle();
    controller().tickAt(1000);
    expect(state().tick, 258);
  });

  test('roundTimeline exposes players of the selected round', () {
    final timeline = state().timeline!;
    expect(timeline.steamIds, containsAll([aliceSteamId, bobSteamId]));
    expect(timeline.sideOf(aliceSteamId), 2);
    expect(timeline.playerAt(aliceSteamId, 130), isNotNull);
  });

  test('speed of 0.5x advances half ticks with carry', () {
    controller().setSpeed(0.5);
    controller().toggle();
    controller().tickAt(500); // 0.5 s * 64 * 0.5 = 16 ticks
    expect(state().tick, 146);
  });
}
