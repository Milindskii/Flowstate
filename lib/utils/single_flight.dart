/// Runs an action at most once at a time per key. A second call while the first is still running gets the SAME
/// future back instead of starting another request, so rapid repeated taps become one logical request.
/// The key is released when the action settles (success or failure), so a retry after a failure runs fresh.
class SingleFlight {
  final Map<String, Future<dynamic>> _inFlight = {};

  bool isRunning(String key) => _inFlight.containsKey(key);

  Future<T> run<T>(String key, Future<T> Function() action) {
    final running = _inFlight[key];
    if (running != null) return running as Future<T>;
    final future = action();
    _inFlight[key] = future;
    // Cleanup must not surface the action's error a second time; callers already handle it on `future`. Block bodies
    // on purpose: returning the removed future would make this chain adopt (and re-throw) its error.
    void release() {
      _inFlight.remove(key);
    }

    future.then<void>((_) => release(), onError: (_) => release());
    return future;
  }
}
