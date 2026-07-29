import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/source/extension_repository.dart';
import 'package:mohyeong/data/source/installed_extension.dart';
import 'package:mohyeong/domain/source/model/manga_source.dart';
import 'package:mohyeong/presentation/browse/browse_screen.dart';
import 'package:mohyeong/presentation/tide/tide.dart';

/// Browse's three views sit behind a segmented control and build lazily —
/// Migrate must not exist until it is asked for, and the Extensions view
/// probes every origin on its first build, which is exactly the work the
/// shell's idle pre-warm must not trigger. This pins both.

InstalledExtension _ext(String id, String name, String lang, int version) =>
    InstalledExtension(
      id: id,
      name: name,
      lang: lang,
      baseUrl: 'https://$id.example',
      versionCode: version,
      supportsLatest: true,
      sourcePath: '/tmp/$id/source.js',
      installUrl: null,
    );

class _FakeExtensionRepository implements ExtensionRepository {
  _FakeExtensionRepository(this.extensions);

  final List<InstalledExtension> extensions;

  /// Set when the Extensions view's first build fires its origin probe.
  bool checkedForUpdates = false;

  @override
  Stream<List<InstalledExtension>> watchInstalled() => Stream.value(extensions);

  @override
  Future<List<InstalledExtension>> listInstalled() async => extensions;

  @override
  Future<Set<String>> checkForUpdates() async {
    checkedForUpdates = true;
    return const <String>{};
  }

  @override
  Future<MangaSource> getSource(String id) async => throw UnimplementedError();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_FakeExtensionRepository> _pumpBrowse(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _FakeExtensionRepository([
    _ext('asura', 'Asura Scans', 'en', 12),
    _ext('mangadex', 'MangaDex', 'all', 7),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [extensionRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: BrowseScreen()),
    ),
  );
  await _pump(tester);
  return repo;
}

void main() {
  testWidgets('Sources lists installed sources behind a segmented control',
      (WidgetTester tester) async {
    final repo = await _pumpBrowse(tester);

    expect(find.byType(TideSegmented), findsOneWidget);
    expect(find.text('Local source'), findsOneWidget);
    expect(find.text('Asura Scans'), findsOneWidget);
    expect(find.text('MangaDex'), findsOneWidget);

    // Sources is the opening view, so the Extensions probe must not have run.
    expect(repo.checkedForUpdates, isFalse);
    // …and Migrate has not been built at all.
    expect(find.text('Install extension'), findsNothing);
  });

  testWidgets('switching to Extensions builds it, and only then probes',
      (WidgetTester tester) async {
    final repo = await _pumpBrowse(tester);

    await tester.tap(find.text('Extensions'));
    await _pump(tester);

    expect(repo.checkedForUpdates, isTrue);
    expect(find.text('Install extension'), findsOneWidget);
    expect(find.text('INSTALLED'), findsOneWidget);
    // Language and version are separate tags now, with the host as plain text
    // beside them — one run of `EN · v12 · asura.example` read as a single
    // grey string rather than as three independent facts.
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('v12'), findsOneWidget);
    expect(find.text('asura.example'), findsWidgets);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('v7'), findsOneWidget);
    expect(find.text('mangadex.example'), findsWidgets);
    // Nothing is waiting, so the actionable section stays off the screen
    // entirely rather than showing an empty header.
    expect(find.text('UPDATE AVAILABLE'), findsNothing);
  });

  testWidgets('a source row names the site it reads from',
      (WidgetTester tester) async {
    await _pumpBrowse(tester);

    // "EN" alone was a two-letter caption; the domain is what actually tells
    // two similarly-named sources apart.
    expect(find.text('EN · asura.example'), findsOneWidget);
    expect(find.text('ALL · mangadex.example'), findsOneWidget);
  });

  testWidgets('a source with no reachable logo keeps its sigil',
      (WidgetTester tester) async {
    await _pumpBrowse(tester);

    // No network (and no support directory) under test, so every row falls
    // back to the sigil: the source's initial over a gradient from its id.
    // Two different sources, two different letters.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
  });
}
