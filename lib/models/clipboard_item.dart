class ClipboardItem {
  final int? id;
  final String content;
  final String type;
  final String? category;
  final String? sourceApp;
  final String? thumbnailPath;
  final DateTime createdAt;
  final bool isFavorite;

  ClipboardItem({
    this.id,
    required this.content,
    required this.type,
    this.category,
    this.sourceApp,
    this.thumbnailPath,
    required this.createdAt,
    this.isFavorite = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'type': type,
      'category': category,
      'source_app': sourceApp,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }

  factory ClipboardItem.fromMap(Map<String, dynamic> map) {
    return ClipboardItem(
      id: map['id'] as int?,
      content: map['content'] as String,
      type: map['type'] as String,
      category: map['category'] as String?,
      sourceApp: map['source_app'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isFavorite: (map['is_favorite'] as int?) == 1,
    );
  }

  ClipboardItem copyWith({
    int? id,
    String? content,
    String? type,
    String? category,
    String? sourceApp,
    String? thumbnailPath,
    DateTime? createdAt,
    bool? isFavorite,
  }) {
    return ClipboardItem(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      category: category ?? this.category,
      sourceApp: sourceApp ?? this.sourceApp,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
