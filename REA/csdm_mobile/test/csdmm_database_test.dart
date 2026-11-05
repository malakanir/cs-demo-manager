import 'dart:io';

import 'package:csdm_mobile/models/csdmm_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/csdmm_fixture.dart';

void main() {
  late Directory tempDirectory;
  late String fixturePath;

  setUpAll(() {
    tempDirectory = Directory.systemTemp.createTempSync('csdm_mobile_db_test_');
    fixturePath = createFixtureCsdmm(tempDirectory);
  });

  tearDownAll(() {
    tempDirectory.deleteSync(recursive: true);
  });

  group('CsdmmDatabase', () {
    late CsdmmDatabase database;

    setUp(() {
      database = CsdmmDatabase.open(fixturePath);
    });

    tearDown(() {
      database.close();
    });

    test('getMeta returns every match key verbatim', () {
      expect(database.getMeta(), {
        'checksum': fixtureChecksum,
        'map_name': fixtureMapName,
        'tickrate': '64',
        'tick_count': '1280',
        'game': 'cs2',
        'date': '2026-01-15T20:00:00.000Z',
        'demo_name': 'fixture-demo',
        'duration': '40',
        'format_version': '1',
        'has_positions': 'true',
      });
    });

    test('getPlayers returns typed rows ordered by steam id', () {
      final players = database.getPlayers();

      expect(players, hasLength(2));
      expect(players[0].steamId, aliceSteamId);
      expect(players[0].name, 'Alice');
      expect(players[0].teamName, 'TeamA');
      expect(players[0].color, '0');
      expect(players[1].steamId, bobSteamId);
      expect(players[1].name, 'Bob');
      expect(players[1].teamName, 'TeamB');
      expect(players[1].color, '1');
    });

    test('getRounds returns typed rows ordered by round number', () {
      final rounds = database.getRounds();

      expect(rounds, hasLength(2));
      expect(rounds[0].roundNumber, 1);
      expect(rounds[0].startTick, 100);
      expect(rounds[0].freezeTimeEndTick, 130);
      expect(rounds[0].endTick, 3000);
      expect(rounds[0].endOfficiallyTick, 3010);
      expect(rounds[0].winnerSide, 3);
      expect(rounds[0].endReason, 'target_bombed');
      expect(rounds[0].scoreCt, 1);
      expect(rounds[0].scoreT, 0);
      expect(rounds[1].roundNumber, 2);
      expect(rounds[1].winnerSide, 2);
      expect(rounds[1].scoreCt, 1);
      expect(rounds[1].scoreT, 1);
    });

    test('getPositions groups rows by round and decodes both blobs', () {
      final positions = database.getPositions();

      expect(positions.keys, orderedEquals([1]));
      final rows = positions[1]!;
      expect(rows, hasLength(2));

      final alice = rows.firstWhere((row) => row.playerSteamId == aliceSteamId);
      final movements = alice.movements;
      expect(movements.movementCount, 2);
      expect(movements.ticks, orderedEquals([100, 200]));
      expect(movements.xPos, orderedEquals([-500.5, 600.25]));
      expect(movements.yPos, orderedEquals([1200.75, -300.5]));
      expect(movements.zPos, orderedEquals([64.03125, -16.5]));
      expect(movements.yaw, orderedEquals([90, 359.5]));
      expect(movements.flash, orderedEquals([0, 2.5]));
      expect(movements.isDucking, orderedEquals([1, 0]));
      expect(movements.isAirborne, orderedEquals([0, 1]));

      final states = alice.states;
      expect(states.stateCount, 1);
      expect(states.stateTicks, orderedEquals([100]));
      expect(states.isAlive, orderedEquals([1]));
      expect(states.side, orderedEquals([2]));
      expect(states.money, orderedEquals([4000]));
      expect(states.health, orderedEquals([100]));
      expect(states.armor, orderedEquals([100]));
      expect(states.hasHelmet, orderedEquals([1]));
      expect(states.activeWeaponNames, equals(['weapon_ak47']));
      expect(states.equipments, equals(['weapon_knife']));
      expect(states.grenades, equals(['']));
      expect(states.pistols, equals(['weapon_glock']));
      expect(states.smgs, equals(['']));
      expect(states.rifles, equals(['weapon_ak47']));
      expect(states.heavy, equals(['']));

      final bob = rows.firstWhere((row) => row.playerSteamId == bobSteamId);
      expect(bob.movements.ticks, orderedEquals([100, 200]));
      expect(bob.states.side, orderedEquals([3]));
      expect(bob.states.money, orderedEquals([800]));
      expect(bob.states.activeWeaponNames, equals(['weapon_m4a1']));
    });

    test('getKills returns typed rows', () {
      final kills = database.getKills();

      expect(kills, hasLength(1));
      final kill = kills.single;
      expect(kill.roundNumber, 1);
      expect(kill.tick, 1500);
      expect(kill.killerSteamId, aliceSteamId);
      expect(kill.victimSteamId, bobSteamId);
      expect(kill.assisterSteamId, isNull);
      expect(kill.killerSide, 3);
      expect(kill.victimSide, 2);
      expect(kill.weaponName, 'weapon_ak47');
      expect(kill.headshot, isTrue);
      expect(kill.killerX, -500.5);
      expect(kill.killerY, 1200.75);
      expect(kill.victimX, 600.25);
      expect(kill.victimY, -300.5);
      expect(kill.throughSmoke, isFalse);
      expect(kill.noScope, isFalse);
      expect(kill.penetratedObjects, 0);
    });

    test('getGrenades decodes tick and position blobs', () {
      final grenades = database.getGrenades();

      expect(grenades, hasLength(1));
      final grenade = grenades.single;
      expect(grenade.roundNumber, 1);
      expect(grenade.grenadeId, 'gren-1');
      expect(grenade.projectileId, 'proj-1');
      expect(grenade.grenadeName, 'smoke');
      expect(grenade.throwerSteamId, aliceSteamId);
      expect(grenade.throwerSide, 3);
      expect(grenade.ticks, orderedEquals([200, 210]));
      expect(grenade.x, orderedEquals([-100, -90.5]));
      expect(grenade.y, orderedEquals([200, 210.25]));
      expect(grenade.z, orderedEquals([70, 70]));
    });

    test('getInfernos decodes ticks and parses JSON hull strings', () {
      final infernos = database.getInfernos();

      expect(infernos, hasLength(1));
      final inferno = infernos.single;
      expect(inferno.roundNumber, 1);
      expect(inferno.uniqueId, 'inf-1');
      expect(inferno.throwerSteamId, aliceSteamId);
      expect(inferno.ticks, orderedEquals([300, 320]));
      expect(inferno.convexHulls2d, [
        [1, 2, 3, 4],
        [5, 6, 7.5, 8],
      ]);
    });

    test('getShots, getBombEvents and getGrenadeEvents return typed rows', () {
      final shots = database.getShots();
      expect(shots, hasLength(1));
      expect(shots.single.tick, 1490);
      expect(shots.single.shooterSteamId, aliceSteamId);
      expect(shots.single.weaponName, 'weapon_ak47');
      expect(shots.single.x, -500.5);
      expect(shots.single.y, 1200.75);
      expect(shots.single.playerYaw, 90);

      final bombEvents = database.getBombEvents();
      expect(bombEvents, hasLength(1));
      expect(bombEvents.single.roundNumber, 1);
      expect(bombEvents.single.tick, 2000);
      expect(bombEvents.single.type, 'planted');

      final grenadeEvents = database.getGrenadeEvents();
      expect(grenadeEvents, hasLength(1));
      expect(grenadeEvents.single.tick, 1000);
      expect(grenadeEvents.single.type, 'smoke_start');
      expect(grenadeEvents.single.x, 10);
      expect(grenadeEvents.single.y, 20);
      expect(grenadeEvents.single.grenadeId, 'gren-1');
    });

    test('getMapTransform returns the match radar transform', () {
      final transform = database.getMapTransform();

      expect(transform, isNotNull);
      expect(transform!.name, fixtureMapName);
      expect(transform.game, 'cs2');
      expect(transform.positionX, 1000);
      expect(transform.positionY, 1000);
      expect(transform.scale, 5);
      expect(transform.thresholdZ, 10);
    });
  });

  group('MatchData.load', () {
    test('aggregates meta, players, rounds, positions, kills and effects', () {
      final match = MatchData.load(fixturePath);

      expect(match.meta['checksum'], fixtureChecksum);
      expect(match.checksum, fixtureChecksum);
      expect(match.mapName, fixtureMapName);
      expect(match.tickrate, 64);
      expect(match.players, hasLength(2));
      expect(match.rounds, hasLength(2));
      expect(match.positions[1], hasLength(2));
      expect(match.kills, hasLength(1));

      expect(match.effects.grenades, hasLength(1));
      expect(match.effects.infernos, hasLength(1));
      expect(match.effects.shots, hasLength(1));
      expect(match.effects.bombEvents, hasLength(1));
      expect(match.effects.grenadeEvents, hasLength(1));
      expect(match.mapTransform?.name, fixtureMapName);
    });

    test('closes the database so the file can be loaded again', () {
      final first = MatchData.load(fixturePath);
      final second = MatchData.load(fixturePath);

      expect(second.meta, equals(first.meta));
      expect(second.positions[1], hasLength(2));
    });
  });
}
