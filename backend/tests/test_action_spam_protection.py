"""Phase 3: rapid repeated requests are one logical request (no duplicate model call, no duplicate Shield charge).

Build My Day is covered by test_ai_gateway.py / test_shield_economy.py (concurrent + duplicate-key cases) and a
concurrent AI Replan by test_replan_admission.py. This adds the retry case the app now relies on: Replan sends one
idempotency key per user message, so retrying a message that already succeeded costs nothing.
"""
import pytest

from tests.plan_helpers import client
from tests.test_replan_admission import AI_MESSAGE, Model, NOW, op, ops, ref
from tests.test_replan_ai import _day
from tests.test_shield_economy import _poor_free_user, _shields


@pytest.mark.asyncio
async def test_retrying_a_replan_message_with_the_same_key_is_not_charged_again(monkeypatch):
    model = Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out"))))
    uid, h = _poor_free_user(2)
    _day(uid)
    body = {"selected_date": "2026-10-05", "user_message": AI_MESSAGE, "current_local_time": NOW.isoformat(),
            "timezone": "Asia/Kolkata", "idempotency_key": "replan-fixed-1"}
    async with client() as ac:
        r1 = await ac.post("/api/v1/ai/replan", headers=h, json=body)
        assert r1.status_code == 200, r1.text
        assert _shields(uid) == 1                              # the first send cost exactly one Shield
        r2 = await ac.post("/api/v1/ai/replan", headers=h, json=body)
        assert r2.status_code == 200, r2.text
    assert _shields(uid) == 1                                  # the retry of the same message cost nothing
    assert len(model.calls) == 1                               # and did not call the model again
