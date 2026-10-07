import hashlib
import os
import tempfile

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.db.session import engine
from app.main import app

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEV_DB = os.path.join(BACKEND_DIR, "flowstate.db")


def _digest(path: str) -> str:
    if not os.path.exists(path):
        return "absent"
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


@pytest.mark.skipif(bool(os.environ.get("FLOWSTATE_TEST_DATABASE_URL")), reason="PostgreSQL release-gate run")
def test_tests_use_temp_database_not_dev_db():
    db_path = os.path.abspath(engine.url.database)
    assert db_path.startswith(os.path.abspath(tempfile.gettempdir()))
    assert db_path != os.path.abspath(DEV_DB)


@pytest.mark.asyncio
async def test_requests_do_not_modify_dev_db():
    before = _digest(DEV_DB)
    headers = {"Authorization": "Bearer " + create_access_token({"sub": "iso-user", "email": "iso@flowstate.local"})}
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/tasks", headers=headers, json={"title": "Isolation probe"})
        assert res.status_code == 201
    assert _digest(DEV_DB) == before
