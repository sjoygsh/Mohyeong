import 'package:flutter/material.dart';

/// Placeholder for the Updates tab. The Kotlin equivalent backs this with
/// the `updatesView` SQL view -- the data side is in place via the .drift
/// schema, but rendering rows requires the source-fetch + cover pipeline
/// which doesn't exist yet.
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: const _ComingSoon(message: 'Updates feed will appear here.'),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
