// ===========================================================================
// Tide source settings.
//
// Whatever the extension declares, rendered in the app's own controls: a
// checkbox becomes a Tide switch, a select opens an option sheet, a text
// preference opens an input sheet. Each row shows its CURRENT value in its
// caption, so the screen answers "how is this source configured" without
// opening anything.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/extension_repository.dart';
import '../../domain/source/model/manga_source.dart';
import '../tide/tide.dart';

/// Per-source settings editor — the JS-extension analog of Kotlin's
/// `SourcePreferencesScreen` (ConfigurableSource). Renders the defs the
/// extension declares through its optional `preferences()` contract method:
/// `select` → option sheet, `checkbox` → switch, `text` → input sheet.
/// Only NON-default picks persist (under `source_prefs_<slug>`), and every
/// change re-injects into the live runtime immediately.
class SourcePreferencesScreen extends ConsumerStatefulWidget {
  const SourcePreferencesScreen({
    super.key,
    required this.sourceId,
    required this.sourceName,
  });

  final String sourceId;
  final String sourceName;

  @override
  ConsumerState<SourcePreferencesScreen> createState() =>
      _SourcePreferencesScreenState();
}

class _SourcePreferencesScreenState
    extends ConsumerState<SourcePreferencesScreen> {
  List<SourceFilterDef>? _defs;
  Map<String, String> _values = {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(extensionRepositoryProvider);
    try {
      final source = await repo.getSource(widget.sourceId);
      final defs = await source.getPreferences();
      final values = await repo.getSourcePrefs(widget.sourceId);
      if (!mounted) return;
      setState(() {
        _defs = defs;
        _values = Map.of(values);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _effective(SourceFilterDef def) =>
      _values[def.key] ?? def.defaultValue ?? '';

  /// Label for the currently-selected option of a `select` def, falling back
  /// to the raw stored value when the extension no longer offers it.
  String _selectedLabel(SourceFilterDef def) {
    final value = _effective(def);
    return def.options
            .where((o) => o.value == value)
            .map((o) => o.label)
            .firstOrNull ??
        value;
  }

  Future<void> _set(SourceFilterDef def, String value) async {
    setState(() {
      if (value == (def.defaultValue ?? '')) {
        _values.remove(def.key);
      } else {
        _values[def.key] = value;
      }
    });
    await ref
        .read(extensionRepositoryProvider)
        .setSourcePrefs(widget.sourceId, _values);
  }

  Future<void> _pickSelect(SourceFilterDef def) async {
    final picked = await showTideSheet<String>(
      context,
      (_) => TideOptionSheet(
        title: def.title,
        options: [for (final o in def.options) (o.value, o.label)],
        selected: _effective(def),
      ),
    );
    if (picked != null) await _set(def, picked);
  }

  Future<void> _editText(SourceFilterDef def) async {
    final saved = await showTideSheet<String>(
      context,
      (_) => TideInputSheet(
        title: def.title,
        initialValue: _effective(def),
      ),
    );
    if (saved != null) await _set(def, saved);
  }

  @override
  Widget build(BuildContext context) {
    final defs = _defs;
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          TideRise(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TideHeader(title: widget.sourceName),
            Expanded(child: _body(defs)),
          ],
        ),
      ),
        ],
      ),
    );
  }

  Widget _body(List<SourceFilterDef>? defs) {
    if (_error != null) {
      return _Note('Failed to load settings: $_error');
    }
    if (defs == null) {
      return const Center(
        child: TideSpinner(),
      );
    }
    if (defs.isEmpty) {
      return const _Note('This source has no settings.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        for (final (i, def) in defs.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          switch (def.type) {
            'checkbox' => TideRow(
                icon: Icons.tune,
                title: def.title,
                lit: _effective(def) == 'true',
                // Persist the literal boolean string both ways so an
                // extension testing `=== 'false'` sees it; _set still drops
                // the key when it equals the default.
                onTap: () => _set(
                  def,
                  _effective(def) == 'true' ? 'false' : 'true',
                ),
                trailing: TideSwitch(
                  value: _effective(def) == 'true',
                  onChanged: (v) => _set(def, v ? 'true' : 'false'),
                ),
              ),
            'text' => TideRow(
                icon: Icons.edit_outlined,
                title: def.title,
                subtitle:
                    _effective(def).isEmpty ? 'Not set' : _effective(def),
                trailing: const TideChevron(),
                onTap: () => _editText(def),
              ),
            _ => TideRow(
                icon: Icons.list_alt_outlined,
                title: def.title,
                subtitle: _selectedLabel(def),
                trailing: const TideChevron(),
                onTap: () => _pickSelect(def),
              ),
          },
        ],
      ],
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
