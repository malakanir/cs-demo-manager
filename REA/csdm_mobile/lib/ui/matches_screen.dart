import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/csdmm_database.dart';
import '../playback/playback_controller.dart';
import '../transfer/downloader.dart';
import '../transfer/providers.dart';
import 'pairing_screen.dart';
import 'viewer/viewer_screen.dart';

class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  final Map<String, double?> _progress = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _download(MatchSummary m) async {
    final pairing = ref.read(pairingProvider).value;
    if (pairing == null) return;
    setState(() => _progress[m.checksum] = 0);
    try {
      await (await ref.read(downloaderProvider.future)).downloadMatch(
        pairing,
        m.checksum,
        onProgress: (r, t) {
          if (mounted) setState(() => _progress[m.checksum] = t > 0 ? r / t : null);
        },
      );
      ref.invalidate(libraryProvider);
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: ${e.message ?? e.type.name}')));
      }
    } finally {
      if (mounted) setState(() => _progress.remove(m.checksum));
    }
  }

  Future<void> _open(String checksum) async {
    final lib = await ref.read(libraryProvider.future);
    final MatchData data;
    try {
      data = await MatchData.loadAsync(lib.pathFor(checksum));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot open match: $e')));
      }
      return;
    }
    if (!mounted) return;
    // The viewer owns orientation: landscape on init, portrait on dispose.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProviderScope(
          overrides: [
            playbackDataProvider.overrideWithValue(ViewerPlayback(data: data, tickrate: data.tickrate)),
          ],
          child: ViewerScreen(checksum: checksum),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(pairingProvider);
    final matches = ref.watch(matchListProvider);
    final cached = ref.watch(libraryProvider).value?.listCached().toSet() ?? const <String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Pair',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const PairingScreen()))
                .then((_) => ref.invalidate(matchListProvider)),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (cached.isNotEmpty) ...[
            const ListTile(title: Text('Downloaded')),
            for (final c in cached) ListTile(title: Text(c), trailing: const Icon(Icons.play_arrow), onTap: () => _open(c)),
          ],
          const ListTile(title: Text('On desktop')),
          if (pairing.value == null)
            const ListTile(title: Text('Not paired. Scan the QR from csdm-export serve.'))
          else
            matches.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => ListTile(title: Text('Cannot reach desktop: $e')),
              data: (list) => Column(
                children: [for (final m in list) _tile(m, cached.contains(m.checksum))],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(MatchSummary m, bool isCached) {
    final p = _progress[m.checksum];
    final downloading = _progress.containsKey(m.checksum);
    return ListTile(
      title: Text(m.mapName),
      subtitle: Text(m.hasPositions ? m.date.toLocal().toString().split('.').first : 'No position data'),
      trailing: downloading
          ? SizedBox(width: 32, height: 32, child: CircularProgressIndicator(value: p))
          : isCached
              ? const Icon(Icons.check)
              : IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: m.hasPositions ? () => _download(m) : null,
                ),
      onTap: isCached ? () => _open(m.checksum) : null,
    );
  }
}
