import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/typed_preferences.dart';
import 'extension_repository.dart';

/// Extension-update availability — the JS-model port of Kotlin's
/// `ExtensionUpdateJob` + `SourcePreferences.extensionUpdatesCount`.
///
/// The count drives the Browse bottom-nav badge (Kotlin key
/// `ext_updates_count`, matched verbatim); the id set drives the
/// per-row "Update available" affordances on the Extensions tab. The
/// check runs once per app session when the Extensions tab is first
/// shown (the JS model has no background job for this yet), and both
/// values are corrected whenever an extension is updated or removed.
final extUpdatesCountProvider = intPref('ext_updates_count', 0);

/// Ids of installed extensions whose origin URL serves a newer
/// `version_code`. Session state — repopulated by [runExtensionUpdateCheck].
final extensionUpdatesProvider = StateProvider<Set<String>>((_) => const {});

/// Session guard so the automatic check fires once per app run.
final _checkedThisSessionProvider = StateProvider<bool>((_) => false);

/// Probes every URL-installed extension's origin and records the result
/// in [extensionUpdatesProvider] + [extUpdatesCountProvider]. When [force]
/// is false, no-ops after the first run of the session.
Future<void> runExtensionUpdateCheck(WidgetRef ref,
    {bool force = false}) async {
  if (!force && ref.read(_checkedThisSessionProvider)) return;
  ref.read(_checkedThisSessionProvider.notifier).state = true;
  // Capture everything BEFORE the (long, network-bound) await: the caller
  // is a tab widget that may be disposed mid-check, and a WidgetRef must
  // not be touched after its element unmounts. The provider/notifier
  // objects themselves are root-scoped and stay valid.
  final repo = ref.read(extensionRepositoryProvider);
  final updatesNotifier = ref.read(extensionUpdatesProvider.notifier);
  final countNotifier = ref.read(extUpdatesCountProvider.notifier);
  final updatable = await repo.checkForUpdates();
  updatesNotifier.state = updatable;
  await countNotifier.set(updatable.length);
}

/// Drop [extensionId] from the updatable set (after a successful update or
/// an uninstall) and keep the badge count in step.
void clearExtensionUpdate(WidgetRef ref, String extensionId) {
  final current = ref.read(extensionUpdatesProvider);
  if (!current.contains(extensionId)) return;
  final next = {...current}..remove(extensionId);
  ref.read(extensionUpdatesProvider.notifier).state = next;
  ref.read(extUpdatesCountProvider.notifier).set(next.length);
}
