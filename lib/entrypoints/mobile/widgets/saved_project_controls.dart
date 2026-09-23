import '../localization/app_text.dart';
import 'package:flutter/material.dart';

import '../../../core/saved_projects/saved_project.dart';
import '../../../infrastructure/saved_projects/local_saved_project_store.dart';

final class SavedProjectControls extends StatelessWidget {
  const SavedProjectControls({
    super.key,
    required this.mode,
    required this.canSave,
    required this.onSave,
    required this.onLoad,
  });

  final SavedProjectMode mode;
  final bool canSave;
  final VoidCallback onSave;
  final ValueChanged<SavedProject> onLoad;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: appText(context, "開啟已儲存{0}", [appText(context, mode.label)]),
        onPressed: () async {
          final project = await showSavedProjectLibrary(context, mode: mode);
          if (project != null) onLoad(project);
        },
        icon: const Icon(Icons.folder_open_outlined),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: appText(context, "儲存目前{0}", [appText(context, mode.label)]),
        onPressed: canSave ? onSave : null,
        icon: const Icon(Icons.save_outlined),
      ),
    ],
  );
}

Future<String?> requestProjectName(
  BuildContext context, {
  String initialValue = '',
  String title = '儲存練習專案',
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _ProjectNameDialog(initialValue: initialValue, title: title),
  );
}

final class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({required this.initialValue, required this.title});

  final String initialValue;
  final String title;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

final class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(appText(context, widget.title)),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 40,
      decoration: InputDecoration(
        labelText: appText(context, "專案名稱"),
        hintText: appText(context, "例如：Hip Hop 第一段"),
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(appText(context, "取消")),
      ),
      FilledButton(onPressed: _submit, child: Text(appText(context, "儲存"))),
    ],
  );
}

Future<SavedProject?> showSavedProjectLibrary(
  BuildContext context, {
  required SavedProjectMode mode,
}) => showModalBottomSheet<SavedProject>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SavedProjectLibrary(mode: mode),
);

final class _SavedProjectLibrary extends StatefulWidget {
  const _SavedProjectLibrary({required this.mode});

  final SavedProjectMode mode;

  @override
  State<_SavedProjectLibrary> createState() => _SavedProjectLibraryState();
}

final class _SavedProjectLibraryState extends State<_SavedProjectLibrary> {
  final _store = LocalSavedProjectStore.instance;
  late Future<List<SavedProject>> _projects;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _projects = _store.list(mode: widget.mode);
  }

  Future<void> _rename(SavedProject project) async {
    final name = await requestProjectName(
      context,
      initialValue: project.name,
      title: appText(context, "重新命名專案"),
    );
    if (name == null) return;
    await _store.rename(project, name);
    if (mounted) setState(_reload);
  }

  Future<void> _delete(SavedProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(context, "刪除專案？")),
        content: Text(
          appText(context, "「{0}」將從已儲存專案中移除。媒體原始檔不會被刪除。", [project.name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(appText(context, "取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(appText(context, "刪除")),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(project.id);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.72,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  appText(context, "已儲存的{0}", [
                    appText(context, widget.mode.label),
                  ]),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: appText(context, "關閉"),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SavedProject>>(
            future: _projects,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(appText(context, "無法讀取專案：{0}", [snapshot.error])),
                );
              }
              final projects = snapshot.data ?? const [];
              if (projects.isEmpty) {
                return Center(child: Text(appText(context, "尚未儲存任何專案")));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                itemCount: projects.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final project = projects[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(project.name),
                      subtitle: Text(
                        appText(context, "更新於 {0}", [
                          _formatDate(project.updatedAt.toLocal()),
                        ]),
                      ),
                      onTap: () => Navigator.pop(context, project),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') _rename(project);
                          if (value == 'delete') _delete(project);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text(appText(context, "重新命名")),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(appText(context, "刪除")),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  String _formatDate(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
