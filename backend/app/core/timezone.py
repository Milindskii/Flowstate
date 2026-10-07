"""The ONE timezone rule (spec section 5). Every path that needs the user's zone goes through here.

    zone = a valid IANA name supplied with the request (body field or query parameter)
         else the user's stored preference (``user_preferences.timezone``) when valid
         else UTC (logged)

* Abbreviations such as "IST" are not IANA names. They are ignored, so a present-but-invalid request
  value falls back to the stored preference rather than silently to UTC.
* Today, Calendar, Replan, Build My Day, /tasks/today and /tasks/parse all resolve through
  ``resolve_timezone`` / ``resolve_user_timezone``. Nothing else may call ``ZoneInfo(...)`` on a
  user-supplied or stored name (tests/test_timezone_unification.py enforces this).
* Flutter sends the device's IANA zone on every one of these requests (services/timezone_service.dart).
"""
from datetime import date, datetime, timezone
from typing import Optional, Tuple
from zoneinfo import ZoneInfo

from .logging import logger


def _valid_zone(name: Optional[str]) -> Optional[ZoneInfo]:
    if not name or not isinstance(name, str):
        return None
    name = name.strip()
    if not name:
        return None
    try:
        return ZoneInfo(name)
    except Exception:  # ZoneInfoNotFoundError, ValueError (bad key), OSError
        return None


def is_valid_iana(name: Optional[str]) -> bool:
    """True when ``name`` is an IANA zone key ZoneInfo can load (abbreviations like 'IST' are not)."""
    return _valid_zone(name) is not None


def resolve_user_timezone(user, request_tz: Optional[str] = None) -> Tuple[ZoneInfo, str]:
    """``resolve_timezone`` for an authenticated user: request value, then their stored preference."""
    prefs = getattr(user, "preferences", None)
    return resolve_timezone(request_tz, prefs.timezone if prefs else None)


def resolve_timezone(request_tz: Optional[str], prefs_tz: Optional[str]) -> Tuple[ZoneInfo, str]:
    """Return ``(ZoneInfo, iana_name)``.

    Order: valid IANA name from the request -> valid stored preference -> UTC (logged).
    A present-but-invalid request value (e.g. an abbreviation such as "IST" from an old
    client) falls back to the stored preference, never silently to UTC.
    """
    zone = _valid_zone(request_tz)
    if zone is not None:
        return zone, zone.key
    if request_tz:
        logger.warning("timezone: ignoring non-IANA request value %r", request_tz)
    zone = _valid_zone(prefs_tz)
    if zone is not None:
        return zone, zone.key
    logger.warning("timezone: no valid request/preference zone; defaulting to UTC")
    utc = ZoneInfo("UTC")
    return utc, "UTC"


def local_date(instant: datetime, tz: ZoneInfo) -> date:
    """Local calendar date of an instant. Naive values are UTC (the UTCDateTime storage convention)."""
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=timezone.utc)
    return instant.astimezone(tz).date()


def owning_date(planned_date: Optional[date], scheduled_start: Optional[datetime], tz: ZoneInfo) -> Optional[date]:
    """THE date-ownership rule for writes: the day a task belongs to.

    A stored slot fixes the day (its local date); otherwise the explicit planned date.
    ``created_at`` / ``completed_at`` never decide ownership.
    """
    if scheduled_start is not None:
        return local_date(scheduled_start, tz)
    return planned_date
