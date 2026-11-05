import 'package:flutter/material.dart';

import '../../models/csdmm_database.dart';
import '../../playback/positions_at_tick.dart';
import '../../render/players_painter.dart';

const teamsPanelWidth = 200.0;

/// Right-hand panel: one card per side with alive count; tap a card to list
/// its players (health, money, weapon). The whole panel collapses to a handle.
class TeamsPanel extends StatefulWidget {
  const TeamsPanel({super.key, required this.players, required this.timeline, required this.tick});

  final List<PlayerRow> players;
  final RoundTimeline timeline;
  final int tick;

  @override
  State<TeamsPanel> createState() => _TeamsPanelState();
}

class _TeamsPanelState extends State<TeamsPanel> {
  bool _collapsed = false;
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    if (_collapsed) {
      return IconButton(
        key: const Key('teams-panel-toggle'),
        style: IconButton.styleFrom(backgroundColor: const Color(0x8C000000)),
        icon: const Icon(Icons.groups, color: Colors.white),
        onPressed: () => setState(() => _collapsed = false),
      );
    }
    final bySide = <int, List<PlayerRow>>{3: [], 2: []};
    for (final p in widget.players) {
      final side = widget.timeline.sideOf(p.steamId);
      if (side != null && bySide.containsKey(side)) bySide[side]!.add(p);
    }
    return Container(
      key: const Key('teams-panel'),
      width: teamsPanelWidth,
      decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              key: const Key('teams-panel-toggle'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed: () => setState(() => _collapsed = true),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in bySide.entries)
                  if (e.value.isNotEmpty) _card(e.key, e.value),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(int side, List<PlayerRow> players) {
    final color = side == 3 ? ctColor : tColor;
    final states = {
      for (final p in players) p.steamId: widget.timeline.playerAt(p.steamId, widget.tick)?.state,
    };
    final alive = states.values.where((s) => s != null && s.isAlive).length;
    final open = _expanded.contains(side);
    return InkWell(
      key: Key('team-card-$side'),
      onTap: () => setState(() => open ? _expanded.remove(side) : _expanded.add(side)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${side == 3 ? 'CT' : 'T'}  $alive/${players.length} alive',
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (open)
              for (final p in players) _playerRow(p, states[p.steamId]),
          ],
        ),
      ),
    );
  }

  Widget _playerRow(PlayerRow p, StateAtTick? s) {
    final alive = s != null && s.isAlive;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        alive
            ? '${p.name}  ${s.health}hp  \$${s.money}  ${s.activeWeaponName.replaceFirst('weapon_', '')}'
            : '${p.name}  dead',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: alive ? Colors.white : Colors.white54, fontSize: 11),
      ),
    );
  }
}
