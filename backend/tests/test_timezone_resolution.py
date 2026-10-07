"""Unit tests for the single timezone-resolution helper (spec §5, finding 1)."""
from zoneinfo import ZoneInfo

from app.core.timezone import resolve_timezone


def test_valid_request_tz_wins():
    tz, name = resolve_timezone("America/Los_Angeles", "Asia/Kolkata")
    assert name == "America/Los_Angeles" and tz == ZoneInfo("America/Los_Angeles")


def test_missing_request_uses_preference():
    assert resolve_timezone(None, "Asia/Kolkata")[1] == "Asia/Kolkata"
    assert resolve_timezone("", "Asia/Kolkata")[1] == "Asia/Kolkata"


def test_abbreviation_falls_back_to_preference_not_utc():
    for bad in ("IST", "India Standard Time", "PST", "garbage/zone", "../etc/passwd"):
        assert resolve_timezone(bad, "Asia/Kolkata")[1] == "Asia/Kolkata", bad


def test_invalid_everything_is_utc():
    assert resolve_timezone("IST", "nope")[1] == "UTC"
    assert resolve_timezone(None, None)[1] == "UTC"


def test_utc_request_is_honoured_when_explicit():
    assert resolve_timezone("UTC", "Asia/Kolkata")[1] == "UTC"


def test_is_valid_iana():
    from app.core.timezone import is_valid_iana

    assert is_valid_iana("Asia/Kolkata") and is_valid_iana("UTC") and is_valid_iana("America/Los_Angeles")
    assert not any(is_valid_iana(x) for x in ("IST", "India Standard Time", "", None, "../x"))
