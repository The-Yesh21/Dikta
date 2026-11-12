import 'package:flutter/material.dart';
import '../../core/pacing/pacing_engine.dart';

/// Live tuning panel for real-time adjustments of dictation pacing and voice parameters.
class LiveTuningPanel extends StatefulWidget {
  const LiveTuningPanel({
    super.key,
    required this.pacingEngine,
    this.onChanged,
  });

  final PacingEngine pacingEngine;
  final VoidCallback? onChanged;

  @override
  State<LiveTuningPanel> createState() => _LiveTuningPanelState();
}

class _LiveTuningPanelState extends State<LiveTuningPanel> {
  late double _secLatin;
  late double _secDevanagari;
  late double _secKannada;
  late double _speechRate;
  late double _commaPause;
  late double _sentencePause;
  late double _paragraphPause;
  late double _fatigueStrength;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  void _loadValues() {
    final pe = widget.pacingEngine;
    _secLatin = pe.getWritingSecondsPerGrapheme(script: ScriptType.latin);
    _secDevanagari = pe.getWritingSecondsPerGrapheme(script: ScriptType.devanagari);
    _secKannada = pe.getWritingSecondsPerGrapheme(script: ScriptType.kannada);
    _speechRate = pe.gnaniSpeechRate;
    _commaPause = pe.commaPause;
    _sentencePause = pe.sentencePause;
    _paragraphPause = pe.paragraphPause;
    _fatigueStrength = pe.fatigueStrength;
  }

  void _notifyChange() {
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final pe = widget.pacingEngine;
    final tempo = pe.currentTempo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Pacing & Voice Tuning'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to Defaults',
            onPressed: () {
              pe.setSecondsPerGrapheme(ScriptType.latin, pe.config.secondsPerGraphemeLatin);
              pe.setSecondsPerGrapheme(ScriptType.devanagari, pe.config.secondsPerGraphemeDevanagari);
              pe.setSecondsPerGrapheme(ScriptType.kannada, pe.config.secondsPerGraphemeKannada);
              pe.gnaniSpeechRate = pe.config.gnaniSpeechRate;
              pe.commaPause = pe.config.syntaxPauseCommaSeconds;
              pe.sentencePause = pe.config.syntaxPauseSentenceSeconds;
              pe.paragraphPause = pe.config.syntaxPauseParagraphSeconds;
              pe.fatigueStrength = pe.config.fatigueStrength;
              pe.reset();
              _loadValues();
              _notifyChange();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLiveStatusCard(tempo),
          const SizedBox(height: 16),
          _buildSectionHeader('Writing Speed (Seconds / Grapheme)'),
          _buildSlider(
            title: 'English (Latin)',
            subtitle: '~${(60 / (_secLatin * 5)).round()} words/min',
            value: _secLatin,
            min: 0.10,
            max: 0.80,
            divisions: 70,
            unit: 's/grapheme',
            onChanged: (val) {
              _secLatin = val;
              pe.setSecondsPerGrapheme(ScriptType.latin, val);
              _notifyChange();
            },
          ),
          _buildSlider(
            title: 'Hindi (Devanagari)',
            subtitle: '~${(60 / (_secDevanagari * 4)).round()} words/min',
            value: _secDevanagari,
            min: 0.15,
            max: 1.00,
            divisions: 85,
            unit: 's/grapheme',
            onChanged: (val) {
              _secDevanagari = val;
              pe.setSecondsPerGrapheme(ScriptType.devanagari, val);
              _notifyChange();
            },
          ),
          _buildSlider(
            title: 'Kannada',
            subtitle: '~${(60 / (_secKannada * 4)).round()} words/min',
            value: _secKannada,
            min: 0.15,
            max: 1.20,
            divisions: 105,
            unit: 's/grapheme',
            onChanged: (val) {
              _secKannada = val;
              pe.setSecondsPerGrapheme(ScriptType.kannada, val);
              _notifyChange();
            },
          ),
          const Divider(height: 32),
          _buildSectionHeader('Gnani Speech Speed (API Parameter)'),
          _buildSlider(
            title: 'Gnani Speech Rate',
            subtitle: 'API audio delivery speed',
            value: _speechRate,
            min: 0.85,
            max: 1.15,
            divisions: 30,
            unit: 'x',
            onChanged: (val) {
              _speechRate = val;
              pe.gnaniSpeechRate = val;
              _notifyChange();
            },
          ),
          const Divider(height: 32),
          _buildSectionHeader('Additive Boundary Pauses'),
          _buildSlider(
            title: 'Comma Pause',
            subtitle: 'Added after clause/comma',
            value: _commaPause,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            unit: 's',
            onChanged: (val) {
              _commaPause = val;
              pe.commaPause = val;
              _notifyChange();
            },
          ),
          _buildSlider(
            title: 'Sentence End Pause',
            subtitle: 'Added after full stop or purna viram',
            value: _sentencePause,
            min: 0.0,
            max: 4.0,
            divisions: 40,
            unit: 's',
            onChanged: (val) {
              _sentencePause = val;
              pe.sentencePause = val;
              _notifyChange();
            },
          ),
          _buildSlider(
            title: 'Paragraph End Pause',
            subtitle: 'Added after paragraph boundary',
            value: _paragraphPause,
            min: 0.0,
            max: 6.0,
            divisions: 60,
            unit: 's',
            onChanged: (val) {
              _paragraphPause = val;
              pe.paragraphPause = val;
              _notifyChange();
            },
          ),
          const Divider(height: 32),
          _buildSectionHeader('Fatigue & Rhythm Engine'),
          _buildSlider(
            title: 'Fatigue Decay Strength',
            subtitle: '0.0 = constant tempo, 1.0 = full gradual decay',
            value: _fatigueStrength,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            unit: '',
            onChanged: (val) {
              _fatigueStrength = val;
              pe.fatigueStrength = val;
              _notifyChange();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusCard(double tempo) {
    return Card(
      elevation: 2,
      color: Colors.teal.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                const Text('Current Tempo', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  '${(tempo * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ],
            ),
            Column(
              children: [
                const Text('Speech Rate', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  '${_speechRate.toStringAsFixed(2)}x',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ],
            ),
            Column(
              children: [
                const Text('Fatigue Factor', style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  _fatigueStrength.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildSlider({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(
                  '${value.toStringAsFixed(2)} $unit',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13),
                ),
              ],
            ),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: Colors.teal,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
