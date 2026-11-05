import 'dart:convert';

import 'package:flutter/services.dart';

/// Radar transform parameters for one map, from `assets/maps.json`.
///
/// The asset is generated from csdm's `default-maps.ts` and bundled with the
/// app; it is loaded once per app start through [loadFromAsset].
class MapParams {
  const MapParams({
    required this.name,
    required this.game,
    required this.posX,
    required this.posY,
    required this.scale,
    required this.thresholdZ,
  });

  factory MapParams.fromJson(Map<String, Object?> json) {
    return MapParams(
      name: json['name']! as String,
      game: json['game']! as String,
      posX: (json['position_x']! as num).toDouble(),
      posY: (json['position_y']! as num).toDouble(),
      scale: (json['scale']! as num).toDouble(),
      thresholdZ: (json['threshold_z']! as num).toDouble(),
    );
  }

  static const assetPath = 'assets/maps.json';

  static Map<String, MapParams> _mapsByName = const {};

  /// Parses the maps JSON document (an array of map objects).
  static List<MapParams> parseAll(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      throw FormatException('$assetPath is not a JSON array');
    }
    return [
      for (final entry in decoded)
        if (entry is Map<String, Object?>)
          MapParams.fromJson(entry)
        else
          throw const FormatException('$assetPath entry is not an object'),
    ];
  }

  /// Loads and caches the bundled map parameters.
  static Future<void> loadFromAsset({AssetBundle? bundle}) async {
    final text = await (bundle ?? rootBundle).loadString(assetPath);
    setAll(parseAll(text));
  }

  /// Replaces the cached parameters, e.g. after loading the asset or in tests.
  static void setAll(Iterable<MapParams> maps) {
    _mapsByName = {for (final map in maps) map.name: map};
  }

  /// Returns the parameters for [name], or null when the map has no radar entry.
  static MapParams? forMap(String name) => _mapsByName[name];

  static void clear() {
    _mapsByName = const {};
  }

  final String name;
  final String game;
  final double posX;
  final double posY;
  final double scale;
  final double thresholdZ;
}
