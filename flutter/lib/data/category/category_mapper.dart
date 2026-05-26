import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart' as db;
import '../../domain/category/model/category.dart';

class CategoryMapper {
  const CategoryMapper._();

  static Category fromRow(db.Category row) => Category(
        id: row.id,
        name: row.name,
        order: row.sort,
        flags: row.flags,
        parentId: row.parentId,
      );

  static db.CategoriesCompanion toCompanion(Category category) {
    return db.CategoriesCompanion.insert(
      id: Value(category.id),
      name: category.name,
      sort: category.order,
      flags: category.flags,
      parentId: Value(category.parentId),
    );
  }
}
