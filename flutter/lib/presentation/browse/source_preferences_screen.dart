import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/extension_repository.dart';
import '../../domain/source/model/manga_source.dart';

/// Per-source settings editor — the JS-extension analog of Kotlin's
/// `SourcePreferencesScreen` (ConfigurableSource). Renders the defs the
/// extension declares through its optional `preferences()` contract method:
/// `select` → radio dialog, `checkbox` → switch, `text` → text-field dialog.
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
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(def.title),
        children: [
          RadioGroup<String>(
            groupValue: _effective(def),
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final opt in def.options)
                  RadioListTile<String>(
                    title: Text(opt.label),
                    value: opt.value,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await _set(def, picked);
  }

  Future<void> _editText(SourceFilterDef def) async {
    final controller = TextEditingController(text: _effective(def));
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(def.title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null) await _set(def, saved);
  }

  @override
  Widget build(BuildContext context) {
    final defs = _defs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.sourceName)),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load settings: $_error'),
              ),
            )
          : defs == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    for (final def in defs)
                      switch (def.type) {
                        'checkbox' => SwitchListTile(
                            title: Text(def.title),
                            value: _effective(def) == 'true',
                            onChanged: (v) => _set(def, v ? 'true' : ''),
                          ),
                        'text' => ListTile(
                            title: Text(def.title),
                            subtitle: _effective(def).isEmpty
                                ? null
                                : Text(_effective(def)),
                            onTap: () => _editText(def),
                          ),
                        _ => ListTile(
                            title: Text(def.title),
                            subtitle: Text(
                              def.options
                                  .where(
                                      (o) => o.value == _effective(def))
                                  .map((o) => o.label)
                                  .firstOrNull ??
                                  _effective(def),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _pickSelect(def),
                          ),
                      },
                  ],
                ),
    );
  }
}
