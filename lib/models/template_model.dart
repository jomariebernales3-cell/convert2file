class TemplateModel {
  final int? id;
  final int userId;
  final int fileId;
  final String title;
  final Map<String, dynamic> structure;
  final Map<String, dynamic> placeholders;
  final DateTime createdAt;
  final DateTime updatedAt;

  TemplateModel({
    this.id,
    required this.userId,
    required this.fileId,
    required this.title,
    required this.structure,
    required this.placeholders,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'file_id': fileId,
      'title': title,
      'structure_json': structure.toString(),
      'placeholders_json': placeholders.toString(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TemplateModel.fromMap(Map<String, dynamic> map) {
    return TemplateModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      fileId: map['file_id'] as int,
      title: map['title'] as String,
      structure: map['structure_json'] != null ? map['structure_json'] as Map<String, dynamic> : {},
      placeholders: map['placeholders_json'] != null ? map['placeholders_json'] as Map<String, dynamic> : {},
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class TemplateStructure {
  final String title;
  final List<Map<String, dynamic>> headings;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> tables;
  final List<Map<String, dynamic>> lists;
  final List<String> rawLines;

  TemplateStructure({
    required this.title,
    required this.headings,
    required this.sections,
    required this.tables,
    required this.lists,
    required this.rawLines,
  });

  factory TemplateStructure.fromJson(Map<String, dynamic> json) {
    return TemplateStructure(
      title: json['title'] as String? ?? 'Untitled',
      headings: List<Map<String, dynamic>>.from(json['headings'] as List? ?? []),
      sections: List<Map<String, dynamic>>.from(json['sections'] as List? ?? []),
      tables: List<Map<String, dynamic>>.from(json['tables'] as List? ?? []),
      lists: List<Map<String, dynamic>>.from(json['lists'] as List? ?? []),
      rawLines: List<String>.from(json['raw_lines'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'headings': headings,
      'sections': sections,
      'tables': tables,
      'lists': lists,
      'raw_lines': rawLines,
    };
  }
}
