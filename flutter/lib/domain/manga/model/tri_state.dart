/// Mirror of core/common's `TriState` enum.
/// Used for filter controls that have an off / include / exclude state.
enum TriState {
  /// Filter is off — predicate always true.
  disabled,

  /// Filter is on, include rows where the predicate is true.
  enabledIs,

  /// Filter is on, include rows where the predicate is false.
  enabledNot,
}

/// Mirrors Kotlin's `applyFilter(filter, predicate)`.
bool applyTriState(TriState filter, bool Function() predicate) {
  switch (filter) {
    case TriState.disabled:
      return true;
    case TriState.enabledIs:
      return predicate();
    case TriState.enabledNot:
      return !predicate();
  }
}
