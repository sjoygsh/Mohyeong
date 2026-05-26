import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Singleton AppDatabase. Held alive for the entire app lifetime.
///
/// We deliberately don't dispose this on `ref.onDispose` because closing the
/// Drift connection while widgets still hold streams produces a race; the
/// underlying SQLite connection is closed when the OS terminates the process,
/// which is the only lifetime that actually matters here.
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});
