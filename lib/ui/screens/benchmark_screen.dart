import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/tts/model_locator.dart';
import '../../services/tts/tts_benchmark_runner.dart';
import '../theme/dikta_theme.dart';

/// Screen for running on-device Kokoro TTS benchmarks.
/// Styled in the Dikta Archival Burgundy Crimson & Antique Gold palette.
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
      backgroundColor: DiktaColors.parchmentBackground,
      appBar: AppBar(
        title: const Text(
          'Kokoro TTS Benchmark',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        backgroundColor: DiktaColors.burgundyPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: DiktaColors.goldBorder.withValues(alpha: 0.6),
            height: 1.0,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: DiktaColors.goldLight),
            onPressed: _isRunning ? null : _checkModelStatus,
            tooltip: 'Re-scan model directory',
          ),
        ],
      ),
      body: _isChecking
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(DiktaColors.burgundyPrimary),
              ),
            )
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DiktaColors.burgundyPrimary,
                      foregroundColor: DiktaColors.goldLight,
                      disabledBackgroundColor: DiktaColors.burgundyPrimary.withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white60,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: (_modelPaths == null || _isRunning)
                              ? Colors.transparent
                              : DiktaColors.goldAntique,
                          width: 1.2,
                        ),
                      ),
                    ),
                    onPressed: (_modelPaths == null || _isRunning)
                        ? null
                        : _runBenchmark,
                    icon: Icon(
                      Icons.speed,
                      color: (_modelPaths == null || _isRunning) ? Colors.white60 : DiktaColors.goldBright,
                    ),
                    label: Text(
                      _isRunning ? 'Benchmarking...' : 'Run On-Device Benchmark',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0.3),
                    ),
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
      elevation: 0,
      color: hasModel ? DiktaColors.cardSurface : DiktaColors.goldParchment,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: hasModel ? DiktaColors.goldAntique : DiktaColors.goldBorder,
          width: hasModel ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasModel ? Icons.layers_outlined : Icons.folder_open_outlined,
                  color: hasModel ? DiktaColors.burgundyPrimary : DiktaColors.goldDark,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  hasModel ? 'Model Ready' : 'Model Missing',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: hasModel ? DiktaColors.burgundyPrimary : DiktaColors.burgundyDeep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _currentStatus,
              style: const TextStyle(color: DiktaColors.inkPrimary, height: 1.3, fontSize: 13),
            ),
            if (!hasModel && _targetDirectory != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Target Directory on Device:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: DiktaColors.burgundyPrimary,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                _targetDirectory!.path,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: DiktaColors.inkSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: DiktaColors.goldParchment,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DiktaColors.goldBorder),
      ),
      child: Row(
        children: [
          RotationTransition(
            turns: _spinnerController,
            child: const Icon(Icons.sync, color: DiktaColors.burgundyPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'UI Thread Alive & Fluid (Synthesis running in background Isolate)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: DiktaColors.burgundyPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsView() {
    return Container(
      decoration: BoxDecoration(
        color: DiktaColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DiktaColors.borderHairline),
      ),
      padding: const EdgeInsets.all(12),
      child: _logs.isEmpty
          ? const Center(
              child: Text(
                'Press "Run On-Device Benchmark" to test model load time and real-time factor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DiktaColors.inkMuted, fontSize: 13),
              ),
            )
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Text(
                  _logs[i],
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: DiktaColors.inkPrimary,
                  ),
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
            elevation: 0,
            color: DiktaColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: DiktaColors.goldBorder, width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model Load Times (${result.isInt8 ? "INT8" : "FP32"})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: DiktaColors.burgundyPrimary,
                    ),
                  ),
                  const Divider(color: DiktaColors.borderHairline, height: 18),
                  Text(
                    '• 2 Threads: ${result.modelLoadTime2ThreadsMs} ms',
                    style: const TextStyle(color: DiktaColors.inkPrimary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• 4 Threads: ${result.modelLoadTime4ThreadsMs} ms',
                    style: const TextStyle(color: DiktaColors.inkPrimary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Phrase Synthesis & Real-Time Factor (RTF):',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: DiktaColors.burgundyPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Card(
            elevation: 0,
            color: DiktaColors.cardSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: DiktaColors.borderHairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowColor: WidgetStateProperty.all(DiktaColors.goldParchment),
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: DiktaColors.burgundyPrimary,
                    fontSize: 12,
                  ),
                  dataTextStyle: const TextStyle(
                    color: DiktaColors.inkPrimary,
                    fontSize: 12,
                  ),
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
                              color: r.realTimeFactor < 1.0 ? DiktaColors.burgundyPrimary : DiktaColors.goldDark,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
