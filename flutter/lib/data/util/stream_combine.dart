import 'dart:async';

/// The two reactive combinators the linked-cluster chapter stream needs.
/// Hand-rolled because this project has no rxdart, and pulling one in for two
/// operators isn't worth the dependency.

/// Re-subscribes to a new inner stream every time [source] emits, cancelling
/// the previous one. Equivalent to rxdart's `switchMap` — NOT
/// [Stream.asyncExpand], which waits for each inner stream to complete and so
/// deadlocks on the endless database watch streams used here.
Stream<R> switchMap<T, R>(
  Stream<T> source,
  Stream<R> Function(T value) mapper,
) {
  final controller = StreamController<R>();
  StreamSubscription<T>? outer;
  StreamSubscription<R>? inner;
  var outerDone = false;

  Future<void> cancelInner() async {
    final sub = inner;
    inner = null;
    await sub?.cancel();
  }

  controller.onListen = () {
    outer = source.listen(
      (value) async {
        await cancelInner();
        if (controller.isClosed) return;
        inner = mapper(value).listen(
          controller.add,
          onError: controller.addError,
          // An inner stream ending doesn't end the result: the next outer
          // emission will bring another one.
        );
      },
      onError: controller.addError,
      onDone: () {
        outerDone = true;
        // Only finish once the inner stream can no longer produce anything.
        if (inner == null) controller.close();
      },
    );
  };
  controller.onCancel = () async {
    await outer?.cancel();
    await cancelInner();
    if (!outerDone) outerDone = true;
  };
  return controller.stream;
}

/// Emits a list of the latest value of every stream in [streams], once all of
/// them have produced at least one value. An empty [streams] emits `[]` once.
Stream<List<T>> combineLatestList<T>(List<Stream<T>> streams) {
  if (streams.isEmpty) return Stream<List<T>>.value(const []);

  final controller = StreamController<List<T>>();
  final latest = List<T?>.filled(streams.length, null);
  final seen = List<bool>.filled(streams.length, false);
  final subs = <StreamSubscription<T>>[];
  var ready = false;

  controller.onListen = () {
    for (var i = 0; i < streams.length; i++) {
      final index = i;
      subs.add(streams[index].listen(
        (value) {
          latest[index] = value;
          seen[index] = true;
          ready = ready || seen.every((s) => s);
          if (ready) controller.add(List<T>.from(latest.cast<T>()));
        },
        onError: controller.addError,
      ));
    }
  };
  controller.onCancel = () async {
    for (final s in subs) {
      await s.cancel();
    }
    subs.clear();
  };
  return controller.stream;
}
