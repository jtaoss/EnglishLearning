import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';

/// Synthetic API contract data, built only from public bundled vocabulary.
Map<String, Object?> mobileSchema() => {
  'object': 'data_source',
  'id': notionPilotSource,
  'in_trash': false,
  'properties': {
    for (final e in NotionFields.mapping.entries)
      e.value: {'type': NotionFields.type(e.key)},
  },
};
List<Map<String, Object?>> mobilePages(List<VocabularyEntry> entries) => [
  for (var i = 0; i < entries.length; i++)
    {
      'object': 'page',
      'id': 'aaaa0000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}',
      'parent': {'data_source_id': notionPilotSource},
      'last_edited_time': '2026-11-08T10:00:00Z',
      'in_trash': false,
      'properties': {
        for (final field in NotionFields.mapping.entries)
          field.value: {
            'type': NotionFields.type(field.key),
            if (NotionFields.type(field.key) == 'select')
              'select': {'name': entries[i].fields[field.key] ?? ''}
            else
              NotionFields.type(field.key): [
                {'plain_text': entries[i].fields[field.key] ?? ''},
              ],
          },
      },
    },
];
