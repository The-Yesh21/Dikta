import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../config/gnani_config.dart';
import '../../services/tts/gnani_tts_engine.dart';

/// Voice audition screen for auditioning, comparing, and selecting Gnani voices
/// across English (en-IN), Hindi (hi-IN), and Kannada (kn-IN).
class VoiceAuditionScreen extends StatefulWidget {
  const VoiceAuditionScreen({
    super.key,
    this.onSelectVoice,
    this.selectedVoiceName = 'Shivani',
    this.selectedLanguage = 'en-IN',
  });

  final void Function(String voiceName, String language)? onSelectVoice;
  final String selectedVoiceName;
  final String selectedLanguage;

  @override
  State<VoiceAuditionScreen> createState() => _VoiceAuditionScreenState();
}

class _VoiceAuditionScreenState extends State<VoiceAuditionScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  late final GnaniTtsEngine _ttsEngine;

  String _selectedLanguage = 'en-IN';
  late String _activeVoiceName;
  double _selectedSpeed = 1.0;

  // Audition state
  String? _currentlyPlayingVoice;
  bool _isSynthesizing = false;
  String? _lastLatencyText;
  String? _errorMessage;
  StreamSubscription<void>? _playerCompleteSub;

  // 3 sample sentences for the 3 target languages
  static const Map<String, String> sampleSentences = {
    'en-IN':
        'Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the cell.',
    'hi-IN':
        'प्रकाश संश्लेषण एक ऐसी जैविक प्रक्रिया है जिसके द्वारा हरे पौधे सूर्य के प्रकाश से ऊर्जा बनाते हैं।',
    'kn-IN':
        'ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆಯು ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕು, ನೀರು ಮತ್ತು ಇಂಗಾಲದ ಡೈಆಕ್ಸೈಡ್ ಬಳಸಿ ಆಹಾರ ತಯಾರಿಸುವ ಪ್ರಕ್ರಿಯೆಯಾಗಿದೆ.',
  };

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.selectedLanguage;
    _activeVoiceName = widget.selectedVoiceName;
    _ttsEngine = GnaniTtsEngine();

    _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyPlayingVoice = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _playerCompleteSub?.cancel();
    _audioPlayer.dispose();
    _ttsEngine.dispose();
    super.dispose();
  }

  Future<void> _playAudition(GnaniVoiceInfo voiceInfo) async {
    await _audioPlayer.stop();

    setState(() {
      _currentlyPlayingVoice = voiceInfo.name;
      _isSynthesizing = true;
      _errorMessage = null;
      _lastLatencyText = null;
    });

    final sentence = sampleSentences[_selectedLanguage] ?? sampleSentences['en-IN']!;
    final stopwatch = Stopwatch()..start();

    try {
      final audio = await _ttsEngine.synthesize(
        sentence,
        voice: voiceInfo.name,
        language: _selectedLanguage,
        model: voiceInfo.model,
        speed: _selectedSpeed,
      );
      stopwatch.stop();

      final elapsedMs = stopwatch.elapsedMilliseconds;
      final source = audio.isFromCache ? '⚡ Cache' : '☁️ API';
      _lastLatencyText = '$source (${elapsedMs}ms, ${audio.durationSeconds.toStringAsFixed(1)}s audio)';

      if (audio.audioFilePath != null) {
        await _audioPlayer.play(DeviceFileSource(audio.audioFilePath!));
      } else if (audio.wavBytes != null) {
        await _audioPlayer.play(BytesSource(audio.wavBytes!, mimeType: 'audio/wav'));
      }

      if (mounted) {
        setState(() {
          _isSynthesizing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSynthesizing = false;
          _currentlyPlayingVoice = null;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final voices = GnaniVoiceCatalog.getVoicesForLanguage(_selectedLanguage);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gnani Voice Audition'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildLanguageAndSpeedBar(),
          _buildSentenceCard(),
          if (_errorMessage != null) _buildErrorBanner(),
          if (_lastLatencyText != null) _buildLatencyIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: voices.length,
              itemBuilder: (context, index) {
                final v = voices[index];
                return _buildVoiceCard(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageAndSpeedBar() {
    return Container(
      color: Colors.teal.shade50,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Language: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('English (en-IN)'),
                selected: _selectedLanguage == 'en-IN',
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedLanguage = 'en-IN';
                    });
                  }
                },
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Hindi (hi-IN)'),
                selected: _selectedLanguage == 'hi-IN',
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedLanguage = 'hi-IN';
                    });
                  }
                },
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Kannada (kn-IN)'),
                selected: _selectedLanguage == 'kn-IN',
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _selectedLanguage = 'kn-IN';
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Voice Speed: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              for (final spd in [0.85, 1.0, 1.15])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      spd == 0.85
                          ? '0.85x (Slow)'
                          : spd == 1.0
                              ? '1.0x (Normal)'
                              : '1.15x (Fast)',
                    ),
                    selected: _selectedSpeed == spd,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedSpeed = spd;
                        });
                      }
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceCard() {
    final text = sampleSentences[_selectedLanguage] ?? sampleSentences['en-IN']!;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sample Sentence for Audition:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyIndicator() {
    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        _lastLatencyText!,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVoiceCard(GnaniVoiceInfo v) {
    final isPlaying = _currentlyPlayingVoice == v.name;
    final isSelected = _activeVoiceName == v.name;
    final isFemale = v.gender.toLowerCase() == 'female';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: isPlaying ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? const BorderSide(color: Colors.teal, width: 2)
            : isPlaying
                ? const BorderSide(color: Colors.blue, width: 2)
                : BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isFemale ? Colors.pink.shade100 : Colors.indigo.shade100,
          child: Icon(
            isFemale ? Icons.face_3 : Icons.face,
            color: isFemale ? Colors.pink.shade800 : Colors.indigo.shade800,
          ),
        ),
        title: Row(
          children: [
            Text(
              v.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isFemale ? Colors.pink.shade50 : Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isFemale ? Colors.pink.shade200 : Colors.indigo.shade200,
                ),
              ),
              child: Text(
                v.gender,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isFemale ? Colors.pink.shade700 : Colors.indigo.shade700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Text(
                v.model,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              const Chip(
                label: Text('Default', style: TextStyle(fontSize: 11, color: Colors.white)),
                backgroundColor: Colors.teal,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(v.description, style: const TextStyle(fontSize: 12)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: isPlaying
                  ? (_isSynthesizing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop_circle, color: Colors.red, size: 30))
                  : const Icon(Icons.play_circle_fill, color: Colors.teal, size: 30),
              tooltip: 'Audition voice',
              onPressed: () {
                if (isPlaying) {
                  _audioPlayer.stop();
                  setState(() {
                    _currentlyPlayingVoice = null;
                  });
                } else {
                  _playAudition(v);
                }
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'select') {
                  setState(() {
                    _activeVoiceName = v.name;
                  });
                  widget.onSelectVoice?.call(v.name, _selectedLanguage);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selected "${v.name}" as default voice for $_selectedLanguage')),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'select',
                  child: Text('Set as Default Voice'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
