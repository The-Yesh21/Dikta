import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_config.dart';
import 'package:dictation_app/core/chunker/chunk_info.dart';
import 'package:dictation_app/core/chunker/text_chunker.dart';
import 'package:dictation_app/core/pacing/pacing_engine.dart';

void main() {
  test('Simulate 10-minute dictation session and print table', () {
    const chunker = TextChunker();

    const sampleNote = '''
Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the biochemical reactions of the cell.
Chemical energy produced by the mitochondria is stored in a small molecule called adenosine triphosphate, or ATP.
Mitochondria contain their own small chromosomes, and generally, genes are inherited only from the mother.
During cellular respiration, glucose and oxygen are converted into carbon dioxide, water, and ATP.
This process begins in the cytoplasm with glycolysis, breaking down one molecule of glucose into two molecules of pyruvate.

Pyruvate then enters the mitochondrial matrix, where it is converted into acetyl-CoA for the citric acid cycle.
The citric acid cycle produces electron carriers, specifically NADH and FADH2, which proceed to the electron transport chain.
As electrons move down the respiratory chain, protons are pumped across the inner mitochondrial membrane into the intermembrane space.
This generates an electrochemical proton gradient across the inner membrane, which drives ATP synthase.
Finally, oxygen acts as the terminal electron acceptor, combining with free protons to produce harmless water molecules.
Without functional mitochondria, complex multicellular life would be unable to sustain the massive energetic requirements of animal tissues.
''';

    final baseChunks = chunker.chunk(sampleNote);
    expect(baseChunks, isNotEmpty);

    var simulatedTime = DateTime(2026, 11, 4, 10, 0, 0);
    final startTime = simulatedTime;

    final engine = PacingEngine(
      clock: () => simulatedTime,
      random: math.Random(42), // Fixed seed for reproducible output
      config: const PacingConfig(
        defaultWritingSpeed: 0.7,
        syntaxPauseCommaSeconds: 0.4,
        syntaxPauseSentenceSeconds: 1.2,
        syntaxPauseParagraphSeconds: 2.5,
        tempo0: 1.0,
        tempoMin: 0.7,
        tauMinutes: 12.0,
        jitterSigma: 0.15,
        minGapSeconds: 0.3,
        fatigueStrength: 1.0,
        sawtoothIntervalMinutes: 5.0,
        sawtoothRecoveryRatio: 0.5,
      ),
    );

    print('\n========================================================================================');
    print('| Chunk # | Elapsed Time |   Tempo   |   Gap (s)   | Words | Boundary Type | Notes / Event      |');
    print('========================================================================================');

    var chunkCounter = 0;
    var baseIdx = 0;

    while (true) {
      final elapsedDuration = simulatedTime.difference(startTime);
      final elapsedSec = elapsedDuration.inSeconds;
      final elapsedMin = elapsedSec ~/ 60;
      final elapsedSecRem = elapsedSec % 60;
      final elapsedStr =
          '${elapsedMin.toString().padLeft(2, '0')}:${elapsedSecRem.toString().padLeft(2, '0')}';

      if (elapsedMin >= 10 && chunkCounter > 0) {
        break;
      }

      final prototypeChunk = baseChunks[baseIdx % baseChunks.length];
      final currentChunk = ChunkInfo(
        index: chunkCounter,
        text: prototypeChunk.text,
        wordCount: prototypeChunk.wordCount,
        boundaryType: prototypeChunk.boundaryType,
      );

      final tempoBefore = engine.currentTempo;
      // Synthesized speech speed ~ 2.5 words/sec
      final speechDuration = currentChunk.wordCount / 2.5;
      final gap = engine.calculateGap(currentChunk, speechDurationSeconds: speechDuration);

      var event = '';
      if (currentChunk.boundaryType == BoundaryType.paragraph) {
        event = 'Paragraph Breath';
      }

      print(
        '|   #${chunkCounter.toString().padLeft(3, '0')}   |    $elapsedStr     |   ${tempoBefore.toStringAsFixed(3)}   |    ${gap.toStringAsFixed(2).padLeft(5)}    |   ${currentChunk.wordCount}   |   ${currentChunk.boundaryType.name.padRight(9)}   | ${event.padRight(18)} |',
      );

      // Advance simulated clock by speech duration + pause gap
      final totalStepSeconds = speechDuration + gap;
      simulatedTime = simulatedTime.add(Duration(milliseconds: (totalStepSeconds * 1000).round()));

      chunkCounter++;
      baseIdx++;
    }

    print('========================================================================================\n');
  });
}
