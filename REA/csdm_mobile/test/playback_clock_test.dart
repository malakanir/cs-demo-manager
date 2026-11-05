import 'package:csdm_mobile/playback/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaybackClock', () {
    test('advances whole ticks from elapsed milliseconds', () {
      final clock = PlaybackClock(64)..reset(0);

      expect(clock.advance(500, 1), 32);
      expect(clock.tick, 32);
      expect(clock.residual, 0);
    });

    test('carries the fractional residual between advances', () {
      final clock = PlaybackClock(64)..reset(0);

      // 50ms * 64Hz = 3.2 ticks.
      expect(clock.advance(50, 1), 3);
      expect(clock.tick, 3);
      expect(clock.residual, closeTo(0.2, 1e-9));

      // The carried 0.2 gives 3.4 ticks on the next advance.
      expect(clock.advance(50, 1), 6);
      expect(clock.tick, 6);
      expect(clock.residual, closeTo(0.4, 1e-9));
    });

    test('speed multiplies the tick advance', () {
      final normal = PlaybackClock(64)..reset(0);
      final doubleSpeed = PlaybackClock(64)..reset(0);
      final halfSpeed = PlaybackClock(64)..reset(0);

      expect(normal.advance(500, 1), 32);
      expect(doubleSpeed.advance(500, 2), 64);
      expect(halfSpeed.advance(1000, 0.5), 32);
    });

    test('returns the absolute current tick', () {
      final clock = PlaybackClock(64)..reset(1000);

      expect(clock.advance(500, 1), 1032);
      expect(clock.tick, 1032);
    });

    test('reset clears the tick and the residual', () {
      final clock = PlaybackClock(64)..reset(0);
      clock.advance(50, 1);

      clock.reset(500);

      expect(clock.tick, 500);
      expect(clock.residual, 0);
      expect(clock.advance(50, 1), 503);
    });
  });
}
