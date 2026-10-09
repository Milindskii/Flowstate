"""Build My Day input limit: one server-authoritative word limit, enforced before any charge or provider call."""
import uuid
from unittest.mock import patch

import pytest

pytestmark = pytest.mark.usefixtures("one_free_plan")  # these exercise the free-allowance mechanism
from httpx import AsyncClient, ASGITransport

from app.core import economy_config
from app.core.security import create_access_token
from app.main import app
from app.models.flow_progression import FlowProfile
from app.db.session import SessionLocal
from app.services.ai_service import AIService
from tests.test_ai_economy import ensure_user, make_auth_header, mock_gemini_tasks, unique_user


def words(n: int) -> str:
    return " ".join(["word"] * n)


def test_limit_constants_are_derived_from_one_value():
    assert economy_config.BMD_MAX_INPUT_WORDS == 200
    assert economy_config.BMD_MAX_INPUT_CHARS == economy_config.BMD_MAX_INPUT_WORDS * 8


def test_input_limit_is_the_same_for_every_user_for_now():
    assert economy_config.input_limit_for(is_pro=False) == economy_config.input_limit_for(is_pro=True)


@pytest.mark.asyncio
async def test_status_exposes_the_limit():
    headers = make_auth_header(unique_user("lim_status"))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/ai/status", headers=headers)
    assert res.status_code == 200
    assert res.json()["max_input_words"] == economy_config.BMD_MAX_INPUT_WORDS


@pytest.mark.asyncio
async def test_text_at_the_limit_is_planned():
    headers = make_auth_header(unique_user("lim_at"))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            res = await ac.post("/api/v1/ai/plan", headers=headers,
                                json={"raw_text": words(economy_config.BMD_MAX_INPUT_WORDS)})
    assert res.status_code == 200


@pytest.mark.asyncio
async def test_one_word_over_is_refused_without_charge_or_provider_call():
    user_id = unique_user("lim_over")
    ensure_user(user_id)
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini") as gemini:
            res = await ac.post("/api/v1/ai/plan", headers=headers,
                                json={"raw_text": words(economy_config.BMD_MAX_INPUT_WORDS + 1)})
            gemini.assert_not_called()
        status = await ac.get("/api/v1/ai/status", headers=headers)
    assert res.status_code == 422
    body = res.json()
    assert body["failure_code"] == "input_too_long"
    assert body["limit_words"] == economy_config.BMD_MAX_INPUT_WORDS
    assert body["words"] == economy_config.BMD_MAX_INPUT_WORDS + 1
    assert status.json()["free_uses_remaining"] == 1  # nothing consumed


@pytest.mark.asyncio
async def test_no_space_text_hits_the_character_backstop():
    headers = make_auth_header(unique_user("lim_chars"))
    text = "字" * (economy_config.BMD_MAX_INPUT_CHARS + 1)  # one "word" by whitespace, far too many characters
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini") as gemini:
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": text})
            gemini.assert_not_called()
    assert res.status_code == 422
    assert res.json()["failure_code"] == "input_too_long"


@pytest.mark.asyncio
async def test_absurd_body_is_stopped_by_the_schema_ceiling():
    headers = make_auth_header(unique_user("lim_ceiling"))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "a " * 20000})
    assert res.status_code == 422


@pytest.mark.asyncio
async def test_client_failure_report_accepts_the_codes_the_app_sends():
    headers = make_auth_header(unique_user("lim_report"))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        for code in ("privacy_declined", "gemini_error", "input_too_long", "client_error"):
            res = await ac.post("/api/v1/ai/planning-attempts", headers=headers,
                                json={"request_id": uuid.uuid4().hex, "failure_code": code})
            assert res.status_code in (200, 201, 204), (code, res.status_code, res.text)
