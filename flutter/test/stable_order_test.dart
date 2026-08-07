import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/category/model/category.dart';

/// Kotlin's `sortedWith` is a STABLE sort; Dart's `List.sort` is not. Every
/// comparator ported from the fork therefore needs an explicit tie-break, or
/// tied rows come back in whatever order the sort happens to land on and can
/// move between rebuilds with nothing having changed.
///
/// This pins the shared category comparator. `order` is genuinely not unique:
/// the reorder path redistributes whatever sibling positions already exist,
/// and a database carried over from the Kotlin app can hold duplicates.
Category _cat(int id, String name, int order) =>
    Category(id: id, name: name, order: order, flags: 0);

List<String> _names(List<Category> cats) =>
    (cats..sort(compareCategories)).map((c) => c.name).toList();

void main() {
  test('order decides while it differs', () {
    expect(
      _names([
        _cat(1, 'Third', 2),
        _cat(2, 'First', 0),
        _cat(3, 'Second', 1),
      ]),
      ['First', 'Second', 'Third'],
    );
  });

  test('categories sharing an order fall back to name', () {
    expect(
      _names([
        _cat(1, 'Charlie', 0),
        _cat(2, 'Alpha', 0),
        _cat(3, 'Bravo', 0),
      ]),
      ['Alpha', 'Bravo', 'Charlie'],
    );
  });

  test('categories sharing an order AND a name fall back to id', () {
    expect(
      ([
        _cat(9, 'Same', 0),
        _cat(3, 'Same', 0),
        _cat(7, 'Same', 0),
      ]..sort(compareCategories))
          .map((c) => c.id)
          .toList(),
      [3, 7, 9],
    );
  });

  test('the result does not depend on the order it was handed in', () {
    // The failure this guards is only visible above Dart's insertion-sort
    // threshold, so the list has to be long enough to reach the unstable
    // path.
    final forward = [
      for (var i = 0; i < 16; i++) _cat(i, 'Cat ${i.toString().padLeft(2, '0')}', 0),
    ];
    final backward = [...forward.reversed];
    expect(_names(backward), _names(forward));
    expect(
      _names(forward).first,
      'Cat 00',
      reason: 'a tie must resolve by name, not by arrival',
    );
  });
}
