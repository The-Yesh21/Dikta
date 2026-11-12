import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/tts/kokoro_engine.dart';
import '../../services/tts/model_locator.dart';
import '../../services/tts/tts_benchmark_runner.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen>
    with SingleTickerProviderStateMixin {
  final ModelLocator _modelLocator = const ExternalStorageModelLocator();
  KokoroModelPaths? _modelPaths;
  Directory? _targetDirectory;
  bool _isChecking = true;
  bool _isRunning = false;
  String _currentStatus = 'Checking for model files...';
  final List<String> _logs = [];
  BenchmarkSuiteResult? _result;

  late final AnimationController _spinnerController;

  @override
  void initState() {
    super.initState();
    _spinnerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _checkModelStatus();
  }

  @override
  void dispose() {
    _spinnerController.dispose();
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    setState(() => _isChecking = true);
    final targetDir = await _modelLocator.getModelsDirectory();
    final paths = await _modelLocator.locateKokoroModel();

    setState(() {
      _targetDirectory = targetDir;
      _modelPaths = paths;
      _isChecking = false;
      if (paths != null) {
        _currentStatus =
            'Kokoro model detected (${paths.isInt8 ? "INT8" : "FP32"})!\nReady for benchmark.';
      } else {
        _currentStatus = 'Model files not found in app storage.';
      }
    });
  }

  void _runBenchmark() async {
    final paths = _modelPaths;
    if (paths == null) return;

    setState(() {
      _isRunning = true;
      _logs.clear();
      _result = null;
    });

    final runner = TtsBenchmarkRunner(modelPaths: paths);
    final stream = runner.runBenchmark(
      onComplete: (suiteResult) {
        setState(() {
          _isRunning = false;
          _result = suiteResult;
          _currentStatus = 'Benchmark complete!';
        });
      },
    );

    await for (final update in stream) {
      setState(() {
        _currentStatus = update;
        _logs.add(update);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kokoro TTS Benchmark'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRunning ? null : _checkModelStatus,
            tooltip: 'Re-scan model directory',
          ),
        ],
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 12),
                  if (_isRunning) _buildUiFluidityIndicator(),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: (_modelPaths == null || _isRunning)
                        ? null
                        : _runBenchmark,
                    icon: const Icon(Icons.speed),
                    label: Text(_isRunning
                        ? 'Benchmarking...'
                        : 'Run On-Device Benchmark'),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _result != null
                        ? _buildResultsView(_result!)
                        : _buildLogsView(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final hasModel = _modelPaths != null;
    return Card(
      color: hasModel ? Colors.green.shade50 : Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasModel ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: hasModel ? Colors.green.shade800 : Colors.amber.shade900,
                ),
                const SizedBox(width: 8),
                Text(
                  hasModel ? 'Model Ready' : 'Model Missing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasModel ? Colors.green.shade900 : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_currentStatus),
            if (!hasModel && _targetDirectory != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Target Directory on Device:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              SelectableText(
                _targetDirectory!.path,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Visual proof that the UI thread stays 60fps / responsive during synthesis.
  Widget _buildUiFluidityIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          RotationTransition(
            turns: _spinnerController,
            child: const Icon(Icons.sync, color: Colors.blue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'UI Thread Alive & Fluid (Synthesis running in background Isolate)',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: _logs.isEmpty
          ? const Center(
              child: Text(
                'Press "Run On-Device Benchmark" to test model load time and real-time factor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Text(
                  _logs[i],
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
    );
  }

  Widget _buildResultsView(BenchmarkSuiteResult result) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model Load Times (${result.isInt8 ? "INT8" : "FP32"})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  Text('• 2 Threads: ${result.modelLoadTime2ThreadsMs} ms'),
                  Text('• 4 Threads: ${result.modelLoadTime4ThreadsMs} ms'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Phrase Synthesis & Real-Time Factor (RTF):',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Phrase')),
                DataColumn(label: Text('Threads')),
                DataColumn(label: Text('Run')),
                DataColumn(label: Text('Synth (ms)')),
                DataColumn(label: Text('Audio (s)')),
                DataColumn(label: Text('RTF')),
              ],
              rows: result.records.map((r) {
                return DataRow(
                  cells: [
                    DataCell(Text(r.phraseLabel)),
                    DataCell(Text('${r.threads}')),
                    DataCell(Text(r.isCold ? '#${r.runNumber} (Cold)' : '#${r.runNumber}')),
                    DataCell(Text('${r.synthesisTimeMs}')),
                    DataCell(Text(r.audioDurationSeconds.toStringAsFixed(2))),
                    DataCell(
                      Text(
                        '${r.realTimeFactor.toStringAsFixed(2)}x',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: r.realTimeFactor < 1.0 ? Colors.green : Colors.deepOrange,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
