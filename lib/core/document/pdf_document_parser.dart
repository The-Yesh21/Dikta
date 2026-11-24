import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_reference_holder.dart';
// ignore: implementation_imports
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';

import 'document_item.dart';

/// Pure Dart parser and semantic document structure analyzer for PDF notes.
///
/// Extracts structured text lines and embedded diagrams/images, classifying
/// content into headings, paragraphs, and diagram placeholders with writing-friendly
/// spoken notes and ruled-line space estimations.
class PdfDocumentParser {
  /// Heading font size multiplier threshold relative to average font size.
  static const double headingSizeMultiplier = 1.15;

  /// Default page height in points if not explicitly specified by MediaBox.
  static const double defaultPageHeight = 842.0;

  /// Default body font size in points if no valid font sizes exist.
  static const double defaultFontSize = 12.0;

  /// Parses a PDF document from raw byte data.
  ///
  /// Returns a structured list of [DocumentItem]s preserving visual document flow,
  /// with headings identified, paragraphs extracted, and diagrams marked with
  /// lines-to-leave calculations.
  static List<DocumentItem> parseBytes(List<int> bytes) {
    if (bytes.isEmpty) return const [];

    PdfDocument? document;
    try {
      final uint8Bytes =
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      document = PdfDocument(inputBytes: uint8Bytes);

      final pageCount = document.pages.count;
      if (pageCount == 0) return const [];

      final extractor = PdfTextExtractor(document);
      final pageLines = <int, List<TextLine>>{};
      final allFontSizes = <double>[];

      // Step 1: Extract text lines across all pages and gather font size statistics.
      for (int p = 0; p < pageCount; p++) {
        try {
          final lines = extractor.extractTextLines(
            startPageIndex: p,
            endPageIndex: p,
          );
          pageLines[p] = lines;
          for (final line in lines) {
            final trimmed = line.text.trim();
            if (trimmed.isNotEmpty && line.fontSize > 0) {
              allFontSizes.add(line.fontSize);
            }
          }
        } catch (_) {
          pageLines[p] = [];
        }
      }

      // Step 2: Compute statistical average and heading font threshold.
      final averageFontSize = calculateAverageFontSize(allFontSizes);
      final headingThreshold = averageFontSize * headingSizeMultiplier;

      final items = <DocumentItem>[];

      // Step 3: Analyze each page for text classification and diagram placements.
      for (int p = 0; p < pageCount; p++) {
        final pageNumber = p + 1;
        final loadedPage = document.pages[p];
        final pageHeight = loadedPage.size.height > 0
            ? loadedPage.size.height
            : defaultPageHeight;

        // Detect embedded diagrams and images on this page.
        final pageImages = _extractPageImages(loadedPage, pageHeight);

        final lines = pageLines[p] ?? [];
        final positionedItems = <_PagePositionedItem>[];

        if (lines.isNotEmpty) {
          // Classify text lines into headings or paragraphs.
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            final cleanText = line.text.trim();
            if (cleanText.isEmpty) continue;

            final isFirstLine = i == 0;
            final isHeading =
                (line.fontSize >= headingThreshold && line.fontSize > 0) ||
                    isExplicitHeadingText(cleanText,
                        isFirstLineOfSection: isFirstLine);

            final item = isHeading
                ? DocumentItem.heading(
                    text: cleanText,
                    fontSize: line.fontSize > 0 ? line.fontSize : averageFontSize,
                    pageNumber: pageNumber,
                  )
                : DocumentItem.paragraph(
                    text: cleanText,
                    fontSize: line.fontSize > 0 ? line.fontSize : averageFontSize,
                    pageNumber: pageNumber,
                  );

            positionedItems.add(_PagePositionedItem(
              item: item,
              top: line.bounds.top,
            ));
          }
        } else {
          // Robust fallback: extract raw text for this page if structured lines unavailable
          try {
            final pageText = extractor.extractText(startPageIndex: p, endPageIndex: p);
            final rawSplit = pageText.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            for (int i = 0; i < rawSplit.length; i++) {
              final rawLine = rawSplit[i];
              final isFirstLine = i == 0;
              final isHeading = isExplicitHeadingText(rawLine, isFirstLineOfSection: isFirstLine);
              final item = isHeading
                  ? DocumentItem.heading(
                      text: rawLine,
                      fontSize: 16.0,
                      pageNumber: pageNumber,
                    )
                  : DocumentItem.paragraph(
                      text: rawLine,
                      fontSize: averageFontSize,
                      pageNumber: pageNumber,
                    );
              positionedItems.add(_PagePositionedItem(
                item: item,
                top: (i + 1) * 24.0,
              ));
            }
          } catch (_) {}
        }

        // Add detected diagram placeholders with lines-to-leave calculations.
        for (final img in pageImages) {
          final linesToLeave = calculateDiagramLines(img.relativeHeight);
          positionedItems.add(_PagePositionedItem(
            item: DocumentItem.diagram(
              relativeHeight: img.relativeHeight,
              linesToLeave: linesToLeave,
              pageNumber: pageNumber,
            ),
            top: img.top,
          ));
        }

        // Sort items by vertical position on page (top to bottom).
        positionedItems.sort((a, b) => a.top.compareTo(b.top));

        for (final pItem in positionedItems) {
          items.add(pItem.item);
        }
      }

      if (items.isEmpty) {
        return _parseFallback(bytes);
      }

      return items;
    } catch (_) {
      // Graceful fallback for non-standard or malformed streams.
      return _parseFallback(bytes);
    } finally {
      document?.dispose();
    }
  }

  /// Parses a PDF document from an on-disk file path asynchronously.
  static Future<List<DocumentItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const [];
    }
    final bytes = await file.readAsBytes();
    return parseBytes(bytes);
  }

  /// Parses a PDF document from an on-disk file path synchronously.
  static List<DocumentItem> parseFileSync(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return const [];
    }
    final bytes = file.readAsBytesSync();
    return parseBytes(bytes);
  }

  /// Calculates the statistical average of all valid positive font sizes.
  static double calculateAverageFontSize(List<double> fontSizes) {
    final valid = fontSizes.where((s) => s > 0).toList();
    if (valid.isEmpty) return defaultFontSize;
    final sum = valid.reduce((a, b) => a + b);
    return sum / valid.length;
  }

  /// Calculates the recommended ruled notebook lines to leave based on diagram relative height.
  ///
  /// Spec:
  /// - <= 0.20 (Small diagram): 4 lines
  /// - 0.21 - 0.40 (Medium diagram): 8 lines
  /// - > 0.40 (Large diagram): 14 lines
  static int calculateDiagramLines(double relativeHeight) {
    if (relativeHeight <= 0.20) {
      return 4;
    } else if (relativeHeight <= 0.40) {
      return 8;
    } else {
      return 14;
    }
  }

  /// Returns the standardized human-readable spoken note for a diagram.
  static String getDiagramNote(int linesToLeave) {
    return 'Diagram note: Leave about $linesToLeave lines of space to draw it later.';
  }

  /// Determines whether a line of text represents an explicit heading based on
  /// typography, casing, and section prefixes.
  static bool isExplicitHeadingText(String text,
      {bool isFirstLineOfSection = false}) {
    final clean = text.trim();
    if (clean.isEmpty) return false;

    // Pattern 1: Explicit Section / Chapter / Module keywords in English or Kannada.
    final sectionKeywordRegex = RegExp(
      r'^(chapter|section|unit|part|module|topic|lesson)\b',
      caseSensitive: false,
    );
    final kannadaChapterRegex = RegExp(
      r'^ಅಧ್ಯಾಯ[\s\d:.\-\u0CE6-\u0CEF]',
      caseSensitive: false,
    );
    if ((sectionKeywordRegex.hasMatch(clean) ||
            kannadaChapterRegex.hasMatch(clean)) &&
        clean.length <= 80) {
      return true;
    }

    // Pattern 2: Numbered or lettered outline heading (e.g. "1. Introduction", "2.1 Background").
    final numberedOutlineRegex = RegExp(
      r'^(\d+(\.\d+)*\.?|[A-Z]\.|\b[IVXLCDM]+\.)\s+[\w\s\u0C80-\u0CFF]',
    );
    if (numberedOutlineRegex.hasMatch(clean) &&
        clean.length <= 80 &&
        !clean.endsWith(',')) {
      return true;
    }

    // Pattern 3: All-uppercase Latin heading (must contain at least 2 Latin characters).
    final hasLatin = RegExp(r'[a-zA-Z]').hasMatch(clean);
    if (hasLatin) {
      final latinOnly = clean.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (latinOnly.length >= 2 &&
          clean == clean.toUpperCase() &&
          clean.length <= 70) {
        // Exclude dangling continuation punctuation
        if (!clean.endsWith(',') &&
            !clean.endsWith(';') &&
            !clean.endsWith('...')) {
          return true;
        }
      }
    }

    // Pattern 4: Short, unpunctuated leading title line at the top of a page/section.
    if (isFirstLineOfSection &&
        clean.length >= 3 &&
        clean.length <= 45 &&
        !clean.endsWith(',') &&
        !clean.endsWith('.') &&
        !clean.endsWith(';')) {
      return true;
    }

    return false;
  }

  /// Detects whether the predominant language across items is Kannada ('kn'), Hindi ('hi'), or English ('en').
  ///
  /// Checks characters against the Unicode Kannada (\u0C80-\u0CFF) and Devanagari (\u0900-\u097F) blocks.
  static String detectLanguage(List<DocumentItem> items) {
    int kannadaChars = 0;
    int devanagariChars = 0;
    int latinChars = 0;

    for (final item in items) {
      for (final rune in item.text.runes) {
        if (rune >= 0x0C80 && rune <= 0x0CFF) {
          kannadaChars++;
        } else if (rune >= 0x0900 && rune <= 0x097F) {
          devanagariChars++;
        } else if ((rune >= 0x0041 && rune <= 0x005A) ||
            (rune >= 0x0061 && rune <= 0x007A)) {
          latinChars++;
        }
      }
    }

    if (devanagariChars > kannadaChars && devanagariChars > latinChars) {
      return 'hi';
    }
    if (kannadaChars > latinChars && kannadaChars > 0) {
      return 'kn';
    }
    return 'en';
  }

  /// Formats document items into clean notes text with headings (#) and diagram notes
  /// suitable for display in the note input text field.
  static String toFormattedNotes(List<DocumentItem> items) {
    final buffer = StringBuffer();
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      switch (item.itemType) {
        case DocumentItemType.heading:
          if (i > 0) buffer.writeln();
          buffer.writeln('## ${item.text}');
          buffer.writeln();
          break;
        case DocumentItemType.diagramPlaceholder:
          buffer.writeln();
          buffer.writeln('[${item.spokenText}]');
          buffer.writeln();
          break;
        case DocumentItemType.paragraph:
          buffer.writeln(item.text);
          break;
      }
    }
    return buffer.toString().trim();
  }

  /// Generates the complete continuous dictation script spoken by the dictation engine.
  static String toDictationScript(List<DocumentItem> items) {
    final buffer = StringBuffer();
    for (final item in items) {
      final spoken = item.spokenText.trim();
      if (spoken.isNotEmpty) {
        buffer.writeln(spoken);
      }
    }
    return buffer.toString().trim();
  }

  /// Extracts embedded images and diagrams on a [PdfPage] by inspecting
  /// content streams for transformation matrices and resource dictionaries.
  static List<_ImagePlacement> _extractPageImages(
      PdfPage page, double pageHeight) {
    final placements = <_ImagePlacement>[];

    try {
      final pageHelper = PdfPageHelper.getHelper(page);
      final contents = pageHelper.dictionary?[PdfName('Contents')];

      // Extract transformation matrices (cm) followed by Do operators in content streams.
      final streamStrings = <String>[];
      if (contents is PdfArray) {
        for (int i = 0; i < contents.count; i++) {
          var elem = contents[i];
          if (elem is PdfReferenceHolder) elem = elem.object;
          if (elem is PdfStream && elem.dataStream != null) {
            _appendDecompressedStream(elem.dataStream!, streamStrings);
          }
        }
      } else if (contents is PdfReferenceHolder) {
        final obj = contents.object;
        if (obj is PdfStream && obj.dataStream != null) {
          _appendDecompressedStream(obj.dataStream!, streamStrings);
        }
      } else if (contents is PdfStream && contents.dataStream != null) {
        _appendDecompressedStream(contents.dataStream!, streamStrings);
      }

      // Regex to detect transformation matrices directly scaling and positioning an image (Do):
      // In PDF, the matrix immediately preceding the Do operator sets the rendered image dimensions:
      // Pattern: sx 0 0 sy tx ty cm \s* /ImageName Do
      final cmRegex = RegExp(
        r'([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+cm\s*\/([A-Za-z0-9_-]+)\s+Do',
      );

      for (final contentText in streamStrings) {
        final matches = cmRegex.allMatches(contentText);
        for (final match in matches) {
          final sy = double.tryParse(match.group(4) ?? '') ?? 0.0;
          final ty = double.tryParse(match.group(6) ?? '') ?? 0.0;
          final imageHeight = sy.abs();

          if (imageHeight > 10.0) {
            final relHeight = (imageHeight / pageHeight).clamp(0.01, 1.0);
            // In PDF coordinate space, ty is often relative to page bottom or inverted.
            final top = ty < 0 ? ty.abs() : (pageHeight - ty).abs();
            placements.add(_ImagePlacement(
              imageHeight: imageHeight,
              pageHeight: pageHeight,
              relativeHeight: relHeight,
              top: top,
            ));
          }
        }
      }

      // Fallback: If no cm ... Do was matched, check XObject resource dictionary directly.
      if (placements.isEmpty) {
        final resources = pageHelper.dictionary?[PdfName('Resources')];
        dynamic resObj = resources;
        if (resObj is PdfReferenceHolder) resObj = resObj.object;

        if (resObj is PdfDictionary) {
          dynamic xobjs = resObj[PdfName('XObject')];
          if (xobjs is PdfReferenceHolder) xobjs = xobjs.object;

          if (xobjs is PdfDictionary) {
            final itemsMap = xobjs.items;
            if (itemsMap != null) {
              for (final entry in itemsMap.entries) {
                dynamic xObj = entry.value;
                if (xObj is PdfReferenceHolder) xObj = xObj.object;

                if (xObj is PdfDictionary) {
                  final subtype = xObj[PdfName('Subtype')];
                  if (subtype is PdfName && subtype.name == 'Image') {
                    final hNum = xObj[PdfName('Height')];
                    final height = (hNum is PdfNumber && hNum.value != null)
                        ? hNum.value!.toDouble()
                        : 200.0;
                    final relHeight =
                        (height / pageHeight).clamp(0.01, 1.0);
                    placements.add(_ImagePlacement(
                      imageHeight: height,
                      pageHeight: pageHeight,
                      relativeHeight: relHeight,
                      top: pageHeight * 0.5, // Default to middle of page
                    ));
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Return any placements collected so far without throwing.
    }

    return placements;
  }

  /// Appends decoded content stream text from raw compressed or uncompressed bytes.
  static void _appendDecompressedStream(
      List<int> dataStream, List<String> output) {
    try {
      final decompressed = zlib.decode(dataStream);
      output.add(utf8.decode(decompressed, allowMalformed: true));
    } catch (_) {
      try {
        // Try raw deflate
        final rawDecompressed =
            ZLibCodec(raw: true).decode(dataStream);
        output.add(utf8.decode(rawDecompressed, allowMalformed: true));
      } catch (_) {
        // Fallback: decode directly
        output.add(utf8.decode(dataStream, allowMalformed: true));
      }
    }
  }

  /// Graceful fallback parser when PDF binary parsing fails or plain text is supplied.
  static List<DocumentItem> _parseFallback(List<int> bytes) {
    // If the input is a binary PDF (magic bytes %PDF-), do not decode raw bytecode as UTF-8
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46) { // F
      return const [];
    }

    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final rawLines =
          text.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
      final nonEmpty = rawLines.where((l) => l.isNotEmpty).toList();
      if (nonEmpty.isEmpty) return const [];

      final items = <DocumentItem>[];
      for (int i = 0; i < nonEmpty.length; i++) {
        final line = nonEmpty[i];
        final isFirst = i == 0;
        final isHeading =
            isExplicitHeadingText(line, isFirstLineOfSection: isFirst);

        if (isHeading) {
          items.add(DocumentItem.heading(
            text: line,
            fontSize: 16.0,
            pageNumber: 1,
          ));
        } else {
          items.add(DocumentItem.paragraph(
            text: line,
            fontSize: defaultFontSize,
            pageNumber: 1,
          ));
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }
}

/// Internal data container for diagram image placement on a page.
class _ImagePlacement {
  final double imageHeight;
  final double pageHeight;
  final double relativeHeight;
  final double top;

  _ImagePlacement({
    required this.imageHeight,
    required this.pageHeight,
    required this.relativeHeight,
    required this.top,
  });
}

/// Internal helper associating a [DocumentItem] with its vertical page position.
class _PagePositionedItem {
  final DocumentItem item;
  final double top;

  _PagePositionedItem({required this.item, required this.top});
}
