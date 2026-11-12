/// The type of syntax/structural boundary terminating a text chunk.
enum BoundaryType {
  /// Mid-sentence clause boundary (comma, semicolon, colon, em-dash).
  comma,

  /// End of sentence (period, exclamation, question mark, terminal danda).
  sentence,

  /// End of paragraph (double newline).
  paragraph,

  /// No structural boundary (chunk split caused by word count limit).
  none,
}

/// Information about a single chunk produced by [TextChunker].
class ChunkInfo {
  const ChunkInfo({
    required this.index,
    required this.text,
    required this.wordCount,
    required this.boundaryType,
    this.charStartIndex = 0,
    this.charEndIndex = 0,
  });

  /// 0-based sequential index of this chunk in the document.
  final int index;

  /// The cleaned text phrase to be synthesized.
  final String text;

  /// Number of words in this chunk.
  final int wordCount;

  /// The boundary type trailing this chunk (controls the syntax factor pause).
  final BoundaryType boundaryType;

  /// Character start position in the original text.
  final int charStartIndex;

  /// Character end position in the original text.
  final int charEndIndex;

  @override
  String toString() =>
      'ChunkInfo(#$index, words: $wordCount, boundary: $boundaryType, text: "$text")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChunkInfo &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          text == other.text &&
          wordCount == other.wordCount &&
          boundaryType == other.boundaryType;

  @override
  int get hashCode => Object.hash(index, text, wordCount, boundaryType);
}
