import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../domain/category/model/category.dart';

/// Manage the user-defined library categories. The implicit system
/// category (id=0, "Uncategorized") is hidden -- the SQL trigger blocks
/// deleting it and the Kotlin app never exposed it here.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(categoryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptCreate(context, repo),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: StreamBuilder<List<Category>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(text: 'Failed to load categories: ${snap.error}');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snap.data!
              .where((c) => !c.isSystemCategory)
              .toList(growable: false);
          if (categories.isEmpty) {
            return const _Message(
              text: 'You have no categories. Tap the plus button to create '
                  'one for organizing your library.',
            );
          }
          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: categories.length,
            onReorderItem: (oldIndex, newIndex) =>
                _onReorder(repo, categories, oldIndex, newIndex),
            itemBuilder: (context, i) {
              final c = categories[i];
              return ListTile(
                key: ValueKey(c.id),
                title: Text(c.name),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename category',
                      onPressed: () => _promptRename(context, repo, c),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, repo, c),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onReorder(
    CategoryRepository repo,
    List<Category> visible,
    int oldIndex,
    int newIndex,
  ) async {
    // onReorderItem already gives us the new index in the post-removal
    // list, so no off-by-one normalization is needed.
    if (newIndex == oldIndex) return;
    final reordered = [...visible];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    // The system category (order=0) is hidden but still exists; preserve
    // its slot by starting user categories at order=1.
    for (var i = 0; i < reordered.length; i++) {
      await repo.update(id: reordered[i].id, order: i + 1);
    }
  }

  Future<void> _promptCreate(
    BuildContext context,
    CategoryRepository repo,
  ) async {
    final existing = await repo.getAll();
    if (!context.mounted) return;
    final taken = {
      for (final c in existing)
        if (!c.isSystemCategory) c.name.toLowerCase(),
    };
    final name = await _promptForName(
      context,
      title: 'Add category',
      confirmLabel: 'Add',
      takenNames: taken,
    );
    if (name == null || name.isEmpty) return;
    // Append at the end, after the highest existing order.
    final maxOrder = existing.fold<int>(0, (m, c) => c.order > m ? c.order : m);
    await repo.insert(name: name, order: maxOrder + 1, flags: 0);
  }

  Future<void> _promptRename(
    BuildContext context,
    CategoryRepository repo,
    Category category,
  ) async {
    final existing = await repo.getAll();
    if (!context.mounted) return;
    final taken = {
      for (final c in existing)
        if (!c.isSystemCategory && c.id != category.id) c.name.toLowerCase(),
    };
    final name = await _promptForName(
      context,
      title: 'Rename category',
      confirmLabel: 'OK',
      initialValue: category.name,
      takenNames: taken,
    );
    if (name == null || name.isEmpty || name == category.name) return;
    await repo.update(id: category.id, name: name);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CategoryRepository repo,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category'),
        content: Text('Do you wish to delete the category "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.deleteById(category.id);
    }
  }

  Future<String?> _promptForName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initialValue = '',
    Set<String> takenNames = const {},
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialValue: initialValue,
        takenNames: takenNames,
      ),
    );
  }
}

/// Create/rename dialog with the same inline validation as Kotlin's
/// CategoryCreateDialog/CategoryRenameDialog: the confirm button stays
/// disabled until the name is non-empty, changed (rename) and unique.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
    required this.takenNames,
  });

  final String title;
  final String confirmLabel;
  final String initialValue;
  final Set<String> takenNames;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  bool get _isDuplicate =>
      _name.isNotEmpty && widget.takenNames.contains(_name.toLowerCase());

  bool get _canConfirm =>
      _name.isNotEmpty && !_isDuplicate && _name != widget.initialValue;

  String? get _supportText {
    if (_name.isEmpty) return '*required';
    if (_isDuplicate) return 'A category with this name already exists!';
    return null;
  }

  void _submit() {
    if (_canConfirm) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Name',
          errorText: _supportText,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canConfirm ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
