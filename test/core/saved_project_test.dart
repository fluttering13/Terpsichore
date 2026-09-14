import 'package:flutter_test/flutter_test.dart';
import 'package:terpsichore/core/saved_projects/saved_project.dart';

void main() {
  test('saved project preserves mode, timestamps, and nested state', () {
    final project = SavedProject(
      id: 'learning-1',
      name: '第一段練習',
      mode: SavedProjectMode.learning,
      createdAt: DateTime.utc(2026, 9, 15, 10),
      updatedAt: DateTime.utc(2026, 9, 15, 11),
      data: {
        'loopStartMs': 1200,
        'repeat': true,
        'source': {'path': '/videos/dance.mp4'},
      },
    );

    final restored = SavedProject.fromJson(project.toJson());

    expect(restored.id, project.id);
    expect(restored.name, project.name);
    expect(restored.mode, SavedProjectMode.learning);
    expect(restored.createdAt, project.createdAt);
    expect(restored.updatedAt, project.updatedAt);
    expect(restored.data, project.data);
  });

  test('saved project modes have user-facing labels', () {
    expect(SavedProjectMode.learning.label, '學習模式');
    expect(SavedProjectMode.analysis.label, 'A+B 分析');
    expect(SavedProjectMode.musicPractice.label, '純音樂練習');
  });
}
