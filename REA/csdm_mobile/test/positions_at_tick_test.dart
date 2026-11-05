import 'dart:typed_data';

import 'package:csdm_mobile/models/packed_timeline.dart';
import 'package:csdm_mobile/playback/positions_at_tick.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blobs.dart';

PackedTimeline buildMovements({
  required List<int> ticks,
  required List<double> x,
  required List<double> y,
  List<double>? z,
  List<double>? yaw,
  List<double>? flash,
  List<int>? ducking,
  List<int>? airborne,
}) {
  final count = ticks.length;
  return PackedTimeline.decodeMovements(
    ticks: int32Blob(ticks),
    x: float32Blob(x),
    y: float32Blob(y),
    z: float32Blob(z ?? List<double>.filled(count, 0)),
    yaw: float32Blob(yaw ?? List<double>.filled(count, 0)),
    flashDurationRemaining: float32Blob(flash ?? List<double>.filled(count, 0)),
    isDucking: uint8Blob(ducking ?? List<int>.filled(count, 0)),
    isAirborne: uint8Blob(airborne ?? List<int>.filled(count, 0)),
  );
}

PackedTimeline buildStates({
  required List<int> ticks,
  List<int>? isAlive,
  List<int>? side,
  List<int>? money,
  List<int>? health,
  List<int>? armor,
  List<int>? hasHelmet,
  List<int>? hasBomb,
  List<int>? hasDefuseKit,
  List<int>? isScoping,
  List<int>? isDefusing,
  List<int>? isPlanting,
  List<int>? isGrabbingHostage,
  List<String>? activeWeaponNames,
  List<String>? equipments,
  List<String>? grenades,
  List<String>? pistols,
  List<String>? smgs,
  List<String>? rifles,
  List<String>? heavy,
}) {
  final count = ticks.length;
  List<int> integers(List<int>? values) => values ?? List<int>.filled(count, 0);
  List<int> booleans(List<int>? values) => values ?? List<int>.filled(count, 0);
  List<String> strings(List<String>? values) =>
      values ?? List<String>.filled(count, '');

  return PackedTimeline.decodeStates(
    stateTicks: int32Blob(ticks),
    isAlive: uint8Blob(booleans(isAlive)),
    side: int32Blob(integers(side)),
    money: int32Blob(integers(money)),
    health: int32Blob(integers(health)),
    armor: int32Blob(integers(armor)),
    hasHelmet: uint8Blob(booleans(hasHelmet)),
    hasBomb: uint8Blob(booleans(hasBomb)),
    hasDefuseKit: uint8Blob(booleans(hasDefuseKit)),
    isScoping: uint8Blob(booleans(isScoping)),
    isDefusing: uint8Blob(booleans(isDefusing)),
    isPlanting: uint8Blob(booleans(isPlanting)),
    isGrabbingHostage: uint8Blob(booleans(isGrabbingHostage)),
    activeWeaponNames: strings(activeWeaponNames),
    equipments: strings(equipments),
    grenades: strings(grenades),
    pistols: strings(pistols),
    smgs: strings(smgs),
    rifles: strings(rifles),
    heavy: strings(heavy),
  );
}

RoundTimeline buildRoundTimeline({
  required PackedTimeline movements,
  required PackedTimeline states,
  int tickrate = 64,
  String steamId = 'alice',
}) {
  return RoundTimeline(
    tickrate: tickrate,
    players: [
      PlayerTimeline(steamId: steamId, movements: movements, states: states),
    ],
  );
}

void main() {
  group('findLastIndexAtOrBefore', () {
    final ticks = Int32List.fromList([100, 200, 300]);

    test('returns -1 before the first tick', () {
      expect(findLastIndexAtOrBefore(ticks, 99), -1);
    });

    test('returns the exact index for a tick equal to a sample', () {
      expect(findLastIndexAtOrBefore(ticks, 100), 0);
      expect(findLastIndexAtOrBefore(ticks, 200), 1);
      expect(findLastIndexAtOrBefore(ticks, 300), 2);
    });

    test('returns the last sample at or before a tick between samples', () {
      expect(findLastIndexAtOrBefore(ticks, 150), 0);
      expect(findLastIndexAtOrBefore(ticks, 299), 1);
    });

    test('returns the last index for a tick after every sample', () {
      expect(findLastIndexAtOrBefore(ticks, 1000), 2);
    });

    test('returns -1 for empty ticks', () {
      expect(findLastIndexAtOrBefore(Int32List(0), 0), -1);
    });
  });

  group('interpolateYaw', () {
    test('interpolates within the same turn', () {
      expect(interpolateYaw(0, 90, 0.5), closeTo(45, 1e-9));
      expect(interpolateYaw(0, 90, 0.25), closeTo(22.5, 1e-9));
    });

    test('interpolates 90 to 270 through 180', () {
      expect(interpolateYaw(90, 270, 0.5), closeTo(180, 1e-9));
    });

    test('interpolates 350 to 10 across north as 0, not -340', () {
      expect(interpolateYaw(350, 10, 0.5), closeTo(0, 1e-9));
      expect(interpolateYaw(350, 10, 0.25), closeTo(355, 1e-9));
      expect(interpolateYaw(350, 10, 0.75), closeTo(5, 1e-9));
    });

    test('takes the shortest rotation across the 180 boundary', () {
      // 170 -> -170 is +20 degrees, so the midpoint is 180.
      expect(interpolateYaw(170, -170, 0.5), closeTo(180, 1e-9));
    });

    test('keeps endpoints unchanged', () {
      expect(interpolateYaw(90, 270, 0), closeTo(90, 1e-9));
      expect(interpolateYaw(90, 270, 1), closeTo(270, 1e-9));
    });
  });

  group('RoundTimeline playerAt', () {
    test('interpolates x, y, z and flash linearly between samples', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(
          ticks: [0, 4],
          x: [0, 40],
          y: [100, 60],
          z: [10, 30],
          flash: [2, 1],
          yaw: [0, 0],
        ),
        states: buildStates(ticks: [0]),
      );

      final position = timeline.playerAt('alice', 2)!;

      expect(position.x, closeTo(20, 1e-6));
      expect(position.y, closeTo(80, 1e-6));
      expect(position.z, closeTo(20, 1e-6));
      expect(position.flash, closeTo(1.5, 1e-6));
    });

    test('interpolates yaw circularly between samples', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(
          ticks: [0, 10],
          x: [0, 0],
          y: [0, 0],
          yaw: [350, 10],
        ),
        states: buildStates(ticks: [0]),
      );

      expect(timeline.playerAt('alice', 5)!.yaw, closeTo(0, 1e-6));

      final crossing180 = buildRoundTimeline(
        movements: buildMovements(
          ticks: [0, 10],
          x: [0, 0],
          y: [0, 0],
          yaw: [90, 270],
        ),
        states: buildStates(ticks: [0]),
      );

      expect(crossing180.playerAt('alice', 5)!.yaw, closeTo(180, 1e-6));
    });

    test('steps state to the last state at or before the tick', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(ticks: [0, 100], x: [0, 100], y: [0, 0]),
        states: buildStates(
          ticks: [0, 50],
          health: [100, 50],
          side: [3, 3],
          activeWeaponNames: ['weapon_ak47', 'weapon_awp'],
        ),
      );

      expect(timeline.playerAt('alice', 25)!.state!.health, 100);
      expect(timeline.playerAt('alice', 50)!.state!.health, 50);
      expect(timeline.playerAt('alice', 99)!.state!.health, 50);
      expect(
        timeline.playerAt('alice', 25)!.state!.activeWeaponName,
        'weapon_ak47',
      );
      expect(
        timeline.playerAt('alice', 99)!.state!.activeWeaponName,
        'weapon_awp',
      );
    });

    test('steps ducking and airborne from the previous movement sample', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(
          ticks: [0, 10],
          x: [0, 10],
          y: [0, 0],
          ducking: [1, 0],
          airborne: [0, 1],
        ),
        states: buildStates(ticks: [0]),
      );

      final position = timeline.playerAt('alice', 5)!;

      expect(position.ducking, isTrue);
      expect(position.airborne, isFalse);
    });

    test('holds the last sample when the gap exceeds the tickrate', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(
          ticks: [0, 200],
          x: [0, 100],
          y: [0, 0],
          yaw: [0, 180],
        ),
        states: buildStates(ticks: [0]),
      );

      final position = timeline.playerAt('alice', 50)!;

      expect(position.x, 0);
      expect(position.yaw, 0);
      expect(timeline.playerAt('alice', 199)!.x, 0);
    });

    test(
      'holds the last sample inside a hole but returns null after the end',
      () {
        final hole = buildRoundTimeline(
          movements: buildMovements(ticks: [0, 300], x: [0, 300], y: [0, 0]),
          states: buildStates(ticks: [0]),
        );

        expect(hole.playerAt('alice', 100)!.x, 0);

        final dead = buildRoundTimeline(
          movements: buildMovements(ticks: [0, 500], x: [0, 500], y: [0, 0]),
          states: buildStates(ticks: [0, 500], isAlive: [1, 0]),
        );

        expect(dead.playerAt('alice', 500), isNotNull);
        expect(dead.playerAt('alice', 600), isNull);
      },
    );

    test('returns null before the first sample or for an unknown player', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(ticks: [100, 200], x: [0, 100], y: [0, 0]),
        states: buildStates(ticks: [100]),
      );

      expect(timeline.playerAt('alice', 99), isNull);
      expect(timeline.playerAt('bob', 150), isNull);
    });
  });

  group('sideOf', () {
    test('returns the side from the first state sample', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(ticks: [100], x: [0], y: [0]),
        states: buildStates(ticks: [100, 200], side: [3, 2]),
      );

      expect(timeline.sideOf('alice'), 3);
    });

    test('returns null when the player has no state samples', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(ticks: [100], x: [0], y: [0]),
        states: buildStates(ticks: [], side: []),
      );

      expect(timeline.sideOf('alice'), isNull);
    });

    test('returns null for an unknown player', () {
      final timeline = buildRoundTimeline(
        movements: buildMovements(ticks: [100], x: [0], y: [0]),
        states: buildStates(ticks: [100]),
      );

      expect(timeline.sideOf('bob'), isNull);
    });
  });
}
