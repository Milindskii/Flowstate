"""Per-instance protection for the AI provider: request deadline, circuit breaker, bounded concurrency.

These are deliberately in-process: each API instance protects itself and the shared provider quota is split by
``AI_MAX_CONCURRENCY`` per instance. Cross-instance state (usage, rate limits, one-in-flight-per-user) lives in
Postgres, see ``services/ai_gateway.py``.
"""
import threading
import time
from contextlib import contextmanager
from contextvars import ContextVar
from typing import List, Optional

from .config import settings

# Monotonic instant by which all provider work for the current request must be finished (None = unbounded).
request_deadline: ContextVar[Optional[float]] = ContextVar("ai_request_deadline", default=None)


class AIBusy(Exception):
    """The provider path is saturated or unhealthy. Carries the HTTP-friendly reason and a Retry-After hint."""

    def __init__(self, reason: str, retry_after: int = 10):
        super().__init__(reason)
        self.reason = reason  # "capacity" | "circuit_open"
        self.retry_after = max(1, int(retry_after))


class CircuitBreaker:
    """closed -> (N consecutive provider-health failures within the window) -> open -> (after the open period)
    -> half-open (exactly one probe) -> closed on success / open again on failure."""

    def __init__(self):
        self._lock = threading.Lock()
        self.reset()

    def reset(self) -> None:
        with self._lock:
            self.state = "closed"
            self._failures: List[float] = []
            self._opened_at = 0.0
            self._probe_in_flight = False

    def allow(self, now: Optional[float] = None) -> bool:
        now = time.monotonic() if now is None else now
        with self._lock:
            if self.state == "closed":
                return True
            if self.state == "open":
                if now - self._opened_at < settings.AI_BREAKER_OPEN_SECONDS:
                    return False
                self.state = "half_open"
                self._probe_in_flight = False
            if self._probe_in_flight:
                return False
            self._probe_in_flight = True
            return True

    def retry_after(self, now: Optional[float] = None) -> int:
        now = time.monotonic() if now is None else now
        with self._lock:
            return max(1, int(settings.AI_BREAKER_OPEN_SECONDS - (now - self._opened_at)) + 1)

    def record_success(self) -> None:
        with self._lock:
            self.state = "closed"
            self._failures.clear()
            self._probe_in_flight = False

    def record_neutral(self) -> None:
        """The call neither proved nor disproved provider health (e.g. a bug on our side): free the probe."""
        with self._lock:
            self._probe_in_flight = False

    def record_failure(self, now: Optional[float] = None) -> None:
        now = time.monotonic() if now is None else now
        with self._lock:
            if self.state == "half_open":
                self._open(now)
                return
            window = settings.AI_BREAKER_WINDOW_SECONDS
            self._failures = [t for t in self._failures if now - t <= window]
            self._failures.append(now)
            if len(self._failures) >= settings.AI_BREAKER_FAILURE_THRESHOLD:
                self._open(now)

    def _open(self, now: float) -> None:
        self.state = "open"
        self._opened_at = now
        self._failures.clear()
        self._probe_in_flight = False


breaker = CircuitBreaker()

_semaphore_guard = threading.Lock()
_semaphore: Optional[threading.BoundedSemaphore] = None
_semaphore_size: Optional[int] = None


def _current_semaphore() -> threading.BoundedSemaphore:
    global _semaphore, _semaphore_size
    with _semaphore_guard:
        if _semaphore is None or _semaphore_size != settings.AI_MAX_CONCURRENCY:
            _semaphore = threading.BoundedSemaphore(max(1, settings.AI_MAX_CONCURRENCY))
            _semaphore_size = settings.AI_MAX_CONCURRENCY
        return _semaphore


def reset_ai_limits() -> None:
    """Test hook: fresh breaker and semaphore."""
    global _semaphore, _semaphore_size
    breaker.reset()
    with _semaphore_guard:
        _semaphore, _semaphore_size = None, None


@contextmanager
def ai_slot():
    """Bounded concurrency for provider calls. Raises AIBusy instead of queueing without limit."""
    sem = _current_semaphore()  # released on the same object even if the limit is reconfigured meanwhile
    if not sem.acquire(timeout=max(0.0, settings.AI_QUEUE_WAIT_SECONDS)):
        raise AIBusy("capacity", retry_after=10)
    try:
        yield
    finally:
        sem.release()


@contextmanager
def provider_admission():
    """Circuit breaker check, then a concurrency slot. Raises AIBusy when either refuses."""
    if not breaker.allow():
        raise AIBusy("circuit_open", retry_after=breaker.retry_after())
    try:
        slot = ai_slot()
        slot.__enter__()
    except AIBusy:
        breaker.record_neutral()  # we never reached the provider; don't strand a half-open probe
        raise
    try:
        yield
    finally:
        slot.__exit__(None, None, None)
