import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/category/model/category.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'category_mapper.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final db.AppDatabase _db;

  Future<Category?> getById(int id) async {
    final row = await _db.getCategory(id).getSingleOrNull();
    return row == null ? null : CategoryMapper.fromRow(row);
  }

  /// All categories ordered by `sort`. The system "Uncategorized" row (id=0)
  /// is included; the UI decides whether to display it.
  Future<List<Category>> getAll() async {
    final rows = await _db.getCategories().get();
    return rows.map(CategoryMapper.fromRow).toList(growable: false);
  }

  Stream<List<Category>> watchAll() {
    return _db.getCategories().watch().map(
          (rows) => rows.map(CategoryMapper.fromRow).toList(growable: false),
        );
  }

  Future<List<Category>> getByMangaId(int mangaId) async {
    final rows = await _db.getCategoriesByMangaId(mangaId).get();
    return rows.map(CategoryMapper.fromRow).toList(growable: false);
  }

  Future<int> insert({
    required String name,
    required int order,
    required int flags,
    int? parentId,
  }) async {
    return _db.insertCategory(name, order, flags, parentId);
  }

  Future<void> deleteById(int id) async {
    await _db.deleteCategory(id);
  }

  /// The generated `updateCategory` signature got inferred as all-String due
  /// to `coalesce()` defeating Drift's type inference, so we issue a custom
  /// statement here instead. Each field is independently nullable -- pass
  /// null to keep the existing value.
  Future<void> update({
    required int id,
    String? name,
    int? order,
    int? flags,
  }) async {
    await _db.customUpdate(
      'UPDATE categories SET '
      'name = coalesce(?1, name), '
      'sort = coalesce(?2, sort), '
      'flags = coalesce(?3, flags) '
      'WHERE _id = ?4',
      variables: [
        Variable<String>(name),
        Variable<int>(order),
        Variable<int>(flags),
        Variable<int>(id),
      ],
      updates: {_db.categories},
    );
  }

  Future<void> updateParent({required int id, int? parentId}) async {
    await _db.updateParent(parentId, id);
  }

  /// Manga ids belonging to a specific category. Uncategorised manga
  /// (the implicit category 0) are surfaced as "every favourite without
  /// any row in `mangas_categories`" since they aren't represented as a
  /// physical row. Used by per-category bulk operations like the
  /// library-update affordance.
  Future<Set<int>> getMangaIdsInCategory(int categoryId) async {
    final sql = categoryId == 0
        ? '''
          SELECT _id AS manga_id FROM mangas
          WHERE favorite = 1
            AND _id NOT IN (SELECT manga_id FROM mangas_categories)
        '''
        : '''
          SELECT manga_id FROM mangas_categories WHERE category_id = ?1
        ''';
    final rows = await _db.customSelect(
      sql,
      variables: categoryId == 0 ? const [] : [Variable<int>(categoryId)],
      readsFrom: {_db.mangas, _db.mangasCategories},
    ).get();
    return rows.map((r) => r.read<int>('manga_id')).toSet();
  }

  /// Returns the set of category ids the manga is assigned to. The implicit
  /// system category (id=0) is omitted -- it is the absence-of-category
  /// state, not an explicit row.
  Future<Set<int>> getCategoryIdsForManga(int mangaId) async {
    final categories = await getByMangaId(mangaId);
    return categories
        .where((c) => !c.isSystemCategory)
        .map((c) => c.id)
        .toSet();
  }

  /// Replace the manga's category memberships with the given set. The
  /// trigger on `mangas_categories` will bump `mangas.version` per row,
  /// matching the Kotlin app's sync semantics.
  Future<void> setCategoriesForManga(int mangaId, Set<int> categoryIds) async {
    await _db.transaction(() async {
      await _db.deleteMangaCategoryByMangaId(mangaId);
      for (final categoryId in categoryIds) {
        await _db.insertMangaCategory(mangaId, categoryId);
      }
    });
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.watch(databaseProvider));
});
