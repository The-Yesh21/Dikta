/// Document item types identifying structured content extracted from imported documents.
enum DocumentItemType {
  /// Section heading or title.
  heading,

  /// Regular body text paragraph or line.
  paragraph,

  /// Visual diagram, chart, or image placeholder with spacing recommendations.
  diagramPlaceholder,
}

/// Represents an individual structured document element (heading, body paragraph,
/// or embedded diagram placeholder) extracted from a note document (such as a PDF).
class DocumentItem {
  /// The raw or representative textual content of this item.
  final String text;

  /// Font size in points (0.0 for diagram placeholders).
  final double fontSize;

  /// The structural classification of this item.
  final DocumentItemType itemType;

  /// The relative height of the diagram relative to the page height (0.0 - 1.0).
  /// Null for text items.
  final double? diagramRelativeHeight;

  /// Number of ruled notebook lines the student should leave empty to sketch the diagram.
  /// (e.g. 4 for small, 8 for medium, 14 for large). Null for text items.
  final int? diagramLinesToLeave;

  /// The speech text spoken aloud by the dictation engine.
  /// For headings: "Heading: [Text]."
  /// For diagrams: "Diagram note: Leave about [N] lines of space to draw it later."
  /// For paragraphs: "[Text]"
  final String spokenText;

  /// Page number where this item appears (1-indexed).
  final int pageNumber;

  const DocumentItem({
    required this.text,
    required this.fontSize,
    required this.itemType,
    this.diagramRelativeHeight,
    this.diagramLinesToLeave,
    required this.spokenText,
    this.pageNumber = 1,
  });

  /// Factory constructor for a section heading.
  factory DocumentItem.heading({
    required String text,
    required double fontSize,
    int pageNumber = 1,
  }) {
    final clean = text.trim();
    final punctuationClean = clean.endsWith('.') ? clean : '$clean.';
    final spoken = 'Heading: $punctuationClean';
    return DocumentItem(
      text: clean,
      fontSize: fontSize,
      itemType: DocumentItemType.heading,
      spokenText: spoken,
      pageNumber: pageNumber,
    );
  }

  /// Factory constructor for a regular paragraph or text line.
  factory DocumentItem.paragraph({
    required String text,
    required double fontSize,
    int pageNumber = 1,
  }) {
    final clean = text.trim();
    return DocumentItem(
      text: clean,
      fontSize: fontSize,
      itemType: DocumentItemType.paragraph,
      spokenText: clean,
      pageNumber: pageNumber,
    );
  }

  /// Factory constructor for an embedded diagram placeholder.
  factory DocumentItem.diagram({
    required double relativeHeight,
    required int linesToLeave,
    String? customNote,
    int pageNumber = 1,
  }) {
    final note = customNote ??
        'Diagram note: Leave about $linesToLeave lines of space to draw it later.';
    return DocumentItem(
      text: note,
      fontSize: 0.0,
      itemType: DocumentItemType.diagramPlaceholder,
      diagramRelativeHeight: relativeHeight,
      diagramLinesToLeave: linesToLeave,
      spokenText: note,
      pageNumber: pageNumber,
    );
  }

  /// Whether this item represents a section heading.
  bool get isHeading => itemType == DocumentItemType.heading;

  /// Whether this item represents body paragraph text.
  bool get isParagraph => itemType == DocumentItemType.paragraph;

  /// Whether this item represents an embedded diagram placeholder.
  bool get isDiagramPlaceholder =>
      itemType == DocumentItemType.diagramPlaceholder;

  DocumentItem copyWith({
    String? text,
    double? fontSize,
    DocumentItemType? itemType,
    double? diagramRelativeHeight,
    int? diagramLinesToLeave,
    String? spokenText,
    int? pageNumber,
  }) {
    return DocumentItem(
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      itemType: itemType ?? this.itemType,
      diagramRelativeHeight:
          diagramRelativeHeight ?? this.diagramRelativeHeight,
      diagramLinesToLeave: diagramLinesToLeave ?? this.diagramLinesToLeave,
      spokenText: spokenText ?? this.spokenText,
      pageNumber: pageNumber ?? this.pageNumber,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'fontSize': fontSize,
      'itemType': itemType.name,
      'diagramRelativeHeight': diagramRelativeHeight,
      'diagramLinesToLeave': diagramLinesToLeave,
      'spokenText': spokenText,
      'pageNumber': pageNumber,
    };
  }

  factory DocumentItem.fromMap(Map<String, dynamic> map) {
    final typeName = map['itemType'] as String? ?? 'paragraph';
    final type = DocumentItemType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => DocumentItemType.paragraph,
    );
    return DocumentItem(
      text: map['text'] as String? ?? '',
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 12.0,
      itemType: type,
      diagramRelativeHeight:
          (map['diagramRelativeHeight'] as num?)?.toDouble(),
      diagramLinesToLeave: map['diagramLinesToLeave'] as int?,
      spokenText: map['spokenText'] as String? ?? '',
      pageNumber: map['pageNumber'] as int? ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentItem &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          fontSize == other.fontSize &&
          itemType == other.itemType &&
          diagramRelativeHeight == other.diagramRelativeHeight &&
          diagramLinesToLeave == other.diagramLinesToLeave &&
          spokenText == other.spokenText &&
          pageNumber == other.pageNumber;

  @override
  int get hashCode => Object.hash(
        text,
        fontSize,
        itemType,
        diagramRelativeHeight,
        diagramLinesToLeave,
        spokenText,
        pageNumber,
      );

  @override
  String toString() {
    switch (itemType) {
      case DocumentItemType.heading:
        return 'DocumentItem.heading(page: $pageNumber, font: ${fontSize.toStringAsFixed(1)}, text: "$text")';
      case DocumentItemType.paragraph:
        return 'DocumentItem.paragraph(page: $pageNumber, font: ${fontSize.toStringAsFixed(1)}, text: "$text")';
      case DocumentItemType.diagramPlaceholder:
        return 'DocumentItem.diagram(page: $pageNumber, relH: ${diagramRelativeHeight?.toStringAsFixed(2)}, lines: $diagramLinesToLeave)';
    }
  }
}
