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

  controller.onListen = () {
    outer = source.listen(
      // Deliberately SYNCHRONOUS: no await between cancelling the old inner
      // and subscribing to the new one. An earlier version awaited the
      // cancel, which leaves a window where a second outer event could see a
      // null `inner` and overwrite the first's subscription without
      // cancelling it. That was NOT reproducible — a StreamController hands
      // events to the listener one turn apart, so the await always settled
      // first — but the window only stays shut by accident of the source's
      // delivery timing, and this version doesn't depend on it.
      // `cancel()` stops delivery the moment it is called, so not awaiting is
      // safe.
      (value) {
        inner?.cancel();
        if (controller.isClosed) return;
        inner = mapper(value).listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            // An inner ending is normally not the end of the result — the
            // next outer event brings another. It IS the end once the outer
            // can no longer produce one.
            if (outerDone) controller.close();
          },
        );
      },
      onError: controller.addError,
      onDone: () {
        outerDone = true;
        // Nothing left to wait for only if no inner is currently running.
        if (inner == null) controller.close();
      },
    );
  };
  controller.onCancel = () async {
    final o = outer;
    final i = inner;
    outer = null;
    inner = null;
    await o?.cancel();
    await i?.cancel();
  };
  return controller.stream;
}

/// [combineLatestList] for two streams of different types. Used to fold the
/// excluded-scanlator set into the cluster's chapter streams, which the merge
/// needs before it dedupes.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  final controller = StreamController<R>();
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  late A latestA;
  late B latestB;
  var seenA = false;
  var seenB = false;

  void emit() {
    if (seenA && seenB) controller.add(combine(latestA, latestB));
  }

  controller.onListen = () {
    subA = a.listen(
      (value) {
        latestA = value;
        seenA = true;
        emit();
      },
      onError: controller.addError,
    );
    subB = b.listen(
      (value) {
        latestB = value;
        seenB = true;
        emit();
      },
      onError: controller.addError,
    );
  };
  controller.onCancel = () async {
    await subA?.cancel();
    await subB?.cancel();
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
