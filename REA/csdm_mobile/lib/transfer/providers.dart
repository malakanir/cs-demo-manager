import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'downloader.dart';
import 'library.dart';
import 'pairing.dart';

final docsDirProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  return Directory('${base.path}/matches').create(recursive: true);
});

final pairingProvider = AsyncNotifierProvider<PairingNotifier, PairingInfo?>(PairingNotifier.new);

class PairingNotifier extends AsyncNotifier<PairingInfo?> {
  @override
  Future<PairingInfo?> build() async => PairingInfo.load(await ref.watch(docsDirProvider.future));

  Future<void> set(PairingInfo info) async {
    await PairingInfo.save(await ref.read(docsDirProvider.future), info);
    state = AsyncData(info);
  }
}

final downloaderProvider =
    FutureProvider<Downloader>((ref) async => Downloader(await ref.watch(docsDirProvider.future)));

final libraryProvider = FutureProvider<Library>((ref) async => Library(await ref.watch(docsDirProvider.future)));

final matchListProvider = FutureProvider<List<MatchSummary>>((ref) async {
  final pairing = await ref.watch(pairingProvider.future);
  if (pairing == null) return const [];
  return (await ref.watch(downloaderProvider.future)).listMatches(pairing);
});
