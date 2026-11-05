import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../transfer/pairing.dart';
import '../transfer/providers.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _manual = TextEditingController();
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    if (_done) return;
    final info = PairingInfo.parse(raw);
    if (info == null) {
      setState(() => _error = 'Not a valid pairing URL (expected http://ip:port/#/token)');
      return;
    }
    _done = true;
    await ref.read(pairingProvider.notifier).set(info);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with desktop')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (c) {
                final v = c.barcodes.firstOrNull?.rawValue;
                if (v != null) _submit(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _manual,
              decoration: InputDecoration(
                labelText: 'Or paste pairing URL',
                errorText: _error,
                suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: () => _submit(_manual.text)),
              ),
              onSubmitted: _submit,
            ),
          ),
        ],
      ),
    );
  }
}
