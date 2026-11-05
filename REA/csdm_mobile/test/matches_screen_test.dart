import 'dart:io';

import 'package:csdm_mobile/transfer/downloader.dart';
import 'package:csdm_mobile/transfer/pairing.dart';
import 'package:csdm_mobile/transfer/providers.dart';
import 'package:csdm_mobile/ui/matches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePairing extends PairingNotifier {
  @override
  Future<PairingInfo?> build() async => const PairingInfo(baseUrl: 'http://h:1', token: 't');
}

void main() {
  testWidgets('lists desktop matches and cached ones', (tester) async {
    final dir = Directory.systemTemp.createTempSync('csdm_ms');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/cached1.csdmm').writeAsBytesSync([0]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        docsDirProvider.overrideWith((_) async => dir),
        pairingProvider.overrideWith(_FakePairing.new),
        matchListProvider.overrideWith((_) async => [
              MatchSummary(checksum: 'a1', mapName: 'de_mirage', date: DateTime(2026, 1, 1), duration: 1800, hasPositions: true),
              MatchSummary(checksum: 'b2', mapName: 'de_dust2', date: DateTime(2026, 1, 2), duration: 1700, hasPositions: false),
            ]),
      ],
      child: const MaterialApp(home: MatchesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('de_mirage'), findsOneWidget);
    expect(find.text('No position data'), findsOneWidget);
    expect(find.text('cached1'), findsOneWidget);
    expect(find.byIcon(Icons.download), findsNWidgets(2));
  });
}
