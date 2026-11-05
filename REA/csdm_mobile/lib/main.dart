import 'package:flutter/material.dart';

void main() {
  runApp(const CsdmmApp());
}

class CsdmmApp extends StatelessWidget {
  const CsdmmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CS2 Replays',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
      ),
      home: const Scaffold(body: Center(child: Text('CS2 Replays'))),
    );
  }
}
