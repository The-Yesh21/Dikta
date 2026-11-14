import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:dictation_app/core/document/document_item.dart';
import 'package:dictation_app/core/document/pdf_document_parser.dart';

void main() {
  group('DocumentItem unit tests', () {
    test('heading factory formats spokenText with Heading prefix and period', () {
      final item1 = DocumentItem.heading(text: 'Cell Biology', fontSize: 18.0);
      expect(item1.itemType, DocumentItemType.heading);
      expect(item1.isHeading, isTrue);
      expect(item1.isParagraph, isFalse);
      expect(item1.isDiagramPlaceholder, isFalse);
      expect(item1.spokenText, 'Heading: Cell Biology.');

      // When text already ends with period, should not append double periods
      final item2 = DocumentItem.heading(text: 'Chapter 1: Introduction.', fontSize: 20.0);
      expect(item2.spokenText, 'Heading: Chapter 1: Introduction.');
    });

    test('paragraph factory preserves text and spokenText', () {
      final item = DocumentItem.paragraph(
        text: 'The cell is the basic structural and functional unit of life.',
        fontSize: 12.0,
      );
      expect(item.itemType, DocumentItemType.paragraph);
      expect(item.isParagraph, isTrue);
      expect(item.isHeading, isFalse);
      expect(item.spokenText, 'The cell is the basic structural and functional unit of life.');
    });

    test('diagram factory calculates note and sets spokenText', () {
      final small = DocumentItem.diagram(relativeHeight: 0.15, linesToLeave: 4);
      expect(small.itemType, DocumentItemType.diagramPlaceholder);
      expect(small.isDiagramPlaceholder, isTrue);
      expect(small.diagramRelativeHeight, 0.15);
      expect(small.diagramLinesToLeave, 4);
      expect(small.spokenText, 'Diagram note: Leave about 4 lines of space to draw it later.');

      final medium = DocumentItem.diagram(relativeHeight: 0.30, linesToLeave: 8);
      expect(medium.spokenText, 'Diagram note: Leave about 8 lines of space to draw it later.');

      final large = DocumentItem.diagram(relativeHeight: 0.55, linesToLeave: 14);
      expect(large.spokenText, 'Diagram note: Leave about 14 lines of space to draw it later.');
    });

    test('serialization toMap and fromMap works seamlessly', () {
      final item = DocumentItem.heading(text: 'Photosynthesis', fontSize: 16.0, pageNumber: 2);
      final map = item.toMap();
      final restored = DocumentItem.fromMap(map);

      expect(restored, equals(item));
      expect(restored.text, 'Photosynthesis');
      expect(restored.fontSize, 16.0);
      expect(restored.pageNumber, 2);
      expect(restored.itemType, DocumentItemType.heading);
    });
  });

  group('Diagram size calculation tests', () {
    test('relative height <= 0.20 gives 4 lines', () {
      expect(PdfDocumentParser.calculateDiagramLines(0.05), 4);
      expect(PdfDocumentParser.calculateDiagramLines(0.15), 4);
      expect(PdfDocumentParser.calculateDiagramLines(0.20), 4);
      expect(
        PdfDocumentParser.getDiagramNote(4),
        'Diagram note: Leave about 4 lines of space to draw it later.',
      );
    });

    test('relative height 0.21 - 0.40 gives 8 lines', () {
      expect(PdfDocumentParser.calculateDiagramLines(0.21), 8);
      expect(PdfDocumentParser.calculateDiagramLines(0.30), 8);
      expect(PdfDocumentParser.calculateDiagramLines(0.40), 8);
      expect(
        PdfDocumentParser.getDiagramNote(8),
        'Diagram note: Leave about 8 lines of space to draw it later.',
      );
    });

    test('relative height > 0.40 gives 14 lines', () {
      expect(PdfDocumentParser.calculateDiagramLines(0.41), 14);
      expect(PdfDocumentParser.calculateDiagramLines(0.60), 14);
      expect(PdfDocumentParser.calculateDiagramLines(0.95), 14);
      expect(
        PdfDocumentParser.getDiagramNote(14),
        'Diagram note: Leave about 14 lines of space to draw it later.',
      );
    });
  });

  group('Heading detection heuristics', () {
    test('font size >= 1.15 * average is classified as heading', () {
      final avg = PdfDocumentParser.calculateAverageFontSize([12.0, 12.0, 12.0]);
      expect(avg, 12.0);
      final threshold = avg * PdfDocumentParser.headingSizeMultiplier; // 13.8

      expect(14.0 >= threshold, isTrue);
      expect(12.0 >= threshold, isFalse);
    });

    test('explicit uppercase Latin headings are detected', () {
      expect(PdfDocumentParser.isExplicitHeadingText('PHOTOSYNTHESIS AND RESPIRATION'), isTrue);
      expect(PdfDocumentParser.isExplicitHeadingText('HUMAN CIRCULATORY SYSTEM'), isTrue);
      // Dangling punctuation like comma should not be a heading
      expect(PdfDocumentParser.isExplicitHeadingText('PHOTOSYNTHESIS,'), isFalse);
    });

    test('section, chapter, and outline headings are detected', () {
      expect(PdfDocumentParser.isExplicitHeadingText('Chapter 1: The Human Heart'), isTrue);
      expect(PdfDocumentParser.isExplicitHeadingText('Section 3.2 Fluid Dynamics'), isTrue);
      expect(PdfDocumentParser.isExplicitHeadingText('Unit 4 - Plant Kingdom'), isTrue);
      expect(PdfDocumentParser.isExplicitHeadingText('1. Introduction to Genetics'), isTrue);
      expect(PdfDocumentParser.isExplicitHeadingText('2.1 Mitosis and Meiosis'), isTrue);
    });

    test('Kannada chapter patterns are detected', () {
      expect(PdfDocumentParser.isExplicitHeadingText('ಅಧ್ಯಾಯ ೧: ಜೀವಕೋಶ ಮತ್ತು ಅಂಗಾಂಶಗಳು'), isTrue);
      expect(PdfDocumentParser.isExplicitHeadingText('1. ಕನ್ನಡ ಸಾಹಿತ್ಯ ಪರಿಚಯ'), isTrue);
    });

    test('regular body sentences are not detected as explicit headings', () {
      expect(
        PdfDocumentParser.isExplicitHeadingText(
          'Mitochondria are membrane-bound cell organelles that generate most of the chemical energy.',
        ),
        isFalse,
      );
      expect(
        PdfDocumentParser.isExplicitHeadingText(
          'ಜೀವಕೋಶವು ಎಲ್ಲಾ ಜೀವಿಗಳ ಮೂಲ ರಚನಾತ್ಮಕ ಮತ್ತು ಕ್ರಿಯಾತ್ಮಕ ಘಟಕವಾಗಿದೆ.',
        ),
        isFalse,
      );
    });
  });

  group('Script handling & Language detection tests', () {
    test('detects English language accurately', () {
      final items = [
        DocumentItem.heading(text: 'Chapter 1', fontSize: 18.0),
        DocumentItem.paragraph(text: 'The solar system consists of the sun and eight planets.', fontSize: 12.0),
      ];
      expect(PdfDocumentParser.detectLanguage(items), 'en');
    });

    test('detects Kannada language without corruption (\u0C80-\u0CFF)', () {
      final items = [
        DocumentItem.heading(text: 'ಅಧ್ಯಾಯ ೧: ಪ್ರಕೃತಿ ಪಾಠ', fontSize: 18.0),
        DocumentItem.paragraph(
          text: 'ಭಾರತ ದೇಶವು ವೈವಿಧ್ಯಮಯ ಸಂಸ್ಕೃತಿ ಮತ್ತು ನೈಸರ್ಗಿಕ ಸಂಪತ್ತನ್ನು ಹೊಂದಿದೆ.',
          fontSize: 12.0,
        ),
      ];
      expect(PdfDocumentParser.detectLanguage(items), 'kn');
      expect(items[0].text, 'ಅಧ್ಯಾಯ ೧: ಪ್ರಕೃತಿ ಪಾಠ');
      expect(items[0].spokenText, 'Heading: ಅಧ್ಯಾಯ ೧: ಪ್ರಕೃತಿ ಪಾಠ.');
    });

    test('handles mixed script notes without character loss', () {
      final items = [
        DocumentItem.heading(text: 'DNA ರಚನೆ (DNA Structure)', fontSize: 18.0),
        DocumentItem.paragraph(
          text: 'DNA ಯು ಎರಡು ಹೆಲಿಕ್ಸ್ ಎಳೆಗಳನ್ನು ಹೊಂದಿರುತ್ತದೆ ಮತ್ತು Watson-Crick ಮಾದರಿಯನ್ನು ಅನುಸರಿಸುತ್ತದೆ.',
          fontSize: 12.0,
        ),
      ];
      // Mixed notes with predominant Kannada characters detect as Kannada
      expect(PdfDocumentParser.detectLanguage(items), 'kn');
      expect(items[0].spokenText, 'Heading: DNA ರಚನೆ (DNA Structure).');
    });
  });

  group('Document formatting and script generation', () {
    final sampleItems = [
      DocumentItem.heading(text: 'Plant Physiology', fontSize: 18.0),
      DocumentItem.paragraph(text: 'Plants absorb water and minerals from the soil through roots.', fontSize: 12.0),
      DocumentItem.diagram(relativeHeight: 0.28, linesToLeave: 8),
      DocumentItem.paragraph(text: 'Xylem transports water upwards to the leaves.', fontSize: 12.0),
    ];

    test('toFormattedNotes generates markdown-ready note string with markers', () {
      final notes = PdfDocumentParser.toFormattedNotes(sampleItems);
      expect(notes, contains('## Plant Physiology'));
      expect(notes, contains('Plants absorb water and minerals from the soil through roots.'));
      expect(notes, contains('[Diagram note: Leave about 8 lines of space to draw it later.]'));
      expect(notes, contains('Xylem transports water upwards to the leaves.'));
    });

    test('toDictationScript generates continuous speech script', () {
      final script = PdfDocumentParser.toDictationScript(sampleItems);
      expect(script, contains('Heading: Plant Physiology.'));
      expect(script, contains('Plants absorb water and minerals from the soil through roots.'));
      expect(script, contains('Diagram note: Leave about 8 lines of space to draw it later.'));
      expect(script, contains('Xylem transports water upwards to the leaves.'));
    });
  });

  group('End-to-End PDF parsing with real synthetic PDF bytes', () {
    // 1x1 PNG bitmap bytes
    final png1x1Bytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);

    test('parses PDF with heading, paragraph, and small diagram (<=0.20)', () {
      final doc = PdfDocument();
      final page = doc.pages.add(); // size is 595 x 842

      // Draw title with 20pt font (>= 1.15 * 12 = 13.8)
      page.graphics.drawString(
        'Cell Respiration',
        PdfStandardFont(PdfFontFamily.helvetica, 20),
        bounds: const Rect.fromLTWH(50, 40, 400, 30),
      );

      // Draw body with 12pt font
      page.graphics.drawString(
        'Glycolysis occurs in the cytoplasm and breaks down glucose.',
        PdfStandardFont(PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(50, 80, 500, 20),
      );

      // Draw small diagram: height 120 on 842 page -> 120/842 = 0.142 (<= 0.20 -> 4 lines)
      final image = PdfBitmap(png1x1Bytes);
      page.graphics.drawImage(image, const Rect.fromLTWH(50, 120, 150, 120));

      final bytes = doc.saveSync();
      doc.dispose();

      final items = PdfDocumentParser.parseBytes(bytes);
      expect(items.isNotEmpty, isTrue);

      final headings = items.where((i) => i.isHeading).toList();
      final paragraphs = items.where((i) => i.isParagraph).toList();
      final diagrams = items.where((i) => i.isDiagramPlaceholder).toList();

      expect(headings.length, greaterThanOrEqualTo(1));
      expect(headings.first.text, 'Cell Respiration');
      expect(headings.first.spokenText, 'Heading: Cell Respiration.');

      expect(paragraphs.length, greaterThanOrEqualTo(1));
      expect(paragraphs.first.text, contains('Glycolysis'));

      expect(diagrams.length, greaterThanOrEqualTo(1));
      expect(diagrams.first.diagramLinesToLeave, 4);
      expect(diagrams.first.spokenText, 'Diagram note: Leave about 4 lines of space to draw it later.');
    });

    test('parses PDF with medium diagram (0.21 - 0.40) and large diagram (>0.40)', () {
      final doc = PdfDocument();
      final page = doc.pages.add(); // 595 x 842

      // Medium image: height 250 on 842 page -> 250/842 = 0.296 (-> 8 lines)
      final image = PdfBitmap(png1x1Bytes);
      page.graphics.drawImage(image, const Rect.fromLTWH(50, 50, 200, 250));

      final bytes = doc.saveSync();
      doc.dispose();

      final items = PdfDocumentParser.parseBytes(bytes);
      final diagrams = items.where((i) => i.isDiagramPlaceholder).toList();
      expect(diagrams.length, greaterThanOrEqualTo(1));
      expect(diagrams.first.diagramLinesToLeave, 8);
      expect(diagrams.first.spokenText, 'Diagram note: Leave about 8 lines of space to draw it later.');
    });

    test('parses PDF with large diagram (> 0.40 -> 14 lines)', () {
      final doc = PdfDocument();
      final page = doc.pages.add(); // 595 x 842

      // Large image: height 450 on 842 page -> 450/842 = 0.534 (> 0.40 -> 14 lines)
      final image = PdfBitmap(png1x1Bytes);
      page.graphics.drawImage(image, const Rect.fromLTWH(50, 50, 300, 450));

      final bytes = doc.saveSync();
      doc.dispose();

      final items = PdfDocumentParser.parseBytes(bytes);
      final diagrams = items.where((i) => i.isDiagramPlaceholder).toList();
      expect(diagrams.length, greaterThanOrEqualTo(1));
      expect(diagrams.first.diagramLinesToLeave, 14);
      expect(diagrams.first.spokenText, 'Diagram note: Leave about 14 lines of space to draw it later.');
    });
  });

  group('Robustness and edge case handling', () {
    test('empty byte array returns empty list', () {
      expect(PdfDocumentParser.parseBytes([]), isEmpty);
    });

    test('corrupted or non-pdf bytes fallback gracefully without throwing', () {
      final corruptBytes = [0x00, 0xFF, 0x41, 0x42, 0x43];
      final items = PdfDocumentParser.parseBytes(corruptBytes);
      expect(items, isA<List<DocumentItem>>());
    });

    test('plain text encoded in bytes is parsed cleanly via fallback', () {
      final text = 'CHAPTER 1\nThis is a plain text paragraph converted as fallback.\n';
      final bytes = Uint8List.fromList(text.codeUnits);
      final items = PdfDocumentParser.parseBytes(bytes);

      expect(items.length, 2);
      expect(items[0].isHeading, isTrue);
      expect(items[0].text, 'CHAPTER 1');
      expect(items[0].spokenText, 'Heading: CHAPTER 1.');
      expect(items[1].isParagraph, isTrue);
      expect(items[1].spokenText, 'This is a plain text paragraph converted as fallback.');
    });
  });
}
