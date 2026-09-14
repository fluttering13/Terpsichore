enum SavedProjectMode { learning, analysis, musicPractice }

extension SavedProjectModeLabel on SavedProjectMode {
  String get label => switch (this) {
    SavedProjectMode.learning => '學習模式',
    SavedProjectMode.analysis => 'A+B 分析',
    SavedProjectMode.musicPractice => '純音樂練習',
  };
}

final class SavedProject {
  const SavedProject({
    required this.id,
    required this.name,
    required this.mode,
    required this.createdAt,
    required this.updatedAt,
    required this.data,
  });

  final String id;
  final String name;
  final SavedProjectMode mode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> data;

  SavedProject copyWith({String? name, DateTime? updatedAt}) => SavedProject(
    id: id,
    name: name ?? this.name,
    mode: mode,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    data: data,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'mode': mode.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'data': data,
  };

  factory SavedProject.fromJson(Map<String, Object?> json) {
    final modeName = json['mode'] as String;
    return SavedProject(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: SavedProjectMode.values.byName(modeName),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      data: Map<String, Object?>.from(json['data'] as Map),
    );
  }
}
