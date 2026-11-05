/// Maps wall-clock elapsed time to demo ticks, carrying the fractional part so
/// that playback speed changes and display refresh rates never lose time.
///
/// The controller calls [advance] once per frame with the elapsed milliseconds
/// since the previous frame; the clock returns the new absolute demo tick.
class PlaybackClock {
  PlaybackClock(this.tickrate);

  /// Demo tickrate in ticks per second.
  final int tickrate;

  int _tick = 0;
  double _residual = 0;

  /// Current absolute demo tick.
  int get tick => _tick;

  /// Fractional tick accumulated but not applied yet, in `[0, 1)`.
  double get residual => _residual;

  /// Jumps to [tick] and drops any carried fraction (round switch, seek).
  void reset(int tick) {
    _tick = tick;
    _residual = 0;
  }

  /// Advances by [elapsedMs] of wall-clock time at [speed] (0.5x - 4x) and
  /// returns the new absolute tick.
  int advance(int elapsedMs, double speed) {
    final exactTicks = _residual + (elapsedMs / 1000) * tickrate * speed;
    final wholeTicks = exactTicks.floor();
    _residual = exactTicks - wholeTicks;
    _tick += wholeTicks;
    return _tick;
  }
}
