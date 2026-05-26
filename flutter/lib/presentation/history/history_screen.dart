import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history/history_repository.dart';

/// History tab. Shows total read duration as a tiny smoke-test of the data
/// layer; per-chapter list rendering needs the chapter-to-manga join that
/// will land alongside the manga-details screen.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(historyRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<int>(
        future: repo.totalReadDurationMs(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ms = snapshot.data!;
          final minutes = (ms / 60000).round();
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    'Total time read: $minutes min',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Detailed history list coming soon.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
