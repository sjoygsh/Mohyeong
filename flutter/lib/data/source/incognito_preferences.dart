/// Incognito mode, ported 1:1 from Mihon. Two independent switches combine
/// into the effective per-source incognito state:
///
///  * [incognitoModeProvider] — the global toggle (Mihon `BasePreferences.
///    incognitoMode`, app-state key `__APP_STATE_incognito_mode`). Reset to
///    false on every cold start (see `main()`), matching Mihon resetting it
///    in `MainActivity`.
///  * [incognitoExtensionsProvider] — a set of extension slugs put into
///    incognito individually (Mihon `SourcePreferences.incognitoExtensions`,
///    key `incognito_extensions`; Mihon stores APK package names, the JS
///    rewrite has no packages so the extension *slug* is the stable identity).
///
/// While incognito for a source, the reader leaves no trace: no reading
/// history, no last-page-read / read-flag progress, and no tracker pushes —
/// mirroring `ReaderViewModel`'s `incognitoMode` guards.
library;

import '../preferences/typed_preferences.dart';
import 'extension_repository.dart';

/// Mihon's `Preference.appStateKey("incognito_mode")` expands to this exact
/// string; matched verbatim so a settings import carries the value across.
const incognitoModeKey = '__APP_STATE_incognito_mode';

/// Mihon `SourcePreferences.incognitoExtensions` key.
const incognitoExtensionsKey = 'incognito_extensions';

/// Global incognito toggle. Default false; reset to false on every launch.
final incognitoModeProvider = boolPref(incognitoModeKey, false);

/// Per-extension incognito slugs.
final incognitoExtensionsProvider =
    stringSetPref(incognitoExtensionsKey, const {});

/// Effective incognito state for [sourceId]. 1:1 with Mihon's
/// `GetIncognitoState.await`: global mode wins, otherwise the source's
/// extension must be in the per-extension set. A null source id is never
/// per-extension incognito (only the global toggle applies).
///
/// Takes the already-read pref values + the repo (rather than a `Ref`) so it
/// can be called from the reader's top-level data loader without coupling to
/// a particular ref type.
Future<bool> resolveIncognitoState({
  required bool globalIncognito,
  required Set<String> incognitoExtensions,
  required ExtensionRepository extensionRepository,
  required int? sourceId,
}) async {
  if (globalIncognito) return true;
  if (sourceId == null) return false;
  if (incognitoExtensions.isEmpty) return false;
  final slug = await extensionRepository.getExtensionPackage(sourceId);
  return slug != null && incognitoExtensions.contains(slug);
}
