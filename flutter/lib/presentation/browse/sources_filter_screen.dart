import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/source_preferences.dart';

/// Filter the Sources list by language and by per-source toggle.
/// Languages are expand/collapse sections — flipping a language off
/// hides every source for that language. Inside an enabled language,
/// the per-source checkbox flips the entry in/out of the
/// `hidden_catalogues` set. Mirrors Mihon's `SourcesFilterScreen`.
class SourcesFilterScreen extends ConsumerWidget {
  const SourcesFilterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(sourcePreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Filter sources')),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load preferences: $e'),
          ),
        ),
        data: (prefs) => _Body(prefs: prefs),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.prefs});

  final SourcePreferences prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(extensionRepositoryProvider);
    return StreamBuilder<List<InstalledExtension>>(
      stream: repo.watchInstalled(),
      builder: (context, extSnap) {
        if (!extSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final extensions = extSnap.data!;
        if (extensions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No extensions installed yet. Install one from the '
                'Extensions tab to manage filters here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        // Group by language, sort languages and their entries.
        final groups = <String, List<InstalledExtension>>{};
        for (final e in extensions) {
          final lang = e.lang.toLowerCase();
          groups.putIfAbsent(lang, () => []).add(e);
        }
        final sortedLangs = groups.keys.toList()..sort();
        for (final l in sortedLangs) {
          groups[l]!.sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
        return StreamBuilder<Set<String>>(
          stream: prefs.watchEnabledLanguages(),
          initialData: prefs.getEnabledLanguages(),
          builder: (context, langSnap) {
            final enabledLangs = langSnap.data ?? const <String>{};
            return StreamBuilder<Set<String>>(
              stream: prefs.watchDisabledSources(),
              initialData: prefs.getDisabledSources(),
              builder: (context, disSnap) {
                final disabled = disSnap.data ?? const <String>{};
                final tiles = <Widget>[];
                for (final lang in sortedLangs) {
                  final langEnabled = enabledLangs.contains(lang);
                  tiles.add(
                    SwitchListTile(
                      title: Text(_displayLanguage(lang)),
                      value: langEnabled,
                      onChanged: (_) => prefs.toggleLanguage(lang),
                    ),
                  );
                  if (langEnabled) {
                    for (final ext in groups[lang]!) {
                      final srcEnabled = !disabled.contains(ext.id);
                      tiles.add(
                        CheckboxListTile(
                          title: Text(ext.name),
                          subtitle: Text(
                            '${ext.lang.toUpperCase()} • v${ext.versionCode}',
                          ),
                          value: srcEnabled,
                          onChanged: (_) => prefs.toggleSource(ext.id),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                      );
                    }
                  }
                }
                return ListView(children: tiles);
              },
            );
          },
        );
      },
    );
  }
}

/// Map common Mihon language codes to human-readable names. Falls back
/// to the upper-cased code so unrecognised codes still render usefully.
String _displayLanguage(String code) {
  switch (code) {
    case 'all':
      return 'All';
    case 'en':
      return 'English';
    case 'ja':
      return 'Japanese';
    case 'ko':
      return 'Korean';
    case 'zh':
      return 'Chinese';
    case 'zh-cn':
    case 'zh_cn':
      return 'Chinese (Simplified)';
    case 'zh-tw':
    case 'zh_tw':
      return 'Chinese (Traditional)';
    case 'es':
      return 'Spanish';
    case 'es-419':
      return 'Spanish (Latin America)';
    case 'pt':
      return 'Portuguese';
    case 'pt-br':
    case 'pt_br':
      return 'Portuguese (Brazil)';
    case 'fr':
      return 'French';
    case 'de':
      return 'German';
    case 'it':
      return 'Italian';
    case 'ru':
      return 'Russian';
    case 'pl':
      return 'Polish';
    case 'nl':
      return 'Dutch';
    case 'sv':
      return 'Swedish';
    case 'tr':
      return 'Turkish';
    case 'ar':
      return 'Arabic';
    case 'th':
      return 'Thai';
    case 'vi':
      return 'Vietnamese';
    case 'id':
      return 'Indonesian';
    case 'hi':
      return 'Hindi';
    case 'he':
      return 'Hebrew';
    case 'uk':
      return 'Ukrainian';
    default:
      return code.toUpperCase();
  }
}
