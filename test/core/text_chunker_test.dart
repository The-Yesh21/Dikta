import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/config/pacing_config.dart';
import 'package:dictation_app/core/chunker/chunk_info.dart';
import 'package:dictation_app/core/chunker/text_chunker.dart';

void main() {
  const chunker = TextChunker();

  group('TextChunker Edge Cases', () {
    test('returns empty list for empty string', () {
      expect(chunker.chunk(''), isEmpty);
    });

    test('returns empty list for whitespace-only strings', () {
      expect(chunker.chunk('   \n\t  \r\n '), isEmpty);
    });

    test('handles single word without crash', () {
      final chunks = chunker.chunk('Hello');
      expect(chunks.length, equals(1));
      expect(chunks.first.text, equals('Hello'));
      expect(chunks.first.wordCount, equals(1));
      expect(chunks.first.boundaryType, equals(BoundaryType.sentence));
    });

    test('handles two words without crash', () {
      final chunks = chunker.chunk('Hello world.');
      expect(chunks.length, equals(1));
      expect(chunks.first.text, equals('Hello world.'));
      expect(chunks.first.wordCount, equals(2));
      expect(chunks.first.boundaryType, equals(BoundaryType.sentence));
    });

    test('sequential chunk indices start at 0 and increment by 1', () {
      final chunks = chunker.chunk(
        'First short sentence. Second short sentence. Third short sentence.',
      );
      expect(chunks.length, equals(3));
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].index, equals(i));
      }
    });
  });

  group('TextChunker Phrase & Boundary Splitting', () {
    test('short sentence within word limit remains a single chunk', () {
      final chunks = chunker.chunk('Water boils at one hundred degrees.');
      expect(chunks.length, equals(1));
      expect(chunks.first.text, equals('Water boils at one hundred degrees.'));
      expect(chunks.first.wordCount, equals(6));
      expect(chunks.first.boundaryType, equals(BoundaryType.sentence));
    });

    test('splits at comma when within word bounds', () {
      final chunks = chunker.chunk(
        'When the sun rises, the birds start singing in the morning.',
      );
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('When the sun rises,'));
      expect(chunks[0].boundaryType, equals(BoundaryType.comma));
      expect(chunks[0].wordCount, equals(4));

      expect(chunks[1].text, equals('the birds start singing in the morning.'));
      expect(chunks[1].boundaryType, equals(BoundaryType.sentence));
      expect(chunks[1].wordCount, equals(7));
    });

    test('forces split on long sentences with no punctuation', () {
      const longText =
          'Photosynthesis is the biological process used by plants to convert light into biochemical energy';
      final chunks = chunker.chunk(longText);

      expect(chunks.length, greaterThan(1));
      for (var i = 0; i < chunks.length - 1; i++) {
        expect(chunks[i].boundaryType, equals(BoundaryType.none));
        expect(
          chunks[i].wordCount,
          inInclusiveRange(PacingConfig.defaultConfig.minWordsPerChunk,
              PacingConfig.defaultConfig.maxWordsPerChunk),
        );
      }
      expect(chunks.last.boundaryType, equals(BoundaryType.sentence));
    });

    test('marks end of paragraph with BoundaryType.paragraph', () {
      const multiParagraphText =
          'This is the first paragraph with some notes.\n\nThis is the second paragraph with more notes.';
      final chunks = chunker.chunk(multiParagraphText);

      expect(chunks.length, equals(2));
      expect(chunks[0].boundaryType, equals(BoundaryType.paragraph));
      expect(chunks[1].boundaryType, equals(BoundaryType.sentence));
    });
  });

  group('TextChunker Advanced Formatting & Abbreviations', () {
    test('does not split sentences on common abbreviations', () {
      final chunks = chunker.chunk(
        'Dr. Smith arrived at 8 a.m. to give the special lecture.',
      );
      expect(chunks.length, inInclusiveRange(1, 2));
      expect(chunks.any((c) => c.text.startsWith('Dr.')), isTrue);
    });

    test('does not split on decimal numbers', () {
      final chunks = chunker.chunk(
        'The value of pi is approximately 3.14159 in Euclidean geometry.',
      );
      expect(chunks.any((c) => c.text.contains('3.14159')), isTrue);
    });
  });

  group('TextChunker Step 2b Linguistic Regression Tests', () {
    test('English: avoids ending chunks on prepositions/articles (the, a, to, into)', () {
      const sentence1 =
          'Mitochondria are membrane-bound cell organelles that generate most of the chemical energy needed to power the biochemical reactions of the cell.';
      final chunks1 = chunker.chunk(sentence1);
      for (final c in chunks1) {
        final words = c.text.split(' ');
        final last = words.last.replaceAll(RegExp(r'[^\w]+'), '').toLowerCase();
        expect(last, isNot(isIn(['the', 'a', 'to', 'into', 'of', 'in'])),
            reason: 'Chunk "${c.text}" should not end on a dangling function word');
      }

      const sentence2 =
          'Chemical energy produced by the mitochondria is stored in a small molecule called adenosine triphosphate, or ATP.';
      final chunks2 = chunker.chunk(sentence2);
      for (final c in chunks2) {
        final words = c.text.split(' ');
        final last = words.last.replaceAll(RegExp(r'[^\w]+'), '').toLowerCase();
        expect(last, isNot(isIn(['the', 'a', 'in', 'to'])),
            reason: 'Chunk "${c.text}" should not end on dangling "a" or "in"');
      }

      const sentence3 =
          'Pyruvate then enters the mitochondrial matrix, where it is converted into acetyl-CoA for the citric acid cycle.';
      final chunks3 = chunker.chunk(sentence3);
      for (final c in chunks3) {
        final words = c.text.split(' ');
        final last = words.last.replaceAll(RegExp(r'[^\w]+'), '').toLowerCase();
        expect(last, isNot(isIn(['into', 'for', 'the', 'is'])),
            reason: 'Chunk "${c.text}" should not end on "into" or "is"');
      }

      const sentence4 =
          'Without functional mitochondria, complex multicellular life would be unable to sustain the massive energetic requirements of animal tissues.';
      final chunks4 = chunker.chunk(sentence4);
      for (final c in chunks4) {
        final words = c.text.split(' ');
        final last = words.last.replaceAll(RegExp(r'[^\w]+'), '').toLowerCase();
        expect(last, isNot(isIn(['to', 'of', 'be'])),
            reason: 'Chunk "${c.text}" should not end on "to"');
      }
    });

    test('Hindi: avoids starting chunks with postposition (से, में, को) and ending with genitive (के, का)', () {
      const hindiSentence1 =
          'इस प्रक्रिया में पौधे वायुमंडल से कार्बन डाइऑक्साइड और मिट्टी से जल अवशोषित करते हैं।';
      final chunks1 = chunker.chunk(hindiSentence1);
      for (var i = 0; i < chunks1.length; i++) {
        final words = chunks1[i].text.split(' ');
        final first = words.first.replaceAll(RegExp(r'[^\w\u0900-\u097F]+'), '');
        final last = words.last.replaceAll(RegExp(r'[^\w\u0900-\u097F]+'), '');

        expect(first, isNot(isIn(['से', 'में', 'को', 'पर', 'का', 'के', 'की'])),
            reason: 'Chunk "${chunks1[i].text}" should not start on postposition "$first"');
        if (i < chunks1.length - 1) {
          expect(last, isNot(isIn(['का', 'के', 'की', 'इस', 'उस'])),
              reason: 'Chunk "${chunks1[i].text}" should not end on function word "$last"');
        }
      }

      const hindiSentence2 =
          'इस चरण में जल के अणुओं का प्रकाशिक अपघटन होता है, जिससे ऑक्सीजन गैस मुक्त होकर वायुमंडल में फैल जाती है।';
      final chunks2 = chunker.chunk(hindiSentence2);
      for (var i = 0; i < chunks2.length; i++) {
        final words = chunks2[i].text.split(' ');
        final first = words.first.replaceAll(RegExp(r'[^\w\u0900-\u097F]+'), '');
        final last = words.last.replaceAll(RegExp(r'[^\w\u0900-\u097F]+'), '');

        expect(first, isNot(isIn(['से', 'में', 'को', 'पर', 'का', 'के', 'की'])),
            reason: 'Chunk "${chunks2[i].text}" should not start on postposition "$first"');
        if (i < chunks2.length - 1) {
          expect(last, isNot(isIn(['का', 'के', 'की'])),
              reason: 'Chunk "${chunks2[i].text}" should not end on genitive marker "के"');
        }
      }
    });

    test('English: avoids ending chunks on modal verbs (would, could, should, can, will, etc.)', () {
      const sentence =
          'Complex multicellular life would be unable to sustain the massive energetic requirements.';
      final chunks = chunker.chunk(sentence);
      for (final c in chunks) {
        final words = c.text.split(' ');
        final last = words.last.replaceAll(RegExp(r'[^\w]+'), '').toLowerCase();
        expect(
          last,
          isNot(isIn(['would', 'could', 'should', 'can', 'will', 'may', 'might', 'must', 'be', 'been'])),
          reason: 'Chunk "${c.text}" should not end on a modal or helper verb',
        );
      }
    });

    test('Kannada: avoids ending chunks on conjunctions/articles/pronouns (ಮತ್ತು, ಅಥವಾ, ಈ, ಆ, ಒಂದು, ಎಲ್ಲಾ)', () {
      const kannadaSentence =
          'ದ್ಯುತಿಸಂಶ್ಲೇಷಣೆಯು ಸಸ್ಯಗಳು ಸೂರ್ಯನ ಬೆಳಕಿನ ಶಕ್ತಿಯನ್ನು ರಾಸಾಯನಿಕ ಶಕ್ತಿಯನ್ನಾಗಿ ಪರಿವರ್ತಿಸುವ ಒಂದು ಪ್ರಮುಖ ಜೈವಿಕ ಪ್ರಕ್ರಿಯೆಯಾಗಿದೆ.';
      final chunks = chunker.chunk(kannadaSentence);
      for (var i = 0; i < chunks.length - 1; i++) {
        final words = chunks[i].text.split(' ');
        final last = words.last.replaceAll(RegExp(r'[^\w\u0C80-\u0CFF]+'), '');
        expect(last, isNot(isIn(['ಮತ್ತು', 'ಅಥವಾ', 'ಈ', 'ಆ', 'ಒಂದು', 'ಎಲ್ಲಾ'])),
            reason: 'Kannada chunk "${chunks[i].text}" should not end on "$last"');
      }
    });
  });

  group('TextChunker Multilingual & Script Support', () {
    test('splits Hindi / Devanagari text using purna viram danda', () {
      const hindiText =
          'यह पहला महत्वपूर्ण वाक्य है। दूसरा वाक्य यहाँ से शुरू होता है।';
      final chunks = chunker.chunk(hindiText);

      expect(chunks.length, equals(2));
      expect(chunks[0].text, contains('यह पहला महत्वपूर्ण वाक्य है।'));
      expect(chunks[0].boundaryType, equals(BoundaryType.sentence));
      expect(chunks[1].text, contains('दूसरा वाक्य यहाँ से शुरू होता है।'));
      expect(chunks[1].boundaryType, equals(BoundaryType.sentence));
    });

    test('handles Kannada script correctly', () {
      const kannadaText =
          'ಇದು ಮೊದಲನೆಯ ವಾಕ್ಯವಾಗಿದೆ. ಇದು ಎರಡನೆಯ ವಿವರಣಾತ್ಮಕ ವಾಕ್ಯವಾಗಿದೆ.';
      final chunks = chunker.chunk(kannadaText);

      expect(chunks.length, equals(2));
      expect(chunks[0].boundaryType, equals(BoundaryType.sentence));
      expect(chunks[1].boundaryType, equals(BoundaryType.sentence));
    });

    test('mixed scripts do not cause crash or invalid chunk states', () {
      const mixedText =
          'Chapter 1: परिचय ಮತ್ತು basics.\n\nWe start with paragraph one. अगला भाग यहाँ है।';
      final chunks = chunker.chunk(mixedText);

      expect(chunks, isNotEmpty);
      expect(chunks.any((c) => c.boundaryType == BoundaryType.paragraph), isTrue);
      for (final chunk in chunks) {
        expect(chunk.wordCount, greaterThan(0));
        expect(chunk.text.trim(), isNotEmpty);
      }
    });
  });
}
