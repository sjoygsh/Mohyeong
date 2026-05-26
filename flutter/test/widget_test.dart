import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/main.dart';

void main() {
  testWidgets('Landing screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MohyeongApp()));
    expect(find.text('Mohyeong'), findsOneWidget);
  });
}
