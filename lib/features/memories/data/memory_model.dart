class MemoryModel {
  final String id;
  final String title;
  final String originalContent;
  final String? processedContent;
  final String memoryType; // task, reminder, personal_memory, idea, commitment, personal_preference, important_date, reference, shopping, general_note
  final String category; // Work, Personal, Health, Shopping, Ideas, Commitments, General
  final List<String> tags;
  final String? associatedPerson;
  final DateTime? associatedDate;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncStatus; // pending, synced, error

  MemoryModel({
    required this.id,
    required this.title,
    required this.originalContent,
    this.processedContent,
    this.memoryType = 'general_note',
    this.category = 'General',
    this.tags = const [],
    this.associatedPerson,
    this.associatedDate,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = 'pending',
  });

  MemoryModel copyWith({
    String? id,
    String? title,
    String? originalContent,
    String? processedContent,
    String? memoryType,
    String? category,
    List<String>? tags,
    String? associatedPerson,
    DateTime? associatedDate,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? syncStatus,
  }) {
    return MemoryModel(
      id: id ?? this.id,
      title: title ?? this.title,
      originalContent: originalContent ?? this.originalContent,
      processedContent: processedContent ?? this.processedContent,
      memoryType: memoryType ?? this.memoryType,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      associatedPerson: associatedPerson ?? this.associatedPerson,
      associatedDate: associatedDate ?? this.associatedDate,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'original_content': originalContent,
      'processed_content': processedContent,
      'memory_type': memoryType,
      'category': category,
      'tags': tags.join(','),
      'associated_person': associatedPerson,
      'associated_date': associatedDate?.toIso8601String(),
      'is_pinned': isPinned ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory MemoryModel.fromMap(Map<String, dynamic> map) {
    List<String> parsedTags = [];
    if (map['tags'] != null && map['tags'].toString().isNotEmpty) {
      parsedTags = map['tags'].toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    return MemoryModel(
      id: map['id'] as String,
      title: map['title'] as String,
      originalContent: map['original_content'] as String,
      processedContent: map['processed_content'] as String?,
      memoryType: map['memory_type'] as String? ?? 'general_note',
      category: map['category'] as String? ?? 'General',
      tags: parsedTags,
      associatedPerson: map['associated_person'] as String?,
      associatedDate: map['associated_date'] != null
          ? DateTime.tryParse(map['associated_date'].toString())
          : null,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'].toString()),
      updatedAt: DateTime.parse(map['updated_at'].toString()),
      deletedAt: map['deleted_at'] != null
          ? DateTime.tryParse(map['deleted_at'].toString())
          : null,
      syncStatus: map['sync_status'] as String? ?? 'pending',
    );
  }
}
