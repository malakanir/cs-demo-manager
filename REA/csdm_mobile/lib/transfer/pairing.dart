import 'dart:convert';
import 'dart:io';

class PairingInfo {
  const PairingInfo({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  /// Parses `http://ip:port/#/token` (the csdm-export QR payload).
  /// Returns null for anything else.
  static PairingInfo? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority || !uri.isScheme('http')) return null;
    final token = uri.fragment.startsWith('/') ? uri.fragment.substring(1) : '';
    if (token.isEmpty) return null;
    return PairingInfo(baseUrl: uri.replace(fragment: '', path: '').toString().replaceAll(RegExp(r'[/#]+$'), ''), token: token);
  }

  Map<String, String> toJson() => {'baseUrl': baseUrl, 'token': token};

  static Future<void> save(Directory dir, PairingInfo info) =>
      File('${dir.path}/pairing.json').writeAsString(jsonEncode(info.toJson()));

  static Future<PairingInfo?> load(Directory dir) async {
    final file = File('${dir.path}/pairing.json');
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return PairingInfo(baseUrl: json['baseUrl'] as String, token: json['token'] as String);
    } on FormatException {
      return null;
    }
  }
}
