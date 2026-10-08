"""Undoing a completion is the account's, not one screen's: PATCH status=todo reopens the task on the server."""
import pytest

from tests.plan_helpers import client, make_user


@pytest.mark.asyncio
async def test_reopening_a_completed_task_clears_its_completion():
    uid, h = make_user()
    async with client() as ac:
        tid = (await ac.post("/api/v1/tasks", headers=h, json={"title": "Read", "estimated_minutes": 30})).json()["id"]
        done = (await ac.post(f"/api/v1/tasks/{tid}/complete", headers=h, json={"actual_minutes": 25})).json()
        assert done["status"] == "completed" and done["completed_at"]

        reopened = await ac.patch(f"/api/v1/tasks/{tid}", headers=h, json={"status": "todo"})
        assert reopened.status_code == 200
        body = reopened.json()
        assert body["status"] == "todo" and body["completed_at"] is None

        # it can be completed again, and a second reopen of an open task is harmless
        again = (await ac.post(f"/api/v1/tasks/{tid}/complete", headers=h, json={})).json()
        assert again["status"] == "completed"
        assert (await ac.patch(f"/api/v1/tasks/{tid}", headers=h, json={"status": "todo"})).json()["completed_at"] is None
        assert (await ac.patch(f"/api/v1/tasks/{tid}", headers=h, json={"status": "todo"})).status_code == 200


@pytest.mark.asyncio
async def test_a_task_of_another_account_cannot_be_reopened():
    a, ha = make_user(prefix="reopen-a")
    b, hb = make_user(prefix="reopen-b")
    async with client() as ac:
        tid = (await ac.post("/api/v1/tasks", headers=ha, json={"title": "Mine", "estimated_minutes": 30})).json()["id"]
        await ac.post(f"/api/v1/tasks/{tid}/complete", headers=ha, json={})
        res = await ac.patch(f"/api/v1/tasks/{tid}", headers=hb, json={"status": "todo"})
        assert res.status_code == 404
        assert (await ac.get(f"/api/v1/tasks/{tid}", headers=ha)).json()["status"] == "completed"
