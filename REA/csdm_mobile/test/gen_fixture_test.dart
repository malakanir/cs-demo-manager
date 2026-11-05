import 'dart:io';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tool/gen_fixture_csdmm.dart writes a file the app can load', () {
    final dir = Directory.systemTemp.createTempSync('csdmm_t10');
    addTearDown(() => dir.deleteSync(recursive: true));

    final result = Process.runSync('dart', ['run', 'tool/gen_fixture_csdmm.dart', dir.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final path = (result.stdout as String).trim();
    expect(File(path).existsSync(), isTrue);
    final data = MatchData.load(path);
    expect(data.mapName, 'de_mirage');
    expect(data.rounds, isNotEmpty);

    // Refuses to overwrite an existing fixture.
    final again = Process.runSync('dart', ['run', 'tool/gen_fixture_csdmm.dart', dir.path]);
    expect(again.exitCode, 1);
  });
}
