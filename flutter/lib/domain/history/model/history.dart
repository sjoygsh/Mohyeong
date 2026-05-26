/// Mirror of `tachiyomi.domain.history.model.History`.
class History {
  const History({
    required this.id,
    required this.chapterId,
    required this.readAt,
    required this.readDuration,
  });

  final int id;
  final int chapterId;
  final DateTime? readAt;
  final int readDuration;

  History copyWith({
    int? id,
    int? chapterId,
    Object? readAt = _sentinel,
    int? readDuration,
  }) {
    return History(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      readAt:
          identical(readAt, _sentinel) ? this.readAt : readAt as DateTime?,
      readDuration: readDuration ?? this.readDuration,
    );
  }

  factory History.empty() => const History(
        id: -1,
        chapterId: -1,
        readAt: null,
        readDuration: -1,
      );
}

const Object _sentinel = Object();
