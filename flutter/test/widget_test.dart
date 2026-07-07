import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/library/library_repository.dart';
import 'package:mohyeong/data/library/library_update_preference.dart';
import 'package:mohyeong/data/library/library_update_scheduler.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/onboarding/onboarding_preferences.dart';
import 'package:mohyeong/data/security/security_preferences.dart';
import 'package:mohyeong/data/source/extension_repository.dart';
import 'package:mohyeong/data/source/installed_extension.dart';
import 'package:mohyeong/data/sync/sync_preferences.dart';
import 'package:mohyeong/data/backup/backup_scheduler.dart';
import 'package:mohyeong/data/sync/sync_scheduler.dart';
import 'package:mohyeong/data/updates/updates_repository.dart';
import 'package:mohyeong/domain/category/model/category.dart';
import 'package:mohyeong/domain/library/model/library_item.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/source/model/manga_source.dart';
import 'package:mohyeong/main.dart';

class _FakeMangaRepository implements MangaRepository {
  @override
  Stream<List<Manga>> watchFavorites() => Stream.value(const <Manga>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistoryRepository implements HistoryRepository {
  @override
  Future<int> totalReadDurationMs() async => 0;

  @override
  Stream<List<HistoryWithContext>> watchRecent({int limit = 200}) =>
      Stream.value(const <HistoryWithContext>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUpdatesRepository implements UpdatesRepository {
  @override
  Stream<List<LibraryUpdate>> watchAll() =>
      Stream.value(const <LibraryUpdate>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test-only scheduler that swallows reschedule / runOnce calls. Avoids
/// hitting the workmanager MethodChannel (which has no platform implementation
/// in the flutter_test environment, so a real call throws).
class _FakeLibraryUpdateScheduler implements LibraryUpdateScheduler {
  @override
  Future<void> reschedule(LibraryUpdateInterval interval) async {}

  @override
  Future<void> runOnce() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test-only sync scheduler that swallows reschedule / runOnce calls for the
/// same reason as [_FakeLibraryUpdateScheduler] — the workmanager MethodChannel
/// has no platform implementation under flutter_test.
class _FakeSyncScheduler implements SyncScheduler {
  @override
  Future<void> reschedule({
    required bool enabled,
    required int intervalHours,
    required SyncService service,
  }) async {}

  @override
  Future<void> runOnce() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test-only backup scheduler — same workmanager-avoidance as the fakes
/// above.
class _FakeBackupScheduler implements BackupScheduler {
  @override
  Future<void> reschedule(int intervalHours) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryRepository implements LibraryRepository {
  @override
  Stream<List<LibraryItem>> watchAll() => Stream.value(const <LibraryItem>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Stream<List<Category>> watchAll() => Stream.value(const <Category>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExtensionRepository implements ExtensionRepository {
  @override
  Stream<List<InstalledExtension>> watchInstalled() =>
      Stream.value(const <InstalledExtension>[]);

  @override
  Future<List<InstalledExtension>> listInstalled() async =>
      const <InstalledExtension>[];

  @override
  Future<MangaSource> getSource(String id) async =>
      throw UnimplementedError();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Home shell renders all five top-level tabs',
      (WidgetTester tester) async {
    // The home shell sits behind AuthGate + OnboardingGate, which both read
    // these flags from disk before revealing their child. Seed them so the
    // gates resolve to "unlocked" + "onboarding done" and render HomeScreen.
    SharedPreferences.setMockInitialValues({
      onboardingCompleteKey: true,
      appLockKey: false,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mangaRepositoryProvider.overrideWithValue(_FakeMangaRepository()),
          libraryRepositoryProvider
              .overrideWithValue(_FakeLibraryRepository()),
          categoryRepositoryProvider
              .overrideWithValue(_FakeCategoryRepository()),
          historyRepositoryProvider.overrideWithValue(_FakeHistoryRepository()),
          updatesRepositoryProvider.overrideWithValue(_FakeUpdatesRepository()),
          extensionRepositoryProvider
              .overrideWithValue(_FakeExtensionRepository()),
          libraryUpdateSchedulerProvider
              .overrideWithValue(_FakeLibraryUpdateScheduler()),
          syncSchedulerProvider.overrideWithValue(_FakeSyncScheduler()),
          backupSchedulerProvider.overrideWithValue(_FakeBackupScheduler()),
        ],
        child: const MohyeongApp(),
      ),
    );
    // Pump a few frames so the gates' async disk reads (SharedPreferences +
    // the typed-pref Notifiers) settle and the empty-state StreamBuilder
    // resolves its first event, revealing the home shell.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // AppBar title for the default (Library) tab.
    expect(find.text('Library'), findsWidgets);
    // The other four tab labels should be present in the NavigationBar.
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // The library should be in its empty state since the fake repo returns [].
    expect(find.text('Your library is empty.'), findsOneWidget);

    // Tabs build lazily on first visit (the IndexedStack starts them as
    // placeholders), so the Updates empty state must not exist yet…
    expect(find.text('No recent updates'), findsNothing);
    // …and materialise after tapping the destination, once the 200ms
    // fade-through finishes.
    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    expect(find.text('No recent updates'), findsOneWidget);
  });
}
