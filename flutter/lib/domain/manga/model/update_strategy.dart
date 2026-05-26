/// Mirror of source-api's `UpdateStrategy` enum.
/// Determines whether a manga is included in scheduled library refreshes.
enum UpdateStrategy {
  /// Refreshed by the normal library-update job.
  alwaysUpdate,

  /// Skipped during library updates (e.g. one-shots, completed series).
  onlyFetchOnce;

  /// Stored as an INTEGER in the DB; index matches Kotlin enum ordinal.
  int get dbValue => index;

  static UpdateStrategy fromDb(int? value) {
    if (value == null) return UpdateStrategy.alwaysUpdate;
    if (value < 0 || value >= UpdateStrategy.values.length) {
      return UpdateStrategy.alwaysUpdate;
    }
    return UpdateStrategy.values[value];
  }
}
