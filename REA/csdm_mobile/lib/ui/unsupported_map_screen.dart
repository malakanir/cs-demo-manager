import 'package:flutter/material.dart';

/// Shown when the match's map has no radar image or transform in this app.
class UnsupportedMapScreen extends StatelessWidget {
  const UnsupportedMapScreen({super.key, required this.mapName});

  final String mapName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unsupported map')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('This app has no radar for "$mapName" yet, so the match cannot be replayed.'),
        ),
      ),
    );
  }
}
