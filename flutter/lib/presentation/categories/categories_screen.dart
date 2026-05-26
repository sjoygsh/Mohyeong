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
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _promptCreate(context, repo),
        child: const Icon(Icons.add),
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
            return const _Message(text: 'No categories yet. Tap + to add one.');
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
                trailing: PopupMenuButton<_RowAction>(
                  onSelected: (action) {
                    switch (action) {
                      case _RowAction.rename:
                        _promptRename(context, repo, c);
                      case _RowAction.delete:
                        _confirmDelete(context, repo, c);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _RowAction.rename,
                      child: Text('Rename'),
                    ),
                    PopupMenuItem(
                      value: _RowAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                ),
                onTap: () => _promptRename(context, repo, c),
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
    final name = await _promptForName(context, title: 'New category');
    if (name == null || name.isEmpty) return;
    final existing = await repo.getAll();
    // Append at the end, after the highest existing order.
    final maxOrder = existing.fold<int>(0, (m, c) => c.order > m ? c.order : m);
    await repo.insert(name: name, order: maxOrder + 1, flags: 0);
  }

  Future<void> _promptRename(
    BuildContext context,
    CategoryRepository repo,
    Category category,
  ) async {
    final name = await _promptForName(
      context,
      title: 'Rename category',
      initialValue: category.name,
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
        title: Text('Delete "${category.name}"?'),
        content: const Text(
          'Manga assigned to this category will be moved to Uncategorized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

enum _RowAction { rename, delete }

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
