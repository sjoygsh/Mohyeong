/// Thrown when a (non-local) source hands back an empty chapter list.
///
/// 1:1 with Kotlin `tachiyomi.domain.chapter.model.NoChaptersException`, which
/// `SyncChaptersWithSource` raises for the same case. Treating "source returned
/// nothing" as a success indistinguishable from "no new chapters" is how a
/// broken parse hides: a library entry whose source URL had gone stale sat
/// frozen for weeks while every refresh cheerfully reported success.
class NoChaptersException implements Exception {
  const NoChaptersException();

  @override
  String toString() => 'No chapters found';
}
