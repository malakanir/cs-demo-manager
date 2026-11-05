import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/matches_screen.dart';

void main() {
  runApp(const ProviderScope(child: CsdmApp()));
}

class CsdmApp extends StatelessWidget {
  const CsdmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CS2 Replays',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
      home: const MatchesScreen(),
    );
  }
}
