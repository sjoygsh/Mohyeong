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

const Object _sentinel = Object();
