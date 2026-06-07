import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../data/preferences/typed_preferences.dart';
import '../../domain/category/model/category.dart';

/// User categories for the category include/exclude pickers. System
/// categories (the "Uncategorized" bucket) are filtered out — Mihon's
/// include/exclude lists operate on user-defined categories only.
final userCategoriesProvider = StreamProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll().map(
        (cats) => cats.where((c) => !c.isSystemCategory).toList(),
      ),
);

/// Settings tile + dialog for a category include/exclude set. The stored
/// value is a [Set] of category-id strings (Mihon-compatible). The subtitle
/// renders the selected category names, or [emptyLabel] when the set is
/// empty. Shared by Settings → Downloads (auto-download) and Settings →
/// Library (global update).
class CategoryFilterTile extends ConsumerWidget {
  const CategoryFilterTile({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.provider,
  });

  final String title;
  final String emptyLabel;
  final NotifierProvider<StringSetPrefNotifier, Set<String>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(provider);
    final categoriesAsync = ref.watch(userCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];

    String subtitle;
    if (selected.isEmpty) {
      subtitle = emptyLabel;
    } else {
      final names = categories
          .where((c) => selected.contains(c.id.toString()))
          .map((c) => c.name)
          .toList();
      subtitle = names.isEmpty ? emptyLabel : names.join(', ');
    }

    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      enabled: categories.isNotEmpty,
      onTap: () async {
        final picked = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _CategoryFilterDialog(
            title: title,
            categories: categories,
            initial: selected,
          ),
        );
        if (picked != null) {
          await ref.read(provider.notifier).set(picked);
        }
      },
    );
  }
}

/// Settings tile + dialog for a single tri-state category set: each category
/// is neutral, included, or excluded. Backed by two [Set]-of-id-string
/// providers ([includedProvider] / [excludedProvider]). Mirrors Kotlin's
/// `TriStateListDialog` + `getCategoriesLabel` subtitle ("Include: …\nExclude:
/// …"). Shared by Settings → Library (global update) and Settings → Downloads
/// (auto-download).
class CategoryTriStateTile extends ConsumerWidget {
  const CategoryTriStateTile({
    super.key,
    required this.title,
    required this.includedProvider,
    required this.excludedProvider,
    this.message,
    this.enabled = true,
  });

  final String title;
  final NotifierProvider<StringSetPrefNotifier, Set<String>> includedProvider;
  final NotifierProvider<StringSetPrefNotifier, Set<String>> excludedProvider;

  /// Explanatory line shown above the category rows in the dialog.
  final String? message;

  /// Additional gate on top of "has user categories" (e.g. the Downloads
  /// screen disables the tile when auto-download is off).
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final included = ref.watch(includedProvider);
    final excluded = ref.watch(excludedProvider);
    final categories =
        ref.watch(userCategoriesProvider).valueOrNull ?? const <Category>[];
    return ListTile(
      title: Text(title),
      subtitle: Text(categoriesLabel(categories, included, excluded)),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled && categories.isNotEmpty,
      onTap: () async {
        final result = await showDialog<TriStateCategoryResult>(
          context: context,
          builder: (_) => _CategoryTriStateDialog(
            title: title,
            message: message,
            categories: categories,
            included: included,
            excluded: excluded,
          ),
        );
        if (result != null) {
          await ref.read(includedProvider.notifier).set(result.included);
          await ref.read(excludedProvider.notifier).set(result.excluded);
        }
      },
    );
  }
}

/// Two-line "Include: …\nExclude: …" subtitle, a 1:1 port of Kotlin's
/// `getCategoriesLabel`.
String categoriesLabel(
  List<Category> all,
  Set<String> included,
  Set<String> excluded,
) {
  final inc = all.where((c) => included.contains(c.id.toString())).toList();
  final exc = all.where((c) => excluded.contains(c.id.toString())).toList();
  final allExcluded = all.isNotEmpty && exc.length == all.length;

  final String incText;
  if (inc.isNotEmpty && inc.length != all.length) {
    incText = inc.map((c) => c.name).join(', ');
  } else if (all.isNotEmpty && inc.length == all.length) {
    incText = 'All';
  } else if (allExcluded) {
    incText = 'None';
  } else {
    incText = 'All';
  }

  final String excText;
  if (exc.isEmpty) {
    excText = 'None';
  } else if (allExcluded) {
    excText = 'All';
  } else {
    excText = exc.map((c) => c.name).join(', ');
  }

  return 'Include: $incText\nExclude: $excText';
}

class TriStateCategoryResult {
  const TriStateCategoryResult(this.included, this.excluded);
  final Set<String> included;
  final Set<String> excluded;
}

class _CategoryTriStateDialog extends StatefulWidget {
  const _CategoryTriStateDialog({
    required this.title,
    required this.message,
    required this.categories,
    required this.included,
    required this.excluded,
  });

  final String title;
  final String? message;
  final List<Category> categories;
  final Set<String> included;
  final Set<String> excluded;

  @override
  State<_CategoryTriStateDialog> createState() =>
      _CategoryTriStateDialogState();
}

class _CategoryTriStateDialogState extends State<_CategoryTriStateDialog> {
  late final Set<String> _included = {...widget.included};
  late final Set<String> _excluded = {...widget.excluded};

  // neutral -> include -> exclude -> neutral
  void _cycle(String id) {
    setState(() {
      if (_included.contains(id)) {
        _included.remove(id);
        _excluded.add(id);
      } else if (_excluded.contains(id)) {
        _excluded.remove(id);
      } else {
        _included.add(id);
      }
    });
  }

  IconData _iconFor(String id) {
    if (_included.contains(id)) return Icons.check_box;
    if (_excluded.contains(id)) return Icons.indeterminate_check_box;
    return Icons.check_box_outline_blank;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(widget.message!),
              ),
            for (final c in widget.categories)
              ListTile(
                leading: Icon(_iconFor(c.id.toString())),
                title: Text(c.name),
                onTap: () => _cycle(c.id.toString()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            TriStateCategoryResult(_included, _excluded),
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _CategoryFilterDialog extends StatefulWidget {
  const _CategoryFilterDialog({
    required this.title,
    required this.categories,
    required this.initial,
  });

  final String title;
  final List<Category> categories;
  final Set<String> initial;

  @override
  State<_CategoryFilterDialog> createState() => _CategoryFilterDialogState();
}

class _CategoryFilterDialogState extends State<_CategoryFilterDialog> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in widget.categories)
              CheckboxListTile(
                title: Text(c.name),
                value: _selected.contains(c.id.toString()),
                onChanged: (checked) => setState(() {
                  final key = c.id.toString();
                  if (checked ?? false) {
                    _selected.add(key);
                  } else {
                    _selected.remove(key);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
