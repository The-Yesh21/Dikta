import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../services/audio/temp_audio_file_manager.dart';
import '../../services/tts/kokoro_engine.dart';
import '../../services/tts/model_locator.dart';

class WordPronunciationItem {
  const WordPronunciationItem({
    required this.word,
    required this.inLexicon,
    required this.phonemes,
    required this.gSoundType,
    required this.note,
  });

  final String word;
  final bool inLexicon;
  final String phonemes;
  final String gSoundType;
  final String note;
}

/// Diagnostic debug screen for evaluating G sounds and OOV words in Kokoro TTS.
class PronunciationDebugScreen extends StatefulWidget {
  const PronunciationDebugScreen({super.key});

  @override
  State<PronunciationDebugScreen> createState() => _PronunciationDebugScreenState();
}

class _PronunciationDebugScreenState extends State<PronunciationDebugScreen> {
  final ModelLocator _modelLocator = const ExternalStorageModelLocator();
  final TempAudioFileManager _tempFileManager = TempAudioFileManager();
  final AudioPlayer _audioPlayer = AudioPlayer();

  KokoroEngine? _engine;
  bool _isEngineReady = false;
  bool _isInitializing = true;
  String _statusMessage = 'Initializing engine for pronunciation diagnosis...';

  int _selectedSpeakerId = 0;
  double _playbackSpeed = 0.8;
  String? _currentlySpeakingWord;
  StreamSubscription<void>? _playerCompleteSub;

  static const List<WordPronunciationItem> diagnosticWords = [
    WordPronunciationItem(
      word: 'get',
      inLexicon: true,
      phonemes: 'ɡ ɛ t',
      gSoundType: 'Hard G (ɡ)',
      note: 'Starts with plosive hard G',
    ),
    WordPronunciationItem(
      word: 'gene',
      inLexicon: true,
      phonemes: 'ʤ ˈ i n',
      gSoundType: 'Soft G (ʤ / "j")',
      note: 'Starts with affricate soft G',
    ),
    WordPronunciationItem(
      word: 'give',
      inLexicon: true,
      phonemes: 'ɡ ˈ ɪ v',
      gSoundType: 'Hard G (ɡ)',
      note: 'Starts with plosive hard G',
    ),
    WordPronunciationItem(
      word: 'giant',
      inLexicon: true,
      phonemes: 'ʤ ˈ I ə n t',
      gSoundType: 'Soft G (ʤ / "j")',
      note: 'Starts with affricate soft G',
    ),
    WordPronunciationItem(
      word: 'generate',
      inLexicon: true,
      phonemes: 'ʤ ˈ ɛ n ə ɹ ˌ A t',
      gSoundType: 'Soft G (ʤ / "j")',
      note: 'Starts with affricate soft G',
    ),
    WordPronunciationItem(
      word: 'glucose',
      inLexicon: true,
      phonemes: 'ɡ l ˈ u k ˌ O s',
      gSoundType: 'Hard G (ɡ)',
      note: 'Starts with plosive hard G cluster "gl"',
    ),
    WordPronunciationItem(
      word: 'gradient',
      inLexicon: true,
      phonemes: 'ɡ ɹ ˈ A d i ə n t',
      gSoundType: 'Hard G (ɡ)',
      note: 'Starts with plosive hard G cluster "gr"',
    ),
    WordPronunciationItem(
      word: 'gravity',
      inLexicon: true,
      phonemes: 'ɡ ɹ ˈ æ v ə ɾ i',
      gSoundType: 'Hard G (ɡ)',
      note: 'Starts with plosive hard G cluster "gr"',
    ),
    WordPronunciationItem(
      word: 'genes',
      inLexicon: true,
      phonemes: 'ʤ ˈ i n z',
      gSoundType: 'Soft G (ʤ / "j")',
      note: 'Starts with affricate soft G',
    ),
    WordPronunciationItem(
      word: 'glycolysis',
      inLexicon: true,
      phonemes: 'ɡ l I k ˈ ɑ l ə s ɪ s',
      gSoundType: 'Hard G (ɡ)',
      note: 'Technical term, in lexicon-us-en.txt',
    ),
    WordPronunciationItem(
      word: 'mitochondria',
      inLexicon: true,
      phonemes: 'm ˌ I ɾ ə k ˈ ɑ n d ɹ i ə',
      gSoundType: 'N/A',
      note: 'In lexicon-us-en.txt',
    ),
    WordPronunciationItem(
      word: 'ATP',
      inLexicon: false,
      phonemes: '[OOV - No Lexicon Match]',
      gSoundType: 'Acronym',
      note: 'Missing from lexicon-us-en.txt! Model spells or guesses',
    ),
    WordPronunciationItem(
      word: 'NADH',
      inLexicon: false,
      phonemes: '[OOV - No Lexicon Match]',
      gSoundType: 'Acronym',
      note: 'Missing from lexicon-us-en.txt! Model spells or guesses',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    setState(() {
      _isInitializing = true;
      _statusMessage = 'Locating Kokoro model & lexicon...';
    });

    final modelPaths = await _modelLocator.locateKokoroModel();
    if (modelPaths == null) {
      setState(() {
        _isInitializing = false;
        _isEngineReady = false;
        _statusMessage = 'Model files not found in app storage.';
      });
      return;
    }

    try {
      final engine = KokoroEngine();
      await engine.init(modelPaths, numThreads: 4);

      _playerCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _currentlySpeakingWord = null;
        });
      });

      setState(() {
        _engine = engine;
        _isEngineReady = true;
        _isInitializing = false;
        _statusMessage = 'Model ready (lexicon: ${modelPaths.lexiconPath != null ? "lexicon-us-en.txt" : "none"})';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _isEngineReady = false;
        _statusMessage = 'Init error: $e';
      });
    }
  }

  Future<void> _speakWord(String word) async {
    if (_engine == null || !_isEngineReady) return;

    await _audioPlayer.stop();

    setState(() {
      _currentlySpeakingWord = word;
    });

    try {
      final audio = await _engine!.synthesize(
        word,
        speakerId: _selectedSpeakerId,
        speed: _playbackSpeed,
      );

      final tempWav = await _tempFileManager.writeTempWave(
        samples: audio.samples,
        sampleRate: audio.sampleRate,
        chunkIndex: 8888,
      );

      await _audioPlayer.play(DeviceFileSource(tempWav));
    } catch (e) {
      if (mounted) {
        setState(() => _currentlySpeakingWord = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to speak "$word": $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _playerCompleteSub?.cancel();
    _audioPlayer.dispose();
    _tempFileManager.cleanupAll();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pronunciation Diagnosis'),
        elevation: 1,
      ),
      body: Column(
        children: [
          // Header status & controls
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.deepPurple.shade50,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _isEngineReady ? Icons.check_circle : Icons.info,
                      color: _isEngineReady ? Colors.green : Colors.amber.shade900,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Voice:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _selectedSpeakerId,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('[#0] af (US Female)')),
                        DropdownMenuItem(value: 7, child: Text('[#7] Emma (UK Female 🇬🇧)')),
                        DropdownMenuItem(value: 8, child: Text('[#8] Isabella (UK Female 🇬🇧)')),
                        DropdownMenuItem(value: 9, child: Text('[#9] George (UK Male 🇬🇧)')),
                        DropdownMenuItem(value: 10, child: Text('[#10] Lewis (UK Male 🇬🇧)')),
                        DropdownMenuItem(value: 5, child: Text('[#5] Adam (US Male)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedSpeakerId = val);
                      },
                    ),
                    const Spacer(),
                    const Text('Speed:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 6),
                    DropdownButton<double>(
                      value: _playbackSpeed,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 0.7, child: Text('0.7x')),
                        DropdownMenuItem(value: 0.8, child: Text('0.8x')),
                        DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _playbackSpeed = val);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Diagnostic word list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12.0),
              itemCount: diagnosticWords.length,
              separatorBuilder: (_, __) => const Divider(height: 6),
              itemBuilder: (ctx, i) {
                final item = diagnosticWords[i];
                final isSpeaking = _currentlySpeakingWord == item.word;

                return Card(
                  elevation: isSpeaking ? 3 : 1,
                  color: item.inLexicon ? Colors.white : Colors.amber.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: item.inLexicon ? Colors.grey.shade300 : Colors.amber.shade700,
                      width: item.inLexicon ? 1 : 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    child: Row(
                      children: [
                        // Speak button
                        IconButton(
                          icon: Icon(
                            isSpeaking ? Icons.volume_up : Icons.play_circle_outline,
                            color: isSpeaking ? Colors.green : Colors.deepPurple,
                            size: 32,
                          ),
                          onPressed: !_isEngineReady ? null : () => _speakWord(item.word),
                        ),
                        const SizedBox(width: 8),

                        // Word details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    item.word,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: item.inLexicon ? Colors.green.shade100 : Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.inLexicon ? 'IN LEXICON' : 'OOV (MISSING)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: item.inLexicon ? Colors.green.shade900 : Colors.red.shade900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    item.gSoundType,
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Phonemes: ${item.phonemes}',
                                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: Colors.indigo),
                              ),
                              Text(
                                item.note,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
