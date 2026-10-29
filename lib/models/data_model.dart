class DataModel {
  final String title;
  final List<String> headings;
  final List<String> paragraphs;
  final List<List<String>> lists;
  final List<List<List<String>>> tables;
  final List<String> importantPoints;
  final List<Map<String, String>> keyValues;
  final List<Map<String, dynamic>> blocks;
  final Map<String, dynamic> meta;

  DataModel({
    required this.title,
    required this.headings,
    required this.paragraphs,
    required this.lists,
    required this.tables,
    required this.importantPoints,
    required this.keyValues,
    required this.blocks,
    required this.meta,
  });

  factory DataModel.empty() {
    return DataModel(
      title: 'Untitled Document',
      headings: [],
      paragraphs: [],
      lists: [],
      tables: [],
      importantPoints: [],
      keyValues: [],
      blocks: [],
      meta: {'structure_version': 2, 'has_explicit_emphasis': false, 'emphasized_count': 0, 'emphasized_terms': []},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'headings': headings,
      'paragraphs': paragraphs,
      'lists': lists,
      'tables': tables,
      'important_points': importantPoints,
      'key_values': keyValues,
      'blocks': blocks,
      'meta': meta,
    };
  }

  factory DataModel.fromJson(Map<String, dynamic> json) {
    return DataModel(
      title: json['title'] as String? ?? 'Untitled Document',
      headings: List<String>.from(json['headings'] as List? ?? []),
      paragraphs: List<String>.from(json['paragraphs'] as List? ?? []),
      lists: (json['lists'] as List? ?? []).map((e) => List<String>.from(e as List)).toList(),
      tables: (json['tables'] as List? ?? []).map((e) => (e as List).map((r) => List<String>.from(r as List)).toList()).toList(),
      importantPoints: List<String>.from(json['important_points'] as List? ?? []),
      keyValues: (json['key_values'] as List? ?? []).map((e) => Map<String, String>.from(e as Map)).toList(),
      blocks: List<Map<String, dynamic>>.from(json['blocks'] as List? ?? []),
      meta: json['meta'] as Map<String, dynamic>? ?? {},
    );
  }
}
