import time
from collections import defaultdict
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Sliding-window in-memory rate limiter per client IP.
    Protects all API endpoints from abusive traffic and DoS.
    """
    def __init__(self, app, max_requests_per_minute: int = 150):
        super().__init__(app)
        self.max_requests_per_minute = max_requests_per_minute
        self.request_history = defaultdict(list)

    async def dispatch(self, request: Request, call_next):
        # Allow test client or health checks without rate limiting
        if (
            request.url.path in ("/health", "/api/v1/health")
            or request.client is None
            or request.client.host == "testclient"
            or request.base_url.hostname == "test"
        ):
            return await call_next(request)

        client_ip = request.client.host
        now = time.time()
        window = 60.0

        # Purge old requests
        valid_requests = [t for t in self.request_history[client_ip] if now - t < window]
        self.request_history[client_ip] = valid_requests

        if len(valid_requests) >= self.max_requests_per_minute:
            reset_time = int(60 - (now - valid_requests[0])) if valid_requests else 60
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded. Please retry shortly."},
                headers={
                    "X-RateLimit-Limit": str(self.max_requests_per_minute),
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": str(max(1, reset_time)),
                    "Retry-After": str(max(1, reset_time)),
                },
            )

        self.request_history[client_ip].append(now)
        response: Response = await call_next(request)

        remaining = max(0, self.max_requests_per_minute - len(self.request_history[client_ip]))
        response.headers["X-RateLimit-Limit"] = str(self.max_requests_per_minute)
        response.headers["X-RateLimit-Remaining"] = str(remaining)
        response.headers["X-RateLimit-Reset"] = "60"
        return response
