// ===========================================================================
// Tide source filter.
//
// Two levels of the same decision — a language on or off, and inside an
// enabled language, each source on or off — so they are drawn as two levels:
// language rows carry a switch and light when enabled, and their sources hang
// beneath them, indented, until the language goes dark and takes them with it.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/source_preferences.dart';
import '../tide/tide.dart';

/// Filter the Sources list by language and by per-source toggle.
/// Flipping a language off hides every source for that language. Inside an
/// enabled language, the per-source toggle flips the entry in/out of the
/// `hidden_catalogues` set. Mirrors Mihon's `SourcesFilterScreen`.
class SourcesFilterScreen extends ConsumerWidget {
  const SourcesFilterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(sourcePreferencesProvider);
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: TideRise(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TideHeader(title: 'Filter sources'),
            Expanded(
              child: prefsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: TideColors.accent),
                ),
                error: (e, _) => _Note('Failed to load preferences: $e'),
                data: (prefs) => _Body(prefs: prefs),
              ),
            ),
          ],
        ),
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
          return const Center(
            child: CircularProgressIndicator(color: TideColors.accent),
          );
        }
        final extensions = extSnap.data!;
        if (extensions.isEmpty) {
          return const _Note(
            'No extensions installed yet. Install one from the Extensions '
            'view to manage filters here.',
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
          groups[l]!.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                final rows = <Widget>[];
                for (final lang in sortedLangs) {
                  final langEnabled = enabledLangs.contains(lang);
                  final sources = groups[lang]!;
                  if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
                  rows.add(
                    TideRow(
                      icon: Icons.translate,
                      title: _displayLanguage(lang),
                      subtitle: sources.length == 1
                          ? '1 source'
                          : '${sources.length} sources',
                      lit: langEnabled,
                      onTap: () => prefs.toggleLanguage(lang),
                      trailing: TideSwitch(
                        value: langEnabled,
                        onChanged: (_) => prefs.toggleLanguage(lang),
                      ),
                    ),
                  );
                  if (!langEnabled) continue;
                  for (final ext in sources) {
                    final enabled = !disabled.contains(ext.id);
                    rows.add(const SizedBox(height: 7));
                    rows.add(
                      // Indented: these belong to the language above them, and
                      // they disappear with it.
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: TideRow(
                          icon: enabled
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          title: ext.name,
                          subtitle:
                              '${ext.lang.toUpperCase()} · v${ext.versionCode}',
                          lit: enabled,
                          onTap: () => prefs.toggleSource(ext.id),
                        ),
                      ),
                    );
                  }
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: rows,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TideText.body(),
          ),
        ),
      );
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
