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
