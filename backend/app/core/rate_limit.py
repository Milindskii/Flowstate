import ipaddress
import time
from collections import OrderedDict, deque
from typing import Deque, Iterable, Optional

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

HEALTH_PATHS = ("/health", "/api/v1/health")
WINDOW_SECONDS = 60.0


class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Sliding-window, in-memory, per-client-IP flood limiter (per instance).

    The client IP is the socket peer. ``X-Forwarded-For`` is only believed when the peer is inside
    ``trusted_proxies`` (your load balancer); then the right-most address that is not itself a trusted proxy
    is used, so a client cannot choose its own bucket. Tracked clients are capped (LRU) so memory is bounded.
    """

    def __init__(
        self,
        app,
        max_requests_per_minute: int = 150,
        trusted_proxies: Optional[Iterable[str]] = None,
        max_tracked_clients: int = 10_000,
    ):
        super().__init__(app)
        self.max_requests_per_minute = max_requests_per_minute
        self.max_tracked_clients = max_tracked_clients
        self.trusted_networks = [ipaddress.ip_network(c, strict=False) for c in (trusted_proxies or [])]
        self.request_history: "OrderedDict[str, Deque[float]]" = OrderedDict()

    def _is_trusted(self, ip: str) -> bool:
        try:
            addr = ipaddress.ip_address(ip)
        except ValueError:
            return False
        return any(addr in net for net in self.trusted_networks)

    def _client_ip(self, request: Request) -> str:
        peer = request.client.host if request.client else "unknown"
        if not self.trusted_networks or not self._is_trusted(peer):
            return peer
        forwarded = request.headers.get("x-forwarded-for", "")
        for candidate in reversed([p.strip() for p in forwarded.split(",") if p.strip()]):
            if not self._is_trusted(candidate):
                return candidate
        return peer

    def _record(self, client_ip: str, now: float) -> Deque[float]:
        history = self.request_history.get(client_ip)
        if history is None:
            history = deque()
            self.request_history[client_ip] = history
            while len(self.request_history) > self.max_tracked_clients:
                self.request_history.popitem(last=False)
        else:
            self.request_history.move_to_end(client_ip)
        while history and now - history[0] >= WINDOW_SECONDS:
            history.popleft()
        return history

    async def dispatch(self, request: Request, call_next):
        if request.url.path in HEALTH_PATHS:
            return await call_next(request)

        client_ip = self._client_ip(request)
        now = time.time()
        history = self._record(client_ip, now)

        if len(history) >= self.max_requests_per_minute:
            reset_time = max(1, int(WINDOW_SECONDS - (now - history[0])))
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded. Please retry shortly."},
                headers={
                    "X-RateLimit-Limit": str(self.max_requests_per_minute),
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": str(reset_time),
                    "Retry-After": str(reset_time),
                },
            )

        history.append(now)
        response: Response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(self.max_requests_per_minute)
        response.headers["X-RateLimit-Remaining"] = str(max(0, self.max_requests_per_minute - len(history)))
        response.headers["X-RateLimit-Reset"] = "60"
        return response
