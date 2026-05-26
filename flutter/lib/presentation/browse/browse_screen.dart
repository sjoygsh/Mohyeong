import 'package:flutter/material.dart';

/// Browse hosts two sub-tabs in the Kotlin app: Sources and Extensions.
/// Both depend on the extensions architecture (deferred to v1.1+ per the
/// project plan) so today this is a stub.
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Browse'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sources'),
              Tab(text: 'Extensions'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            Center(child: Text('Sources list coming soon.')),
            Center(child: Text('Extensions list coming soon.')),
          ],
        ),
      ),
    );
  }
}
