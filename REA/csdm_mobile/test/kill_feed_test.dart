import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:csdm_mobile/ui/viewer/kill_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

KillRow kill(int tick, {String victim = 'v'}) => KillRow(
      roundNumber: 1,
      tick: tick,
      killerSteamId: 'k',
      victimSteamId: victim,
      assisterSteamId: null,
      killerSide: 3,
      victimSide: 2,
      weaponName: 'weapon_ak47',
      headshot: true,
      killerX: null,
      killerY: null,
      victimX: null,
      victimY: null,
      throughSmoke: null,
      noScope: null,
      penetratedObjects: null,
    );

void main() {
  test('window is 5s of game time and excludes future kills', () {
    final kills = [kill(100), kill(500), kill(1000)];
    // tickrate 64 -> window 320 ticks. At tick 600: 100 is 500 old (out), 500 in, 1000 future.
    expect(visibleKills(kills, 600, 64).map((k) => k.tick), [500]);
    expect(visibleKills(kills, 819, 64).map((k) => k.tick), [500]);
    expect(visibleKills(kills, 820, 64), isEmpty);
  });

  test('capped to the 4 most recent', () {
    final kills = [for (var i = 0; i < 6; i++) kill(100 + i)];
    expect(visibleKills(kills, 110, 64).map((k) => k.tick), [102, 103, 104, 105]);
  });

  testWidgets('renders one row per kill with names', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KillFeed(kills: [kill(1)], names: const {'k': 'Alice', 'v': 'Bob'})),
    ));
    expect(find.textContaining('Alice', findRichText: true), findsOneWidget);
    expect(find.textContaining('ak47', findRichText: true), findsOneWidget);
  });
}
