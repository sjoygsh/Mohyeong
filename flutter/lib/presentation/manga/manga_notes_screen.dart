import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';

import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';

/// Full-screen markdown notes editor. Mirrors Mihon's `MangaNotesScreen`
/// minus the live markdown preview — v1.0 ships a plain TextField. The
/// underlying `mangas.notes` TEXT column already round-trips through the
/// mapper, so saving here makes the value backup/sync-eligible for free.
///
/// Saves are debounced (400ms after the last keystroke) so we don't slam
/// the DB on every character, and a final flush runs in `dispose`.
class MangaNotesScreen extends ConsumerStatefulWidget {
  const MangaNotesScreen({super.key, required this.manga});

  final Manga manga;

  @override
  ConsumerState<MangaNotesScreen> createState() => _MangaNotesScreenState();
}

class _MangaNotesScreenState extends ConsumerState<MangaNotesScreen> {
  /// Matches Kotlin `MangaNotesTextArea.MAX_LENGTH` (250) and its 90% warn
  /// threshold, after which the remaining-character counter turns red.
  static const int _maxLength = 250;
  static const int _warnLength = 225; // 90% of _maxLength

  late final TextEditingController _controller =
      TextEditingController(text: widget.manga.notes);
  Timer? _debounce;
  String _lastSaved = '';

  @override
  void initState() {
    super.initState();
    _lastSaved = widget.manga.notes;
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _flush);
  }

  Future<void> _flush() async {
    final next = _controller.text;
    if (next == _lastSaved) return;
    _lastSaved = next;
    await ref.read(mangaRepositoryProvider).setNotes(widget.manga.id, next);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Best-effort final flush. If the user types something then yanks
    // the screen away before the debounce fires we still want to land
    // the change.
    if (_controller.text != _lastSaved) {
      unawaited(
        ref
            .read(mangaRepositoryProvider)
            .setNotes(widget.manga.id, _controller.text),
      );
    }
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TideHeader(title: 'Notes', subtitle: widget.manga.title),
            Expanded(
              child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TideGlass(
                  radius: TideRadius.panel,
                  tintTop: 0.075,
                  tintBottom: 0.026,
                  highlight: 0.14,
                  border: 0.09,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  maxLength: _maxLength,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  // Custom counter is rendered below the field instead.
                  buildCounter: (_, {
                    required int currentLength,
                    required bool isFocused,
                    int? maxLength,
                  }) =>
                      null,
                  cursorColor: TideColors.accent,
                  style: TideText.body().copyWith(color: TideColors.text),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enjoyed the part where…',
                    hintStyle: TideText.body(),
                    alignLabelWithHint: true,
                  ),
                ),
                ),
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final remaining = _maxLength - value.text.characters.length;
                  return Text(
                    '$remaining',
                    style: TideText.caption(size: 12, opacity: 0.5).copyWith(
                      color: value.text.characters.length > _warnLength
                          ? TideColors.danger
                          : null,
                    ),
                  );
                },
              ),
            ],
          ),
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }
}
