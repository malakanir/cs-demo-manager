import 'package:flutter/material.dart';

import '../../models/csdmm_database.dart';
import '../../render/players_painter.dart';

const killFeedMaxRows = 4;
const killFeedSeconds = 5;

/// Kills of the current round within the last 5s of game time, newest last,
/// capped at [killFeedMaxRows].
List<KillRow> visibleKills(List<KillRow> kills, int tick, int tickrate) {
  final window = killFeedSeconds * tickrate;
  final live = kills.where((k) => k.tick <= tick && tick - k.tick < window).toList();
  return live.length > killFeedMaxRows ? live.sublist(live.length - killFeedMaxRows) : live;
}

Color _sideColor(int? side) => side == 3 ? ctColor : (side == 2 ? tColor : unknownSideColor);

class KillFeed extends StatelessWidget {
  const KillFeed({super.key, required this.kills, required this.names});

  /// Already windowed with [visibleKills].
  final List<KillRow> kills;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [for (final k in kills) _row(k)],
    );
  }

  Widget _row(KillRow k) {
    const base = TextStyle(color: Colors.white, fontSize: 12);
    final killer = k.killerSteamId == null ? null : (names[k.killerSteamId] ?? '?');
    final weapon = k.weaponName.replaceFirst('weapon_', '');
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(4)),
      child: Text.rich(
        TextSpan(style: base, children: [
          if (killer != null) TextSpan(text: killer, style: TextStyle(color: _sideColor(k.killerSide))),
          TextSpan(text: ' [$weapon]${k.headshot ? ' ⊙' : ''} '),
          TextSpan(text: names[k.victimSteamId] ?? '?', style: TextStyle(color: _sideColor(k.victimSide))),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
