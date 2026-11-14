import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../config/gnani_config.dart';
import '../../services/tts/gnani_tts_engine.dart';
import '../theme/dikta_theme.dart';

/// Voice audition screen for auditioning, comparing, and selecting Gnani voices
/// across English (en-IN), Hindi (hi-IN), and Kannada (kn-IN).
/// Styled in the Dikta Archival Burgundy Crimson & Antique Gold palette.
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

    try {
      _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
    } catch (_) {}

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
      backgroundColor: DiktaColors.parchmentBackground,
      appBar: AppBar(
        title: const Text(
          'Gnani Voice Audition',
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
      decoration: BoxDecoration(
        color: DiktaColors.goldParchment,
        border: Border(
          bottom: BorderSide(color: DiktaColors.goldBorder.withValues(alpha: 0.8), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'LANGUAGE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: DiktaColors.burgundyPrimary,
                ),
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('English (en-IN)'),
                selected: _selectedLanguage == 'en-IN',
                selectedColor: DiktaColors.burgundyPrimary,
                backgroundColor: DiktaColors.cardSurface,
                side: BorderSide(
                  color: _selectedLanguage == 'en-IN' ? DiktaColors.burgundyPrimary : DiktaColors.goldBorder,
                ),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: _selectedLanguage == 'en-IN' ? FontWeight.bold : FontWeight.w500,
                  color: _selectedLanguage == 'en-IN' ? Colors.white : DiktaColors.inkPrimary,
                ),
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
                selectedColor: DiktaColors.burgundyPrimary,
                backgroundColor: DiktaColors.cardSurface,
                side: BorderSide(
                  color: _selectedLanguage == 'hi-IN' ? DiktaColors.burgundyPrimary : DiktaColors.goldBorder,
                ),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: _selectedLanguage == 'hi-IN' ? FontWeight.bold : FontWeight.w500,
                  color: _selectedLanguage == 'hi-IN' ? Colors.white : DiktaColors.inkPrimary,
                ),
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
                selectedColor: DiktaColors.burgundyPrimary,
                backgroundColor: DiktaColors.cardSurface,
                side: BorderSide(
                  color: _selectedLanguage == 'kn-IN' ? DiktaColors.burgundyPrimary : DiktaColors.goldBorder,
                ),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: _selectedLanguage == 'kn-IN' ? FontWeight.bold : FontWeight.w500,
                  color: _selectedLanguage == 'kn-IN' ? Colors.white : DiktaColors.inkPrimary,
                ),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'VOICE SPEED',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: DiktaColors.burgundyPrimary,
                ),
              ),
              const SizedBox(width: 10),
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
                    selectedColor: DiktaColors.goldLight,
                    backgroundColor: DiktaColors.cardSurface,
                    checkmarkColor: DiktaColors.burgundyPrimary,
                    side: BorderSide(
                      color: _selectedSpeed == spd ? DiktaColors.goldAntique : DiktaColors.goldBorder,
                      width: _selectedSpeed == spd ? 1.5 : 1.0,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: _selectedSpeed == spd ? FontWeight.bold : FontWeight.normal,
                      color: _selectedSpeed == spd ? DiktaColors.burgundyPrimary : DiktaColors.inkSecondary,
                    ),
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
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      elevation: 0,
      color: DiktaColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: DiktaColors.goldBorder, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_quote, size: 16, color: DiktaColors.goldAntique),
                const SizedBox(width: 6),
                Text(
                  'SAMPLE SENTENCE FOR AUDITION',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: DiktaColors.burgundyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                height: 1.4,
                color: DiktaColors.inkPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DiktaColors.burgundySoft,
        border: Border.all(color: DiktaColors.crimsonAccent.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: DiktaColors.crimsonAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: DiktaColors.burgundyDeep, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyIndicator() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: DiktaColors.goldParchment,
        border: Border(
          bottom: BorderSide(color: DiktaColors.goldBorder.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Text(
        _lastLatencyText!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: DiktaColors.goldDark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildVoiceCard(GnaniVoiceInfo v) {
    final isPlaying = _currentlyPlayingVoice == v.name;
    final isSelected = _activeVoiceName == v.name;
    final isFemale = v.gender.toLowerCase() == 'female';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: isPlaying ? 2 : 0,
      color: DiktaColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? const BorderSide(color: DiktaColors.goldAntique, width: 2)
            : isPlaying
                ? const BorderSide(color: DiktaColors.crimsonAccent, width: 2)
                : const BorderSide(color: DiktaColors.borderHairline, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isFemale ? DiktaColors.burgundySoft : DiktaColors.goldLight,
          child: Icon(
            isFemale ? Icons.face_3 : Icons.face,
            color: isFemale ? DiktaColors.burgundyPrimary : DiktaColors.goldDark,
          ),
        ),
        title: Row(
          children: [
            Text(
              v.name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: DiktaColors.inkPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isFemale ? DiktaColors.burgundySoft : DiktaColors.goldParchment,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isFemale
                      ? DiktaColors.burgundyPrimary.withValues(alpha: 0.3)
                      : DiktaColors.goldBorder,
                ),
              ),
              child: Text(
                v.gender,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isFemale ? DiktaColors.burgundyPrimary : DiktaColors.goldDark,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: DiktaColors.parchmentBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: DiktaColors.borderHairline),
              ),
              child: Text(
                v.model,
                style: const TextStyle(fontSize: 10.5, color: DiktaColors.inkSecondary),
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DiktaColors.goldAntique,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: DiktaColors.goldAntique.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            v.description,
            style: const TextStyle(fontSize: 12, color: DiktaColors.inkMuted),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: isPlaying
                  ? (_isSynthesizing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(DiktaColors.burgundyPrimary),
                          ),
                        )
                      : const Icon(Icons.stop_circle, color: DiktaColors.crimsonAccent, size: 32))
                  : const Icon(Icons.play_circle_fill, color: DiktaColors.burgundyPrimary, size: 32),
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
              icon: const Icon(Icons.more_vert, color: DiktaColors.inkSecondary),
              color: DiktaColors.cardSurface,
              onSelected: (val) {
                if (val == 'select') {
                  setState(() {
                    _activeVoiceName = v.name;
                  });
                  widget.onSelectVoice?.call(v.name, _selectedLanguage);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: DiktaColors.burgundyDeep,
                      content: Text(
                        'Selected "${v.name}" as default voice for $_selectedLanguage',
                        style: const TextStyle(color: DiktaColors.goldLight),
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'select',
                  child: Row(
                    children: [
                      Icon(Icons.star_outline, size: 18, color: DiktaColors.goldAntique),
                      SizedBox(width: 8),
                      Text('Set as Default Voice', style: TextStyle(color: DiktaColors.inkPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
