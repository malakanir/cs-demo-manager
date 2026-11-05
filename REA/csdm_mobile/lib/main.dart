import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/matches_screen.dart';

void main() {
  // A build error shows a readable message instead of the red debug screen.
  ErrorWidget.builder = (details) => const Material(
        color: Color(0xFF1B1F23),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Something went wrong. Go back and try again.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
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
