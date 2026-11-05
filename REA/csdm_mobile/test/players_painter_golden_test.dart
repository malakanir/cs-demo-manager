// `flutter test` only discovers files ending in `_test.dart`; the golden lives
// in `players_painter_golden.dart` per the task brief, so this wrapper makes it
// part of the default suite.
import 'players_painter_golden.dart' as golden;

void main() => golden.main();
