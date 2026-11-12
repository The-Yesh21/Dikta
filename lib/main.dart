import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'ui/screens/benchmark_screen.dart';
import 'ui/screens/dictation_test_screen.dart';
import 'ui/screens/voice_audition_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    sherpa_onnx.initBindings();
  } catch (e) {
    debugPrint('Native init exception: $e');
  }
  runApp(const DictationApp());
}

class DictationApp extends StatelessWidget {
  const DictationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dictation App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DictationHomeScreen(),
    );
  }
}

class DictationHomeScreen extends StatefulWidget {
  const DictationHomeScreen({super.key});

  @override
  State<DictationHomeScreen> createState() => _DictationHomeScreenState();
}

class _DictationHomeScreenState extends State<DictationHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DictationTestScreen(),
    VoiceAuditionScreen(),
    BenchmarkScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.record_voice_over),
            label: 'Dictate & Play',
          ),
          NavigationDestination(
            icon: Icon(Icons.hearing),
            label: 'Audition Voices',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed),
            label: 'Benchmark',
          ),
        ],
      ),
    );
  }
}
