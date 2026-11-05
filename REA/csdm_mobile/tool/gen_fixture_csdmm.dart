// Writes the deterministic test match used by the unit tests to a directory,
// so a device can be tested without a csdm database.
//
//   dart run tool/gen_fixture_csdmm.dart [output_dir]
//
// Prints the path of the created `.csdmm` file.
import 'dart:io';

import '../test/support/csdmm_fixture.dart';

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? '.' : args.first)..createSync(recursive: true);
  final path = '${dir.path}/$fixtureChecksum.csdmm';
  if (File(path).existsSync()) {
    stderr.writeln('$path already exists; remove it first.');
    exit(1);
  }
  stdout.writeln(createFixtureCsdmm(dir));
}
