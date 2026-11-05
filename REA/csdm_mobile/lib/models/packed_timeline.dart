import 'dart:typed_data';

/// Decodes the big-endian BLOBs stored in `.csdmm` player position rows.
///
/// csdm packs positions as parallel arrays: movement columns are indexed by
/// `ticks[i]` (int32 ticks, float32 coordinates, uint8 booleans) and state
/// columns are indexed by `stateTicks[i]` (int32 values, uint8 booleans,
/// comma-separated weapon names). The decoded values are kept in flat typed
/// lists so playback never allocates one object per tick.
class PackedTimeline {
  const PackedTimeline._({
    required this.ticks,
    required this.xPos,
    required this.yPos,
    required this.zPos,
    required this.yaw,
    required this.flash,
    required this.isDucking,
    required this.isAirborne,
    required this.stateTicks,
    required this.isAlive,
    required this.side,
    required this.money,
    required this.health,
    required this.armor,
    required this.hasHelmet,
    required this.hasBomb,
    required this.hasDefuseKit,
    required this.isScoping,
    required this.isDefusing,
    required this.isPlanting,
    required this.isGrabbingHostage,
    required this.activeWeaponNames,
    required this.equipments,
    required this.grenades,
    required this.pistols,
    required this.smgs,
    required this.rifles,
    required this.heavy,
  });

  /// Decodes the movement columns of a player position row.
  factory PackedTimeline.decodeMovements({
    required Uint8List ticks,
    required Uint8List x,
    required Uint8List y,
    required Uint8List z,
    required Uint8List yaw,
    required Uint8List flashDurationRemaining,
    required Uint8List isDucking,
    required Uint8List isAirborne,
  }) {
    final count = _int32Count('ticks', ticks);
    _requireInt32Count('x', x, count);
    _requireInt32Count('y', y, count);
    _requireInt32Count('z', z, count);
    _requireInt32Count('yaw', yaw, count);
    _requireInt32Count(
      'flash_duration_remaining',
      flashDurationRemaining,
      count,
    );
    _requireUint8Count('is_ducking', isDucking, count);
    _requireUint8Count('is_airborne', isAirborne, count);

    final decodedTicks = Int32List(count);
    final xPos = Float32List(count);
    final yPos = Float32List(count);
    final zPos = Float32List(count);
    final decodedYaw = Float32List(count);
    final flash = Float32List(count);

    final ticksData = ByteData.sublistView(ticks);
    final xData = ByteData.sublistView(x);
    final yData = ByteData.sublistView(y);
    final zData = ByteData.sublistView(z);
    final yawData = ByteData.sublistView(yaw);
    final flashData = ByteData.sublistView(flashDurationRemaining);

    for (var index = 0; index < count; index++) {
      final offset = index * 4;
      decodedTicks[index] = ticksData.getInt32(offset, Endian.big);
      xPos[index] = xData.getFloat32(offset, Endian.big);
      yPos[index] = yData.getFloat32(offset, Endian.big);
      zPos[index] = zData.getFloat32(offset, Endian.big);
      decodedYaw[index] = yawData.getFloat32(offset, Endian.big);
      flash[index] = flashData.getFloat32(offset, Endian.big);
    }

    return PackedTimeline._(
      ticks: decodedTicks,
      xPos: xPos,
      yPos: yPos,
      zPos: zPos,
      yaw: decodedYaw,
      flash: flash,
      isDucking: Uint8List.fromList(isDucking),
      isAirborne: Uint8List.fromList(isAirborne),
      stateTicks: Int32List(0),
      isAlive: Uint8List(0),
      side: Int32List(0),
      money: Int32List(0),
      health: Int32List(0),
      armor: Int32List(0),
      hasHelmet: Uint8List(0),
      hasBomb: Uint8List(0),
      hasDefuseKit: Uint8List(0),
      isScoping: Uint8List(0),
      isDefusing: Uint8List(0),
      isPlanting: Uint8List(0),
      isGrabbingHostage: Uint8List(0),
      activeWeaponNames: const [],
      equipments: const [],
      grenades: const [],
      pistols: const [],
      smgs: const [],
      rifles: const [],
      heavy: const [],
    );
  }

  /// Decodes the state columns of a player position row. States only have a
  /// sample when they change, hence `stateCount` is usually lower than
  /// `movementCount`.
  factory PackedTimeline.decodeStates({
    required Uint8List stateTicks,
    required Uint8List isAlive,
    required Uint8List side,
    required Uint8List money,
    required Uint8List health,
    required Uint8List armor,
    required Uint8List hasHelmet,
    required Uint8List hasBomb,
    required Uint8List hasDefuseKit,
    required Uint8List isScoping,
    required Uint8List isDefusing,
    required Uint8List isPlanting,
    required Uint8List isGrabbingHostage,
    required List<String> activeWeaponNames,
    required List<String> equipments,
    required List<String> grenades,
    required List<String> pistols,
    required List<String> smgs,
    required List<String> rifles,
    required List<String> heavy,
  }) {
    final count = _int32Count('state_ticks', stateTicks);
    _requireInt32Count('side', side, count);
    _requireInt32Count('money', money, count);
    _requireInt32Count('health', health, count);
    _requireInt32Count('armor', armor, count);
    _requireUint8Count('is_alive', isAlive, count);
    _requireUint8Count('has_helmet', hasHelmet, count);
    _requireUint8Count('has_bomb', hasBomb, count);
    _requireUint8Count('has_defuse_kit', hasDefuseKit, count);
    _requireUint8Count('is_scoping', isScoping, count);
    _requireUint8Count('is_defusing', isDefusing, count);
    _requireUint8Count('is_planting', isPlanting, count);
    _requireUint8Count('is_grabbing_hostage', isGrabbingHostage, count);
    _requireStringCount('active_weapon_name', activeWeaponNames, count);
    _requireStringCount('equipments', equipments, count);
    _requireStringCount('grenades', grenades, count);
    _requireStringCount('pistols', pistols, count);
    _requireStringCount('smgs', smgs, count);
    _requireStringCount('rifles', rifles, count);
    _requireStringCount('heavy', heavy, count);

    final decodedStateTicks = Int32List(count);
    final decodedSide = Int32List(count);
    final decodedMoney = Int32List(count);
    final decodedHealth = Int32List(count);
    final decodedArmor = Int32List(count);

    final ticksData = ByteData.sublistView(stateTicks);
    final sideData = ByteData.sublistView(side);
    final moneyData = ByteData.sublistView(money);
    final healthData = ByteData.sublistView(health);
    final armorData = ByteData.sublistView(armor);

    for (var index = 0; index < count; index++) {
      final offset = index * 4;
      decodedStateTicks[index] = ticksData.getInt32(offset, Endian.big);
      decodedSide[index] = sideData.getInt32(offset, Endian.big);
      decodedMoney[index] = moneyData.getInt32(offset, Endian.big);
      decodedHealth[index] = healthData.getInt32(offset, Endian.big);
      decodedArmor[index] = armorData.getInt32(offset, Endian.big);
    }

    return PackedTimeline._(
      ticks: Int32List(0),
      xPos: Float32List(0),
      yPos: Float32List(0),
      zPos: Float32List(0),
      yaw: Float32List(0),
      flash: Float32List(0),
      isDucking: Uint8List(0),
      isAirborne: Uint8List(0),
      stateTicks: decodedStateTicks,
      isAlive: Uint8List.fromList(isAlive),
      side: decodedSide,
      money: decodedMoney,
      health: decodedHealth,
      armor: decodedArmor,
      hasHelmet: Uint8List.fromList(hasHelmet),
      hasBomb: Uint8List.fromList(hasBomb),
      hasDefuseKit: Uint8List.fromList(hasDefuseKit),
      isScoping: Uint8List.fromList(isScoping),
      isDefusing: Uint8List.fromList(isDefusing),
      isPlanting: Uint8List.fromList(isPlanting),
      isGrabbingHostage: Uint8List.fromList(isGrabbingHostage),
      activeWeaponNames: List<String>.unmodifiable(activeWeaponNames),
      equipments: List<String>.unmodifiable(equipments),
      grenades: List<String>.unmodifiable(grenades),
      pistols: List<String>.unmodifiable(pistols),
      smgs: List<String>.unmodifiable(smgs),
      rifles: List<String>.unmodifiable(rifles),
      heavy: List<String>.unmodifiable(heavy),
    );
  }

  /// Movement ticks, parallel to [xPos], [yPos], [zPos], [yaw] and [flash].
  final Int32List ticks;
  final Float32List xPos;
  final Float32List yPos;
  final Float32List zPos;
  final Float32List yaw;
  final Float32List flash;
  final Uint8List isDucking;
  final Uint8List isAirborne;

  /// State ticks, parallel to every other state column.
  final Int32List stateTicks;
  final Uint8List isAlive;
  final Int32List side;
  final Int32List money;
  final Int32List health;
  final Int32List armor;
  final Uint8List hasHelmet;
  final Uint8List hasBomb;
  final Uint8List hasDefuseKit;
  final Uint8List isScoping;
  final Uint8List isDefusing;
  final Uint8List isPlanting;
  final Uint8List isGrabbingHostage;

  /// Weapon lists, parallel to [stateTicks].
  final List<String> activeWeaponNames;
  final List<String> equipments;
  final List<String> grenades;
  final List<String> pistols;
  final List<String> smgs;
  final List<String> rifles;
  final List<String> heavy;

  int get movementCount => ticks.length;
  int get stateCount => stateTicks.length;
}

/// Decodes a big-endian int32 BLOB (grenade ticks, inferno ticks, ...).
Int32List decodeInt32Blob(Uint8List blob) {
  final count = _int32Count('int32 blob', blob);
  final values = Int32List(count);
  final data = ByteData.sublistView(blob);
  for (var index = 0; index < count; index++) {
    values[index] = data.getInt32(index * 4, Endian.big);
  }
  return values;
}

/// Decodes a big-endian float32 BLOB (grenade coordinates, ...).
Float32List decodeFloat32Blob(Uint8List blob) {
  final count = _int32Count('float32 blob', blob);
  final values = Float32List(count);
  final data = ByteData.sublistView(blob);
  for (var index = 0; index < count; index++) {
    values[index] = data.getFloat32(index * 4, Endian.big);
  }
  return values;
}

int _int32Count(String column, Uint8List bytes) {
  if (bytes.lengthInBytes % 4 != 0) {
    throw FormatException(
      '$column blob length ${bytes.lengthInBytes} is not a multiple of 4',
    );
  }
  return bytes.lengthInBytes ~/ 4;
}

void _requireInt32Count(String column, Uint8List bytes, int expected) {
  final count = _int32Count(column, bytes);
  if (count != expected) {
    throw FormatException('$column has $count values, expected $expected');
  }
}

void _requireUint8Count(String column, Uint8List bytes, int expected) {
  if (bytes.lengthInBytes != expected) {
    throw FormatException(
      '$column has ${bytes.lengthInBytes} values, expected $expected',
    );
  }
}

void _requireStringCount(String column, List<String> values, int expected) {
  if (values.length != expected) {
    throw FormatException(
      '$column has ${values.length} values, expected $expected',
    );
  }
}
