import 'package:workmanager/workmanager.dart';

import '../backup/backup_scheduler.dart';
import '../library/library_update_scheduler.dart';
import '../sync/sync_scheduler.dart';
import '../track/delayed_tracking_scheduler.dart';

/// Single workmanager callback dispatcher for the whole app.
///
/// Workmanager only supports ONE registered entry point per process
/// ([Workmanager.initialize] stores a single Dart callback handle natively),
/// so every background task — the library sweep and the data sync — has to be
/// routed through this one function and branched on the task name. Each branch
/// builds its own dependencies from scratch because the callback runs in a
/// fresh isolate with no Flutter UI state and no Riverpod overrides.
///
/// Marked `vm:entry-point` so tree-shaking can't drop it.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case libraryUpdateTaskName:
      case libraryUpdateOneOffTaskName:
        return runLibraryUpdateTask();
      case syncTaskName:
      case syncOneOffTaskName:
        return runSyncTask();
      case backupTaskName:
        return runBackupTask();
      case delayedTrackingTaskName:
        return runDelayedTrackingTask();
      default:
        // Unknown task — succeed so workmanager doesn't retry it forever.
        return true;
    }
  });
}

bool _initialised = false;

/// Boots the workmanager engine with the shared [backgroundCallbackDispatcher]
/// exactly once per UI-process lifetime. Idempotent — safe to call from each
/// scheduler's `reschedule`/`runOnce` entry points.
Future<void> ensureWorkmanagerInitialized() async {
  if (_initialised) return;
  await Workmanager().initialize(backgroundCallbackDispatcher);
  _initialised = true;
}
