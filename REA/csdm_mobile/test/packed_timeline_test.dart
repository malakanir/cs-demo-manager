import 'dart:typed_data';

import 'package:csdm_mobile/models/packed_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/blobs.dart';

PackedTimeline decodeMovements() {
  return PackedTimeline.decodeMovements(
    ticks: int32Blob([100, 200]),
    x: float32Blob([-500.5, 600.25]),
    y: float32Blob([1200.75, -300.5]),
    z: float32Blob([64.03125, -16.5]),
    yaw: float32Blob([90, 359.5]),
    flashDurationRemaining: float32Blob([0, 2.5]),
    isDucking: uint8Blob([1, 0]),
    isAirborne: uint8Blob([0, 1]),
  );
}

PackedTimeline decodeStates() {
  return PackedTimeline.decodeStates(
    stateTicks: int32Blob([100]),
    isAlive: uint8Blob([1]),
    side: int32Blob([2]),
    money: int32Blob([4000]),
    health: int32Blob([100]),
    armor: int32Blob([100]),
    hasHelmet: uint8Blob([1]),
    hasBomb: uint8Blob([0]),
    hasDefuseKit: uint8Blob([0]),
    isScoping: uint8Blob([0]),
    isDefusing: uint8Blob([0]),
    isPlanting: uint8Blob([0]),
    isGrabbingHostage: uint8Blob([0]),
    activeWeaponNames: const ['weapon_ak47'],
    equipments: const ['weapon_knife'],
    // The exporter CSV-joins inventory arrays, so "no grenades" is one empty
    // string per state sample, not a zero-length list.
    grenades: const [''],
    pistols: const ['weapon_glock'],
    smgs: const [''],
    rifles: const ['weapon_ak47'],
    heavy: const [''],
  );
}

void main() {
  group('PackedTimeline.decodeMovements', () {
    test('decodes int32 ticks and exact float32 values', () {
      final timeline = decodeMovements();

      expect(timeline.movementCount, 2);
      expect(timeline.stateCount, 0);
      expect(timeline.ticks, orderedEquals([100, 200]));
      expect(timeline.xPos, orderedEquals([-500.5, 600.25]));
      expect(timeline.yPos, orderedEquals([1200.75, -300.5]));
      expect(timeline.zPos, orderedEquals([64.03125, -16.5]));
      expect(timeline.yaw, orderedEquals([90, 359.5]));
      expect(timeline.flash, orderedEquals([0, 2.5]));
    });

    test('decodes uint8 boolean bytes at the movement index', () {
      final timeline = decodeMovements();

      expect(timeline.isDucking, orderedEquals([1, 0]));
      expect(timeline.isAirborne, orderedEquals([0, 1]));
      expect(timeline.isDucking[0], 1);
      expect(timeline.isDucking[1], 0);
    });

    test('decodes blobs that are not 4-byte aligned', () {
      final timeline = PackedTimeline.decodeMovements(
        ticks: unaligned(int32Blob([100, 200])),
        x: unaligned(float32Blob([-500.5, 600.25])),
        y: unaligned(float32Blob([1200.75, -300.5])),
        z: unaligned(float32Blob([64.03125, -16.5])),
        yaw: unaligned(float32Blob([90, 359.5])),
        flashDurationRemaining: unaligned(float32Blob([0, 2.5])),
        isDucking: uint8Blob([1, 0]),
        isAirborne: uint8Blob([0, 1]),
      );

      expect(timeline.ticks, orderedEquals([100, 200]));
      expect(timeline.xPos, orderedEquals([-500.5, 600.25]));
      expect(timeline.yaw, orderedEquals([90, 359.5]));
    });

    test(
      'throws FormatException when movement columns have different counts',
      () {
        expect(
          () => PackedTimeline.decodeMovements(
            ticks: int32Blob([100]),
            x: float32Blob([-500.5, 600.25]),
            y: float32Blob([1200.75]),
            z: float32Blob([64.03125]),
            yaw: float32Blob([90]),
            flashDurationRemaining: float32Blob([0]),
            isDucking: uint8Blob([1]),
            isAirborne: uint8Blob([0]),
          ),
          throwsFormatException,
        );
      },
    );

    test('throws FormatException when a movement blob is truncated', () {
      expect(
        () => PackedTimeline.decodeMovements(
          ticks: Uint8List.fromList([0, 0, 0]),
          x: float32Blob([1]),
          y: float32Blob([1]),
          z: float32Blob([1]),
          yaw: float32Blob([1]),
          flashDurationRemaining: float32Blob([0]),
          isDucking: uint8Blob([1]),
          isAirborne: uint8Blob([0]),
        ),
        throwsFormatException,
      );
    });
  });

  group('PackedTimeline.decodeStates', () {
    test('decodes int32, uint8 and string state columns', () {
      final states = decodeStates();

      expect(states.stateCount, 1);
      expect(states.movementCount, 0);
      expect(states.stateTicks, orderedEquals([100]));
      expect(states.isAlive, orderedEquals([1]));
      expect(states.side, orderedEquals([2]));
      expect(states.money, orderedEquals([4000]));
      expect(states.health, orderedEquals([100]));
      expect(states.armor, orderedEquals([100]));
      expect(states.hasHelmet, orderedEquals([1]));
      expect(states.hasBomb, orderedEquals([0]));
      expect(states.hasDefuseKit, orderedEquals([0]));
      expect(states.isScoping, orderedEquals([0]));
      expect(states.isDefusing, orderedEquals([0]));
      expect(states.isPlanting, orderedEquals([0]));
      expect(states.isGrabbingHostage, orderedEquals([0]));
    });

    test('keeps string arrays parallel to state indices', () {
      final states = decodeStates();

      expect(states.activeWeaponNames, equals(['weapon_ak47']));
      expect(states.equipments, equals(['weapon_knife']));
      expect(states.grenades, equals(['']));
      expect(states.pistols, equals(['weapon_glock']));
      expect(states.smgs, equals(['']));
      expect(states.rifles, equals(['weapon_ak47']));
      expect(states.heavy, equals(['']));
    });

    test('decodes multiple states with parallel weapon names', () {
      final states = PackedTimeline.decodeStates(
        stateTicks: int32Blob([100, 250]),
        isAlive: uint8Blob([1, 0]),
        side: int32Blob([2, 3]),
        money: int32Blob([4000, 800]),
        health: int32Blob([100, 0]),
        armor: int32Blob([100, 0]),
        hasHelmet: uint8Blob([1, 0]),
        hasBomb: uint8Blob([0, 1]),
        hasDefuseKit: uint8Blob([0, 0]),
        isScoping: uint8Blob([0, 0]),
        isDefusing: uint8Blob([0, 0]),
        isPlanting: uint8Blob([0, 0]),
        isGrabbingHostage: uint8Blob([0, 0]),
        activeWeaponNames: const ['weapon_ak47', 'weapon_knife'],
        equipments: const ['weapon_knife', 'c4'],
        grenades: const ['weapon_smokegrenade', ''],
        pistols: const ['', ''],
        smgs: const ['', ''],
        rifles: const ['weapon_ak47', ''],
        heavy: const ['', ''],
      );

      expect(states.stateCount, 2);
      expect(states.stateTicks, orderedEquals([100, 250]));
      expect(states.health, orderedEquals([100, 0]));
      expect(states.activeWeaponNames, equals(['weapon_ak47', 'weapon_knife']));
      expect(states.equipments, equals(['weapon_knife', 'c4']));
      expect(states.grenades, equals(['weapon_smokegrenade', '']));
    });

    test('throws FormatException when state columns have different counts', () {
      expect(
        () => PackedTimeline.decodeStates(
          stateTicks: int32Blob([100]),
          isAlive: uint8Blob([1]),
          side: int32Blob([2, 3]),
          money: int32Blob([4000]),
          health: int32Blob([100]),
          armor: int32Blob([100]),
          hasHelmet: uint8Blob([1]),
          hasBomb: uint8Blob([0]),
          hasDefuseKit: uint8Blob([0]),
          isScoping: uint8Blob([0]),
          isDefusing: uint8Blob([0]),
          isPlanting: uint8Blob([0]),
          isGrabbingHostage: uint8Blob([0]),
          activeWeaponNames: const ['weapon_ak47'],
          equipments: const ['weapon_knife'],
          grenades: const [],
          pistols: const [],
          smgs: const [],
          rifles: const [],
          heavy: const [],
        ),
        throwsFormatException,
      );
    });

    test(
      'throws FormatException when string arrays do not match state count',
      () {
        expect(
          () => PackedTimeline.decodeStates(
            stateTicks: int32Blob([100, 200]),
            isAlive: uint8Blob([1, 0]),
            side: int32Blob([2, 3]),
            money: int32Blob([4000, 800]),
            health: int32Blob([100, 0]),
            armor: int32Blob([100, 0]),
            hasHelmet: uint8Blob([1, 0]),
            hasBomb: uint8Blob([0, 1]),
            hasDefuseKit: uint8Blob([0, 0]),
            isScoping: uint8Blob([0, 0]),
            isDefusing: uint8Blob([0, 0]),
            isPlanting: uint8Blob([0, 0]),
            isGrabbingHostage: uint8Blob([0, 0]),
            activeWeaponNames: const ['weapon_ak47'],
            equipments: const ['weapon_knife', 'c4'],
            grenades: const ['', ''],
            pistols: const ['', ''],
            smgs: const ['', ''],
            rifles: const ['', ''],
            heavy: const ['', ''],
          ),
          throwsFormatException,
        );
      },
    );
  });

  test('decodeInt32Blob and decodeFloat32Blob decode big-endian values', () {
    expect(
      decodeInt32Blob(int32Blob([1, -2, 300])),
      orderedEquals([1, -2, 300]),
    );
    expect(
      decodeFloat32Blob(float32Blob([1.5, -2.25, 300.5])),
      orderedEquals([1.5, -2.25, 300.5]),
    );
  });
}
