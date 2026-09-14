import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/saved_projects/saved_project.dart';

final class LocalSavedProjectStore {
  LocalSavedProjectStore._();

  static final instance = LocalSavedProjectStore._();

  Future<File> _file() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/saved_projects');
    await directory.create(recursive: true);
    return File('${directory.path}/projects.json');
  }

  Future<List<SavedProject>> list({SavedProjectMode? mode}) async {
    final file = await _file();
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    final projects =
        (decoded as List)
            .map(
              (item) =>
                  SavedProject.fromJson(Map<String, Object?>.from(item as Map)),
            )
            .where((project) => mode == null || project.mode == mode)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<SavedProject> save({
    String? id,
    required String name,
    required SavedProjectMode mode,
    required Map<String, Object?> data,
  }) async {
    final all = await list();
    final now = DateTime.now();
    final index = id == null ? -1 : all.indexWhere((item) => item.id == id);
    final project = SavedProject(
      id: id ?? '${now.microsecondsSinceEpoch}-${mode.name}',
      name: name.trim(),
      mode: mode,
      createdAt: index < 0 ? now : all[index].createdAt,
      updatedAt: now,
      data: data,
    );
    if (index < 0) {
      all.add(project);
    } else {
      all[index] = project;
    }
    await _write(all);
    return project;
  }

  Future<void> rename(SavedProject project, String name) async {
    final all = await list();
    final index = all.indexWhere((item) => item.id == project.id);
    if (index < 0) return;
    all[index] = project.copyWith(name: name.trim(), updatedAt: DateTime.now());
    await _write(all);
  }

  Future<void> delete(String id) async {
    final all = await list()
      ..removeWhere((item) => item.id == id);
    await _write(all);
  }

  Future<void> _write(List<SavedProject> projects) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(projects.map((e) => e.toJson()).toList()),
    );
  }
}
