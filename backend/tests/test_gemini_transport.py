"""
Gemini transport error classification (Build My Day AI path).

`AIService._gemini_generate` is exercised at the real httpx seam (`httpx.Client.post` is stubbed with
real `httpx.Response` objects), so status handling, the fallback chain and the failure codes are the
production code paths. Provider outages must stay distinguishable (quota / auth / model-not-found /
overloaded / timeout / network) and never be hidden by a later fallback model's different error.
"""
from unittest.mock import patch

import httpx
import pytest


from app.services.ai_service import AIService, GeminiFailure

OK_BODY = {"candidates": [{"content": {"parts": [{"text": '{"tasks": []}'}]}}], "usageMetadata": {}}


def _resp(status, body=None):
    return httpx.Response(status, json=body if body is not None else {"error": {"status": "X", "message": "m"}},
                          request=httpx.Request("POST", "https://generativelanguage.googleapis.com/x"))


def _run(side_effect):
    with patch("httpx.Client.post", side_effect=side_effect) as post:
        try:
            return AIService._gemini_generate("p", "k", request_id="r"), post
        except GeminiFailure as e:
            return e, post


def test_not_found_on_primary_falls_through_to_a_working_model():
    out, post = _run([_resp(404), _resp(200, OK_BODY)])
    assert out == '{"tasks": []}'
    assert post.call_count == 2


def test_not_found_on_every_model_is_model_not_found():
    out, post = _run([_resp(404)] * 5)
    assert isinstance(out, GeminiFailure) and out.code == "model_not_found"
    assert "404" in out.reason


def test_provider_quota_stops_immediately_and_is_not_gemini_error():
    out, post = _run([_resp(429), _resp(200, OK_BODY)])
    assert isinstance(out, GeminiFailure) and out.code == "provider_quota"
    assert post.call_count == 1, "a quota response must not burn the other models"


@pytest.mark.parametrize("status", [401, 403])
def test_auth_failure_stops_immediately(status):
    out, post = _run([_resp(status), _resp(200, OK_BODY)])
    assert isinstance(out, GeminiFailure) and out.code == "provider_auth"
    assert post.call_count == 1


def test_overloaded_on_every_model_is_provider_unavailable():
    out, post = _run([_resp(503)] * 5)
    assert isinstance(out, GeminiFailure) and out.code == "provider_unavailable"
    assert "503" in out.reason


def test_timeouts_everywhere_is_timeout():
    out, _ = _run([httpx.ReadTimeout("t")] * 5)
    assert isinstance(out, GeminiFailure) and out.code == "timeout"


def test_connection_errors_everywhere_is_network():
    out, _ = _run([httpx.ConnectError("c")] * 5)
    assert isinstance(out, GeminiFailure) and out.code == "network"


def test_unreadable_200_everywhere_is_malformed():
    out, _ = _run([_resp(200, {"candidates": []})] * 5)
    assert isinstance(out, GeminiFailure) and out.code == "malformed"


def test_earlier_config_error_is_not_masked_by_a_later_overload():
    """404 on the primary (a config bug) then 503 on the fallbacks: report the actionable 404."""
    out, _ = _run([_resp(404), _resp(503), _resp(503), _resp(503)])
    assert isinstance(out, GeminiFailure) and out.code == "model_not_found"


def test_overload_then_success_on_a_fallback_succeeds():
    out, post = _run([_resp(503), _resp(200, OK_BODY)])
    assert out == '{"tasks": []}'


def test_invalid_api_key_arrives_as_http_400_and_is_still_an_auth_failure():
    """Google answers a bad key with 400 INVALID_ARGUMENT + ErrorInfo reason API_KEY_INVALID (captured live)."""
    body = {"error": {"code": 400, "status": "INVALID_ARGUMENT", "message": "API key not valid. Please pass a valid API key.",
                      "details": [{"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "API_KEY_INVALID"}]}}
    out, post = _run([_resp(400, body), _resp(200, OK_BODY)])
    assert isinstance(out, GeminiFailure) and out.code == "provider_auth"
    assert post.call_count == 1


def test_other_400_stays_a_generic_rejection():
    body = {"error": {"code": 400, "status": "INVALID_ARGUMENT", "message": "Unsupported field", "details": []}}
    out, _ = _run([_resp(400, body)])
    assert isinstance(out, GeminiFailure) and out.code == "gemini_error"
