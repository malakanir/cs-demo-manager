import 'dart:io';

class Library {
  const Library(this.dir);

  final Directory dir;

  String pathFor(String checksum) => '${dir.path}/$checksum.csdmm';

  /// Checksums of fully downloaded matches (`.part` files are ignored).
  List<String> listCached() => [
        for (final e in dir.listSync())
          if (e is File && e.path.endsWith('.csdmm'))
            e.uri.pathSegments.last.replaceFirst(RegExp(r'\.csdmm$'), ''),
      ]..sort();
}
