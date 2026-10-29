class FileRecordModel {
  final int? id;
  final int userId;
  final int? sourceFileId;
  final String kind;
  final String originalName;
  final String storedName;
  final String mimeType;
  final String extension;
  final String path;
  final int sizeBytes;
  final String? metadataJson;
  final DateTime createdAt;

  FileRecordModel({
    this.id,
    required this.userId,
    this.sourceFileId,
    required this.kind,
    required this.originalName,
    required this.storedName,
    required this.mimeType,
    required this.extension,
    required this.path,
    this.sizeBytes = 0,
    this.metadataJson,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'source_file_id': sourceFileId,
      'kind': kind,
      'original_name': originalName,
      'stored_name': storedName,
      'mime_type': mimeType,
      'extension': extension,
      'path': path,
      'size_bytes': sizeBytes,
      'metadata_json': metadataJson,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory FileRecordModel.fromMap(Map<String, dynamic> map) {
    return FileRecordModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      sourceFileId: map['source_file_id'] as int?,
      kind: map['kind'] as String,
      originalName: map['original_name'] as String,
      storedName: map['stored_name'] as String,
      mimeType: map['mime_type'] as String,
      extension: map['extension'] as String,
      path: map['path'] as String,
      sizeBytes: map['size_bytes'] as int? ?? 0,
      metadataJson: map['metadata_json'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  bool get isTemplate => kind == 'template_upload';
  bool get isData => kind == 'data_upload';
  bool get isOutput => kind.startsWith('output_');
}
