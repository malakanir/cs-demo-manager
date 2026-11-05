import 'package:csdm_mobile/models/map_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(MapParams.clear);

  test('parseAll reads the exporter field names', () {
    final maps = MapParams.parseAll('''
      [
        {"name": "de_mirage", "game": "cs2", "position_x": -3230, "position_y": 1713, "scale": 5, "threshold_z": 0},
        {"name": "de_dust2", "game": "cs2", "position_x": -2476, "position_y": 3239, "scale": 4.4, "threshold_z": 2.5}
      ]
    ''');

    expect(maps, hasLength(2));
    expect(maps.first.name, 'de_mirage');
    expect(maps.first.game, 'cs2');
    expect(maps.first.posX, -3230);
    expect(maps.first.posY, 1713);
    expect(maps.first.scale, 5);
    expect(maps.first.thresholdZ, 0);
    expect(maps.last.thresholdZ, 2.5);
  });

  test('forMap returns cached parameters and null for unknown maps', () {
    MapParams.setAll(
      MapParams.parseAll('''
      [{"name": "de_mirage", "game": "cs2", "position_x": -3230, "position_y": 1713, "scale": 5, "threshold_z": 0}]
    '''),
    );

    final mirage = MapParams.forMap('de_mirage');
    expect(mirage, isNotNull);
    expect(mirage!.posX, -3230);
    expect(mirage.posY, 1713);
    expect(mirage.scale, 5);
    expect(mirage.thresholdZ, 0);
    expect(MapParams.forMap('de_unknown'), isNull);
  });

  test('the bundled maps.json contains CS2 radar parameters', () async {
    await MapParams.loadFromAsset();

    final mirage = MapParams.forMap('de_mirage');
    expect(mirage, isNotNull);
    expect(mirage!.game, 'cs2');
    expect(mirage.posX, -3230);
    expect(mirage.posY, 1713);
    expect(mirage.scale, 5);
    expect(MapParams.forMap('de_dust2')?.scale, 4.4);
    expect(MapParams.forMap('cs_office'), isNotNull);
  });
}
