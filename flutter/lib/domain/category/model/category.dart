/// Mirror of `tachiyomi.domain.category.model.Category`.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.order,
    required this.flags,
    this.parentId,
  });

  final int id;
  final String name;
  final int order;
  final int flags;
  final int? parentId;

  /// id == 0 is the implicit "Uncategorized" bucket every Mihon install ships
  /// with; deleting it is blocked by a SQL trigger.
  bool get isSystemCategory => id == uncategorizedId;

  /// Top-level categories either have no parent or point at the system root.
  bool get isTopLevel => parentId == null || parentId == uncategorizedId;

  Category copyWith({
    int? id,
    String? name,
    int? order,
    int? flags,
    Object? parentId = _sentinel,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
      flags: flags ?? this.flags,
      parentId:
          identical(parentId, _sentinel) ? this.parentId : parentId as int?,
    );
  }

  static const int uncategorizedId = 0;
}

/// Display order for a set of categories: the user's `order`, then name, then
/// id.
///
/// The tail is not decoration. `order` is not unique — the reorder path
/// redistributes whatever sibling positions already exist, and a database
/// carried over from the Kotlin app can hold duplicates — and Dart's
/// `List.sort` is NOT stable (Kotlin's `sortedWith`, which every one of these
/// lists was ported from, is). Sorting on `order` alone therefore let tied
/// categories swap places between rebuilds, in the category chips and in the
/// hierarchy's sibling groups alike.
int compareCategories(Category a, Category b) {
  final byOrder = a.order.compareTo(b.order);
  if (byOrder != 0) return byOrder;
  final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byName != 0 ? byName : a.id.compareTo(b.id);
}

const Object _sentinel = Object();
