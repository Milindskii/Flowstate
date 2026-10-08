"""A truncated Gemini answer fails fast (no wasted repair call); an absurd task count is capped with a notice."""
import json
from unittest.mock import patch

import httpx
import pytest

from app.core.config import settings
from app.services.ai_service import AIService, GeminiFailure, MAX_PLAN_TASKS


def _resp(body):
    return httpx.Response(200, json=body, request=httpx.Request("POST", "https://generativelanguage.googleapis.com/x"))


def _task(i):
    return {"ref": f"t{i}", "title": f"Task number {i}", "type": "admin", "estimated_minutes": 20, "difficulty": "light",
            "priority": "low", "confidence": 0.9, "needs_confirmation": False}


@pytest.fixture(autouse=True)
def key(monkeypatch):
    monkeypatch.setattr(settings, "GEMINI_API_KEY", "test-key")


def test_max_tokens_cut_off_fails_fast_without_a_repair_call():
    cut = {"candidates": [{"finishReason": "MAX_TOKENS",
                           "content": {"parts": [{"text": '{"tasks": [{"title": "Half a tas'}]}}]}
    with patch("httpx.Client.post", return_value=_resp(cut)) as post:
        with pytest.raises(GeminiFailure) as err:
            AIService.extract_structured_plan_with_gemini("a very long dump")
    assert err.value.code == "malformed"
    assert post.call_count == 1, "no repair call and no second model for output that is simply too long"


def test_normal_stop_is_unaffected():
    ok = {"candidates": [{"finishReason": "STOP",
                          "content": {"parts": [{"text": json.dumps({"tasks": [_task(1)], "ambiguities": []})}]}}]}
    with patch("httpx.Client.post", return_value=_resp(ok)):
        candidates, *_ = AIService.extract_structured_plan_with_gemini("buy milk")
    assert len(candidates) == 1


def test_task_count_is_capped_and_the_user_is_told():
    many = {"candidates": [{"finishReason": "STOP", "content": {"parts": [{"text": json.dumps(
        {"tasks": [_task(i) for i in range(MAX_PLAN_TASKS + 15)], "ambiguities": []})}]}}]}
    with patch("httpx.Client.post", return_value=_resp(many)):
        candidates, ambiguities, *_ = AIService.extract_structured_plan_with_gemini("a huge day")
    assert len(candidates) == MAX_PLAN_TASKS
    assert any(str(MAX_PLAN_TASKS) in a for a in ambiguities)
