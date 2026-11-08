/// Book content and provenance. Personal learning state lives separately.
final class VocabularyEntry {
  VocabularyEntry(Map<String, String> fields)
    : fields = Map.unmodifiable(fields);

  final Map<String, String> fields;
  String get id => fields['entry_id']!;
  String get word => fields['word']!;
  String get meaning => fields['meaning_zh']!;
  String get libraryClass => fields['library_class']!;
  // Case is meaningful: May/may and March/march have distinct existing IDs.
  String get wordKey => word.trim();
}
