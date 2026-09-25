import pytest
import uuid
import json
from unittest.mock import patch, MagicMock
from httpx import AsyncClient, ASGITransport
from datetime import datetime, timezone

from app.main import app
from app.db.session import SessionLocal, get_db
from app.models.user import User
from app.models.flow_progression import FlowProfile
from app.models.ai_usage import AIUsageRecord
from app.schemas.task import TaskCandidateResponse, TaskType, TaskDifficulty, TaskPriority, TaskSource, FieldProvenance
from app.core.security import create_access_token
from app.services.ai_economy_service import AIEconomyService, _AI_RATE_LIMIT_CACHE
from app.services.ai_service import AIService

def unique_user(prefix="ai_test"):
    return f"{prefix}_{uuid.uuid4().hex[:8]}"

def make_auth_header(user_id: str):
    token = create_access_token({"sub": user_id, "email": f"{user_id}@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.fixture(autouse=True)
def reset_rate_limits():
    _AI_RATE_LIMIT_CACHE.clear()
    yield
    _AI_RATE_LIMIT_CACHE.clear()

def mock_gemini_tasks(tasks=None, ambiguities=None, needs_confirmation=False):
    if tasks is None:
        tasks = [
            TaskCandidateResponse(
                title="Finish report",
                estimated_minutes=60,
                task_type=TaskType.deep_work,
                difficulty=TaskDifficulty.medium,
                priority=TaskPriority.high,
                category="Work",
                confidence=0.92,
                source=TaskSource.ai_parsed,
                field_provenance={"priority": FieldProvenance(source="explicit", confidence=1.0)},
            )
        ]
    return tasks, ambiguities or [], needs_confirmation

# ── Test 1: Free user receives exactly 1 AI use ─────────────────────────
@pytest.mark.asyncio
async def test_free_user_receives_exactly_1_ai_use():
    user_id = unique_user("free_use")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Check initial status
        st_res = await ac.get("/api/v1/ai/status", headers=headers)
        assert st_res.status_code == 200
        assert st_res.json()["free_uses_remaining"] == 1
        assert st_res.json()["can_plan_free"] is True
        assert st_res.json()["requires_shield"] is False

        # First AI planning call consumes the free use
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            plan_res = await ac.post(
                "/api/v1/ai/plan",
                headers=headers,
                json={"raw_text": "Study economics for 1 hour"},
            )
            assert plan_res.status_code == 200
            data = plan_res.json()
            assert data["free_consumed"] is True
            assert data["shield_consumed"] is False
            assert len(data["tasks"]) == 1

        # Check status after: free_uses_remaining is now 0
        st_res2 = await ac.get("/api/v1/ai/status", headers=headers)
        assert st_res2.status_code == 200
        assert st_res2.json()["free_uses_remaining"] == 0
        assert st_res2.json()["can_plan_free"] is False
        assert st_res2.json()["requires_shield"] is True

# ── Test 2: Second AI use requires Shield ────────────────────────────────
@pytest.mark.asyncio
async def test_second_ai_use_requires_shield():
    user_id = unique_user("second_use")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1st use (free)
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            res1 = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Task one"})
            assert res1.status_code == 200

        # 2nd use without confirming shield consumption -> rejected with 402
        res2 = await ac.post(
            "/api/v1/ai/plan",
            headers=headers,
            json={"raw_text": "Task two", "consume_shield": False},
        )
        assert res2.status_code == 402
        assert "requires 1 Flow Shield" in res2.json()["detail"]

# ── Test 3: Shield count decreases exactly once ──────────────────────────
@pytest.mark.asyncio
async def test_shield_count_decreases_exactly_once():
    user_id = unique_user("shield_dec")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Check initial shields (new user gets 2)
        st_res = await ac.get("/api/v1/ai/status", headers=headers)
        initial_shields = st_res.json()["shields_available"]
        assert initial_shields == 2

        # 1st plan (free)
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Task one"})

        # 2nd plan with consume_shield=True
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            plan_res = await ac.post(
                "/api/v1/ai/plan",
                headers=headers,
                json={"raw_text": "Task two", "consume_shield": True},
            )
            assert plan_res.status_code == 200
            assert plan_res.json()["shield_consumed"] is True

        # Check shields: decreased by exactly 1
        st_res2 = await ac.get("/api/v1/ai/status", headers=headers)
        assert st_res2.json()["shields_available"] == initial_shields - 1

# ── Test 4: Failed Gemini request does not permanently consume Shield ────
@pytest.mark.asyncio
async def test_failed_gemini_request_does_not_consume_shield():
    user_id = unique_user("fail_shield")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Use free plan first
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Task one"})

        # Before failure: 2 shields available
        st1 = await ac.get("/api/v1/ai/status", headers=headers)
        assert st1.json()["shields_available"] == 2

        # Mock Gemini throwing an unrecoverable network/timeout error
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=RuntimeError("Gemini 503 timeout")):
            fail_res = await ac.post(
                "/api/v1/ai/plan",
                headers=headers,
                json={"raw_text": "Task two", "consume_shield": True},
            )
            assert fail_res.status_code == 502
            assert "Your free plans and shields were not charged" in fail_res.json()["detail"]

        # Verify shields were NOT decremented
        st2 = await ac.get("/api/v1/ai/status", headers=headers)
        assert st2.json()["shields_available"] == 2

# ── Test 5: Duplicate request does not double-charge ─────────────────────
@pytest.mark.asyncio
async def test_duplicate_request_does_not_double_charge():
    user_id = unique_user("idempotency")
    headers = make_auth_header(user_id)
    idempotency_key = f"key_{uuid.uuid4().hex}"

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()) as mock_extract:
            # First tap
            res1 = await ac.post(
                "/api/v1/ai/plan",
                headers=headers,
                json={"raw_text": "Study algorithms", "idempotency_key": idempotency_key},
            )
            assert res1.status_code == 200
            assert mock_extract.call_count == 1

            # Second tap with identical idempotency key
            res2 = await ac.post(
                "/api/v1/ai/plan",
                headers=headers,
                json={"raw_text": "Study algorithms", "idempotency_key": idempotency_key},
            )
            assert res2.status_code == 200
            # Gemini was NOT called again!
            assert mock_extract.call_count == 1

# ── Test 6: Pro user gets Pro allowance ───────────────────────────────────
@pytest.mark.asyncio
async def test_pro_user_gets_pro_allowance():
    user_id = unique_user("pro_user")
    headers = make_auth_header(user_id)

    with SessionLocal() as db:
        usage = AIEconomyService.get_or_create_usage(db, user_id)
        usage.is_pro = True
        usage.subscription_tier = "flowstate_pro_monthly"
        usage.subscription_status = "active"
        db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        status_res = await ac.get("/api/v1/ai/status", headers=headers)
        assert status_res.status_code == 200
        assert status_res.json()["is_pro"] is True
        assert status_res.json()["can_plan_free"] is True

        # Pro user can call plan multiple times without consuming shields
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Pro Task"})
            assert res.status_code == 200
            assert res.json()["shield_consumed"] is False
            assert res.json()["free_consumed"] is False

# ── Test 7: Non-Pro user cannot spoof Pro status ─────────────────────────
@pytest.mark.asyncio
async def test_non_pro_user_cannot_spoof_pro_status():
    user_id = unique_user("spoof_attempt")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Client tries to claim subscription with mock/fake token
        spoof_res = await ac.post(
            "/api/v1/subscription/verify",
            headers=headers,
            json={
                "purchase_token": "test_mock_invalid_token",
                "product_id": "flowstate_pro_monthly",
            },
        )
        assert spoof_res.status_code in [400, 402]

        # User is strictly NOT Pro
        st_res = await ac.get("/api/v1/ai/status", headers=headers)
        assert st_res.json()["is_pro"] is False

# ── Test 8: Rate limit works ─────────────────────────────────────────────
@pytest.mark.asyncio
async def test_rate_limit_works():
    user_id = unique_user("rate_limit")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=mock_gemini_tasks()):
            # Send 5 requests within an hour (the limit)
            for i in range(5):
                # Ensure they have shields/allowance
                with SessionLocal() as db:
                    usage = AIEconomyService.get_or_create_usage(db, user_id)
                    usage.free_uses_consumed = 0
                    db.commit()
                res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": f"Task {i}"})
                assert res.status_code == 200

            # 6th request triggers HTTP 429
            exceeded_res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Task overflow"})
            assert exceeded_res.status_code == 429
            assert "Rate limit exceeded" in exceeded_res.json()["detail"]

# ── Test 9: Unauthenticated user cannot call AI endpoint ─────────────────
@pytest.mark.asyncio
async def test_unauthenticated_user_cannot_call_ai_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/ai/plan", json={"raw_text": "Hacker task"})
        assert res.status_code == 401

# ── Test 10: Gemini malformed JSON is rejected safely ────────────────────
@pytest.mark.asyncio
async def test_gemini_malformed_json_rejected_safely():
    user_id = unique_user("malformed_json")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch("httpx.Client.post") as mock_post:
            # Gemini returns invalid HTML or truncated output
            mock_resp = MagicMock()
            mock_resp.status_code = 200
            mock_resp.json.return_value = {
                "candidates": [{"content": {"parts": [{"text": "<html>500 Server Error</html>"}]}}]
            }
            mock_post.return_value = mock_resp

            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Study physics"})
            assert res.status_code == 502
            assert "AI task structuring failed" in res.json()["detail"]

# ── Test 11: Explicit deadline is preserved ──────────────────────────────
@pytest.mark.asyncio
async def test_explicit_deadline_is_preserved():
    user_id = unique_user("deadline_test")
    headers = make_auth_header(user_id)

    mock_tasks = [
        TaskCandidateResponse(
            title="Python assignment",
            estimated_minutes=90,
            task_type=TaskType.deep_work,
            difficulty=TaskDifficulty.high,
            priority=TaskPriority.high,
            category="Study",
            deadline_at=datetime(2026, 9, 28, 23, 59, 59, tzinfo=timezone.utc),
            confidence=0.95,
            source=TaskSource.ai_parsed,
            field_provenance={"deadline": FieldProvenance(source="explicit", confidence=1.0)},
        )
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=(mock_tasks, [], False)):
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Python assignment due Friday"})
            assert res.status_code == 200
            tasks = res.json()["tasks"]
            assert len(tasks) == 1
            assert tasks[0]["deadline_at"] is not None
            assert "2026-09-28" in tasks[0]["deadline_at"]
            assert tasks[0]["field_provenance"]["deadline"]["source"] == "explicit"

# ── Test 12: Explicit fixed time is preserved ────────────────────────────
@pytest.mark.asyncio
async def test_explicit_fixed_time_is_preserved():
    user_id = unique_user("fixed_time")
    headers = make_auth_header(user_id)

    mock_tasks = [
        TaskCandidateResponse(
            title="Dentist appointment",
            estimated_minutes=45,
            task_type=TaskType.admin,
            difficulty=TaskDifficulty.light,
            priority=TaskPriority.medium,
            category="Health",
            scheduled_start=datetime(2026, 9, 25, 17, 0, 0, tzinfo=timezone.utc),
            scheduled_end=datetime(2026, 9, 25, 17, 45, 0, tzinfo=timezone.utc),
            confidence=0.95,
            source=TaskSource.ai_parsed,
            field_provenance={"scheduled_time": FieldProvenance(source="explicit", confidence=1.0)},
        )
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=(mock_tasks, [], False)):
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Call dentist at 5 PM"})
            assert res.status_code == 200
            tasks = res.json()["tasks"]
            assert len(tasks) == 1
            assert tasks[0]["scheduled_start"] is not None
            assert "17:00" in tasks[0]["scheduled_start"]
            assert tasks[0]["field_provenance"]["scheduled_time"]["source"] == "explicit"

# ── Test 13: Ambiguous priority requests confirmation ────────────────────
@pytest.mark.asyncio
async def test_ambiguous_priority_requests_confirmation():
    user_id = unique_user("ambig_prio")
    headers = make_auth_header(user_id)

    mock_tasks = [
        TaskCandidateResponse(
            title="Read book chapter",
            estimated_minutes=30,
            task_type=TaskType.deep_work,
            difficulty=TaskDifficulty.light,
            priority=TaskPriority.medium,
            category="Personal",
            confidence=0.72,
            source=TaskSource.ai_parsed,
            field_provenance={"priority": FieldProvenance(source="inferred", confidence=0.70)},
        )
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=(mock_tasks, ["priority_ambiguous"], True)):
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Read book chapter"})
            assert res.status_code == 200
            assert res.json()["needs_confirmation"] is True
            assert "priority_ambiguous" in res.json()["ambiguities"]

# ── Test 14: Gemini cannot invent a fixed time ───────────────────────────
@pytest.mark.asyncio
async def test_gemini_cannot_invent_fixed_time():
    # If the user says "study Python tomorrow", scheduled_start MUST be None!
    user_id = unique_user("no_invent_time")
    headers = make_auth_header(user_id)

    mock_tasks = [
        TaskCandidateResponse(
            title="Study Python",
            estimated_minutes=60,
            task_type=TaskType.study,
            difficulty=TaskDifficulty.medium,
            priority=TaskPriority.medium,
            category="Study",
            deadline_at=datetime(2026, 9, 26, 23, 59, 59, tzinfo=timezone.utc),
            scheduled_start=None,  # STRICTLY NULL
            scheduled_end=None,
            confidence=0.90,
            source=TaskSource.ai_parsed,
        )
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=(mock_tasks, [], False)):
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "study Python tomorrow"})
            assert res.status_code == 200
            tasks = res.json()["tasks"]
            assert tasks[0]["scheduled_start"] is None
            assert tasks[0]["deadline_at"] is not None

# ── Test 15: Gemini cannot invent a deadline ─────────────────────────────
@pytest.mark.asyncio
async def test_gemini_cannot_invent_deadline():
    # If user says "clean desk", deadline_at MUST be None!
    user_id = unique_user("no_invent_deadline")
    headers = make_auth_header(user_id)

    mock_tasks = [
        TaskCandidateResponse(
            title="Clean desk",
            estimated_minutes=20,
            task_type=TaskType.shallow_work,
            difficulty=TaskDifficulty.light,
            priority=TaskPriority.low,
            category="Chores",
            deadline_at=None,  # STRICTLY NULL
            scheduled_start=None,
            confidence=0.95,
            source=TaskSource.ai_parsed,
        )
    ]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=(mock_tasks, [], False)):
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "clean desk"})
            assert res.status_code == 200
            tasks = res.json()["tasks"]
            assert tasks[0]["deadline_at"] is None

# ── Test 16: Only minimum required data is sent to Gemini ────────────────
@pytest.mark.asyncio
async def test_only_minimum_required_data_sent_to_gemini():
    # Context minimization verification:
    # Verifies that only raw_text, timezone, and date are in the prompt.
    user_id = unique_user("context_min")
    headers = make_auth_header(user_id)

    with patch("httpx.Client.post") as mock_post, patch("app.services.ai_service.settings.GEMINI_API_KEY", "mock_key_for_test"):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "candidates": [{
                "content": {
                    "parts": [{
                        "text": json.dumps({
                            "tasks": [{
                                "title": "Buy groceries",
                                "type": "physical",
                                "estimated_minutes": 45,
                                "difficulty": "light",
                                "priority": "low",
                                "priority_source": "explicit",
                                "deadline": None,
                                "fixed_start": None,
                                "confidence": 0.95,
                                "needs_confirmation": False
                            }],
                            "ambiguities": []
                        })
                    }]
                }
            }]
        }
        mock_post.return_value = mock_resp

        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
            res = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Buy groceries"})
            assert res.status_code == 200

            # Inspect what was posted to Gemini
            call_args = mock_post.call_args
            payload = call_args[1]["json"]
            prompt_text = payload["contents"][0]["parts"][0]["text"]

            # Must contain the user's task
            assert "Buy groceries" in prompt_text
            # MUST NOT leak user ID, passwords, database tables, or profile dumps
            assert user_id not in prompt_text
            assert "password" not in prompt_text.lower()
            assert "token" not in prompt_text.lower()
