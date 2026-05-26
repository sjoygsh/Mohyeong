import '../database/app_database.dart' as db;
import '../../domain/source/model/source.dart';

/// Drift `sources` rows store only the bare (id, lang, name) tuple. Capability
/// fields like `supportsLatest` come from the in-process source registry, not
/// the database, so the mapper fills them with `false`-ish defaults.
class SourceMapper {
  const SourceMapper._();

  static Source fromRow(db.Source row) => Source(
        id: row.id,
        lang: row.lang,
        name: row.name,
        supportsLatest: false,
        // Anything that lives in the DB but isn't installed at runtime is a
        // stub by definition (matches the Kotlin StubSource behaviour).
        isStub: true,
      );
}
