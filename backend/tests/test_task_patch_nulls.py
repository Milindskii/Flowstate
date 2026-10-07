"""Finding 9: PATCH must distinguish 'field absent' from 'field explicitly null'."""
import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.main import app


@pytest.fixture
def headers():
    uid = f"patch-{uuid.uuid4().hex[:8]}"
    return {"Authorization": "Bearer " + create_access_token({"sub": uid, "email": f"{uid}@flowstate.local"})}


async def _create(ac, headers, **extra):
    body = {"title": "Patch me", "estimated_minutes": 30,
            "scheduled_start": "2026-10-05T10:00:00Z", "scheduled_end": "2026-10-05T10:30:00Z",
            "deadline_at": "2026-10-06T10:00:00Z", **extra}
    res = await ac.post("/api/v1/tasks", headers=headers, json=body)
    assert res.status_code == 201, res.text
    return res.json()["id"]


@pytest.mark.asyncio
async def test_clear_scheduled_start(headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        tid = await _create(ac, headers)
        res = await ac.patch(f"/api/v1/tasks/{tid}", headers=headers, json={"scheduled_start": None, "scheduled_end": None})
        assert res.status_code == 200
        body = res.json()
        assert body["scheduled_start"] is None and body["scheduled_end"] is None
        assert body["deadline_at"] is not None


@pytest.mark.asyncio
async def test_clear_deadline_via_put(headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        tid = await _create(ac, headers)
        res = await ac.put(f"/api/v1/tasks/{tid}", headers=headers, json={"deadline_at": None})
        assert res.status_code == 200 and res.json()["deadline_at"] is None


@pytest.mark.asyncio
async def test_unset_field_untouched(headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        tid = await _create(ac, headers)
        res = await ac.patch(f"/api/v1/tasks/{tid}", headers=headers, json={"title": "Renamed"})
        body = res.json()
        assert body["title"] == "Renamed"
        assert body["scheduled_start"] is not None and body["deadline_at"] is not None


@pytest.mark.asyncio
@pytest.mark.parametrize("field", ["title", "estimated_minutes", "status", "priority", "task_type"])
async def test_null_non_nullable_rejected(headers, field):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as ac:
        tid = await _create(ac, headers)
        res = await ac.patch(f"/api/v1/tasks/{tid}", headers=headers, json={field: None})
        assert res.status_code == 422, (field, res.text)
        after = await ac.get(f"/api/v1/tasks/{tid}", headers=headers)
        assert after.json()["title"] == "Patch me"
