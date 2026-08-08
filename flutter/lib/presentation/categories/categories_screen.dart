// ===========================================================================
// Tide categories.
//
// A tree, drawn as a tree: depth is indent plus a lit tick on the spine, so a
// child reads as belonging to the row above it rather than as a row that
// happens to start further right. Everything that used to be an AlertDialog —
// create, rename, reparent, delete — is a sheet, and the name sheets keep the
// inline validation that stops you making a duplicate.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../domain/category/model/category.dart';
import '../tide/tide.dart';
import '../util/user_message.dart';
import '../util/open_link.dart';

/// Manage the user-defined library categories. The implicit system
/// category (id=0, "Uncategorized") is hidden -- the SQL trigger blocks
/// deleting it and the Kotlin app never exposed it here.
///
/// Categories can be nested into a parent/child hierarchy: the list is shown
/// flattened in pre-order with each level indented, and a "set parent" action
/// reparents a category (rejecting moves that would create a cycle). Mirrors
/// Kotlin's CategoryScreen + CategoryParentPickerDialog + SetCategoryParent.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(categoryRepositoryProvider);
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          TideRise(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TideHeader(
              title: 'Categories',
              actions: [
                TideIconButton(
                  icon: Icons.help_outlined,
                  onTap: () => openLink(context, helpUrl('categories')),
                ),
                const SizedBox(width: 9),
                TideIconButton(
                  icon: Icons.add,
                  onTap: () => _promptCreate(context, repo),
                ),
              ],
            ),
            Expanded(
              child: StreamBuilder<List<Category>>(
                stream: repo.watchAll(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _Message(
                      text: userMessage(snap.error!, fallback: 'Couldn\'t load your categories.'),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: TideSpinner());
                  }
                  final categories = snap.data!
                      .where((c) => !c.isSystemCategory)
                      .toList(growable: false);
                  if (categories.isEmpty) {
                    return const TideEmpty(
                      title: 'No categories yet',
                    );
                  }
                  final flattened = _flattenHierarchy(categories);
                  return ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: flattened.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        _onReorder(repo, flattened, oldIndex, newIndex),
                    // The default proxy wraps the dragged row in an elevated
                    // Material slab, which on glass reads as a different
                    // widget picking itself up. Lift it instead.
                    proxyDecorator: (child, index, animation) =>
                        _LiftedRow(animation: animation, child: child),
                    itemBuilder: (context, i) {
                      final entry = flattened[i];
                      return Padding(
                        key: ValueKey(entry.category.id),
                        padding: EdgeInsets.only(
                          left: entry.depth * 18.0,
                          bottom: 8,
                        ),
                        child: _CategoryRow(
                          index: i,
                          entry: entry,
                          onSetParent: () => _promptSetParent(
                            context,
                            repo,
                            entry.category,
                            categories,
                          ),
                          onRename: () =>
                              _promptRename(context, repo, entry.category),
                          onDelete: () =>
                              _confirmDelete(context, repo, entry.category),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }

  /// Sibling-constrained reorder ported from Kotlin's `ReorderCategory`: a drag
  /// only changes order within the dragged category's own parent group, and
  /// reuses that group's existing `sort` slots so unrelated categories are left
  /// untouched. `newIndex` is the post-removal flat-list index.
  Future<void> _onReorder(
    CategoryRepository repo,
    List<_CategoryWithDepth> flattened,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex == oldIndex) return;
    final category = flattened[oldIndex].category;
    final all = (await repo.getAll())
        .where((c) => !c.isSystemCategory)
        .toList(growable: false);
    final siblings =
        all.where((c) => c.parentId == category.parentId).toList();
    final currentSiblingIndex = siblings.indexWhere((c) => c.id == category.id);
    if (currentSiblingIndex == -1) return;

    // Translate the flat newIndex into a sibling index by counting how many
    // siblings appear before the target position.
    final flatIndex = all.indexWhere((c) => c.id == category.id);
    final movingForward = newIndex > flatIndex;
    final upper = movingForward
        ? (newIndex + 1).clamp(0, all.length)
        : newIndex.clamp(0, all.length);
    var targetSiblingIndex = all
        .sublist(0, upper)
        .where((c) => c.parentId == category.parentId && c.id != category.id)
        .length;
    targetSiblingIndex = targetSiblingIndex.clamp(0, siblings.length - 1);
    if (currentSiblingIndex == targetSiblingIndex) return;

    siblings.insert(targetSiblingIndex, siblings.removeAt(currentSiblingIndex));

    // Preserve the original sort slots used by this sibling group and
    // redistribute them in the new order.
    final originalSorts = all
        .where((c) => c.parentId == category.parentId)
        .map((c) => c.order)
        .toList()
      ..sort();
    for (var i = 0; i < siblings.length; i++) {
      final order = i < originalSorts.length ? originalSorts[i] : i;
      if (siblings[i].order != order) {
        await repo.update(id: siblings[i].id, order: order);
      }
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
      confirmLabel: 'Rename',
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
    final confirmed = await showTideSheet<bool>(
      context,
      (_) => TideConfirmSheet(
        title: 'Delete category',
        message: 'Do you wish to delete the category "${category.name}"? '
            'The entries in it stay in your library.',
        confirmLabel: 'Delete',
      ),
    );
    if (confirmed == true) {
      await repo.deleteById(category.id);
    }
  }

  /// Opens the parent picker and applies the choice with cycle protection.
  Future<void> _promptSetParent(
    BuildContext context,
    CategoryRepository repo,
    Category category,
    List<Category> allCategories,
  ) async {
    final result = await showTideSheet<_ParentPickResult>(
      context,
      (_) => _ParentSheet(target: category, allCategories: allCategories),
    );
    if (result == null) return; // dismissed
    if (!context.mounted) return;
    await _setParent(context, repo, category, result.parentId);
  }

  /// Reparents [category] to [parentId] (null == top level), rejecting moves
  /// that would create a cycle. 1:1 with Kotlin's `SetCategoryParent`.
  Future<void> _setParent(
    BuildContext context,
    CategoryRepository repo,
    Category category,
    int? parentId,
  ) async {
    if (category.isSystemCategory) return; // InvalidTarget
    final sanitized = parentId == Category.uncategorizedId ? null : parentId;
    if (sanitized == category.id) {
      _showCycleError(context);
      return;
    }
    if (sanitized != null) {
      final all = await repo.getAll();
      final byId = {for (final c in all) c.id: c};
      // Walk up from the proposed parent; hitting the category (or a
      // pre-existing cycle) means the move is illegal.
      int? cursor = sanitized;
      final visited = <int>{};
      while (cursor != null) {
        if (cursor == category.id || !visited.add(cursor)) {
          if (context.mounted) _showCycleError(context);
          return;
        }
        cursor = byId[cursor]?.parentId;
      }
    }
    await repo.updateParent(id: category.id, parentId: sanitized);
  }

  void _showCycleError(BuildContext context) {
    TideToast.of(context).show(
      "Can't make a category a child of itself or its descendants",
    );
  }

  Future<String?> _promptForName(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String initialValue = '',
    Set<String> takenNames = const {},
  }) {
    return showTideSheet<String>(
      context,
      (_) => _NameSheet(
        title: title,
        confirmLabel: confirmLabel,
        initialValue: initialValue,
        takenNames: takenNames,
      ),
    );
  }
}

/// One category: drag handle, depth tick, name, and its three actions.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.index,
    required this.entry,
    required this.onSetParent,
    required this.onRename,
    required this.onDelete,
  });

  final int index;
  final _CategoryWithDepth entry;
  final VoidCallback onSetParent;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final nested = entry.depth > 0;
    return TideGlass(
      radius: TideRadius.pane,
      tintTop: nested ? 0.055 : 0.075,
      tintBottom: nested ? 0.02 : 0.026,
      highlight: nested ? 0.11 : 0.14,
      border: nested ? 0.07 : 0.09,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: SizedBox(
              width: 34,
              height: 38,
              child: Icon(
                Icons.drag_handle,
                size: 18,
                color: TideColors.textAt(0.32),
              ),
            ),
          ),
          if (nested)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                Icons.subdirectory_arrow_right,
                size: 15,
                color: TideColors.accent.withValues(alpha: 0.65),
              ),
            ),
          Expanded(
            child: Text(
              entry.category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TideText.title(
                color: nested ? TideColors.textAt(0.82) : TideColors.text,
              ),
            ),
          ),
          _RowAction(icon: Icons.account_tree_outlined, onTap: onSetParent),
          _RowAction(icon: Icons.edit_outlined, onTap: onRename),
          _RowAction(icon: Icons.delete_outlined, onTap: onDelete),
        ],
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 38,
        child: Icon(icon, size: 16, color: TideColors.textAt(0.42)),
      ),
    );
  }
}

/// The dragged row, lifted off the ground rather than turned into a slab.
class _LiftedRow extends StatelessWidget {
  const _LiftedRow({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TideRadius.pane),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5 * t),
                  blurRadius: 30 * t,
                  offset: Offset(0, 12 * t),
                ),
              ],
            ),
            child: Material(color: Colors.transparent, child: child),
          ),
        );
      },
    );
  }
}

/// A category paired with its depth in the hierarchy after flattening (root=0).
class _CategoryWithDepth {
  const _CategoryWithDepth(this.category, this.depth);

  final Category category;
  final int depth;
}

/// Flattens [categories] into a pre-order traversal of the parent/child tree.
/// Cycles, broken parent references, and a parent pointing at the system
/// category are all tolerated by promoting the affected node to a root. Ported
/// from Kotlin's `CategoryTree.flattenedHierarchy`.
List<_CategoryWithDepth> _flattenHierarchy(List<Category> categories) {
  if (categories.isEmpty) return const [];
  final byId = {for (final c in categories) c.id: c};
  final childrenByParent = <int?, List<Category>>{};
  for (final cat in categories) {
    var parent = cat.parentId;
    // A null, system-category, or dangling parent reference is treated as root.
    if (parent != null &&
        (parent == Category.uncategorizedId || !byId.containsKey(parent))) {
      parent = null;
    }
    childrenByParent.putIfAbsent(parent, () => <Category>[]).add(cat);
  }
  // Sort each sibling group for deterministic display. `order` alone is not
  // deterministic — it is not unique, and Dart's sort is not stable — so this
  // goes through [compareCategories], which carries a name/id tail.
  for (final list in childrenByParent.values) {
    list.sort(compareCategories);
  }

  final result = <_CategoryWithDepth>[];
  final visited = <int>{};
  void dfs(Category node, int depth) {
    if (!visited.add(node.id)) return;
    result.add(_CategoryWithDepth(node, depth));
    for (final child in childrenByParent[node.id] ?? const <Category>[]) {
      dfs(child, depth + 1);
    }
  }

  for (final root in childrenByParent[null] ?? const <Category>[]) {
    dfs(root, 0);
  }
  // Any node orphaned by a cycle is emitted at root depth.
  for (final cat in categories) {
    if (!visited.contains(cat.id)) dfs(cat, 0);
  }
  return result;
}

/// Result of the parent picker: wraps the chosen parent id (null == top level)
/// so a `null` sheet return can be distinguished from "No parent" selected.
class _ParentPickResult {
  const _ParentPickResult(this.parentId);
  final int? parentId;
}

/// Picker for a category's parent. Excludes the target and all of its
/// descendants (choosing one would create a cycle) and indents candidates by
/// hierarchy depth. Mirrors Kotlin's `CategoryParentPickerDialog`.
class _ParentSheet extends StatefulWidget {
  const _ParentSheet({required this.target, required this.allCategories});

  final Category target;
  final List<Category> allCategories;

  @override
  State<_ParentSheet> createState() => _ParentSheetState();
}

class _ParentSheetState extends State<_ParentSheet> {
  late int? _selected = widget.target.parentId;

  /// The target plus every category reachable beneath it.
  Set<int> get _descendantIds {
    final childrenByParent = <int?, List<Category>>{};
    for (final c in widget.allCategories) {
      childrenByParent.putIfAbsent(c.parentId, () => <Category>[]).add(c);
    }
    final collected = <int>{widget.target.id};
    final stack = <int>[widget.target.id];
    while (stack.isNotEmpty) {
      final cursor = stack.removeLast();
      for (final child in childrenByParent[cursor] ?? const <Category>[]) {
        if (collected.add(child.id)) stack.add(child.id);
      }
    }
    return collected;
  }

  @override
  Widget build(BuildContext context) {
    final excluded = _descendantIds;
    final candidates = _flattenHierarchy(
      widget.allCategories
          .where((c) => !excluded.contains(c.id))
          .toList(growable: false),
    );
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Set parent', style: TideText.display(21)),
          const SizedBox(height: 4),
          Text(
            'Where "${widget.target.name}" sits in the tree.',
            style: TideText.caption(size: 12.5, opacity: 0.45),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ParentOption(
                    label: 'No parent — top level',
                    depth: 0,
                    selected: _selected == null,
                    onTap: () => setState(() => _selected = null),
                  ),
                  for (final entry in candidates) ...[
                    const SizedBox(height: 7),
                    _ParentOption(
                      label: entry.category.name,
                      depth: entry.depth,
                      selected: _selected == entry.category.id,
                      onTap: () =>
                          setState(() => _selected = entry.category.id),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TideButton(
                  label: 'Set',
                  primary: true,
                  onTap: () => Navigator.of(context)
                      .pop(_ParentPickResult(_selected)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParentOption extends StatelessWidget {
  const _ParentOption({
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: TideGlass(
        radius: TideRadius.row,
        tintTop: selected ? 0.13 : 0.06,
        tintBottom: selected ? 0.05 : 0.02,
        highlight: selected ? 0.20 : 0.12,
        border: selected ? 0.20 : 0.08,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (depth > 0) ...[
              Icon(
                Icons.subdirectory_arrow_right,
                size: 14,
                color: TideColors.accent.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TideText.title(
                  size: 13.5,
                  color: selected ? TideColors.textBright : TideColors.text,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  size: 17, color: TideColors.accent),
          ],
        ),
      ),
    );
  }
}

/// Create/rename sheet with the same inline validation as Kotlin's
/// CategoryCreateDialog/CategoryRenameDialog: the confirm stays inert until
/// the name is non-empty, changed (rename) and unique.
class _NameSheet extends StatefulWidget {
  const _NameSheet({
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
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
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
    if (_isDuplicate) return 'A category with this name already exists';
    return null;
  }

  void _submit() {
    if (_canConfirm) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    final error = _supportText;
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: TideText.display(21)),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: TideGlass(
              radius: TideRadius.panel,
              tintTop: 0.09,
              tintBottom: 0.03,
              highlight: 0.16,
              // The field itself carries the error, in the accent's warning
              // register rather than as a line of red text below it.
              border: error == null ? 0.11 : 0.0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  cursorColor: TideColors.accent,
                  style: TideText.title(size: 14.5),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Name',
                    hintStyle: TideText.title(
                      size: 14.5,
                      color: TideColors.textAt(0.33),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TideText.caption(size: 12, opacity: 0.9)
                  .copyWith(color: TideColors.danger),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: _canConfirm ? 1 : 0.4,
                  child: TideButton(
                    label: widget.confirmLabel,
                    primary: true,
                    onTap: _submit,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TideText.body(),
        ),
      ),
    );
  }
}
