"""Performance regression (2026-10-07): on a remote Postgres every SQL statement is a network round trip, so the
hot read endpoints have a query budget, and a repeated GET (resume, pull-to-refresh, every task edit) writes nothing.
Measured before the fix: repeat /today 20 queries + 1 INSERT/commit, /calendar/day 9, repeat /flow 15 (commit +
3 refreshes)."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy import event

from app.db.session import engine
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import seed

WRITES = ("INSERT", "UPDATE", "DELETE")


@pytest.mark.asyncio
async def test_hot_read_endpoints_stay_within_query_budget_and_repeat_reads_never_write():
    uid, h = make_user()
    now = datetime.now(IST).replace(minute=0, second=0, microsecond=0)
    for i in range(8):
        seed(uid, f"Task {i}", now + timedelta(hours=i - 3), 45, planned_date=now.date())
    for i in range(4):
        seed(uid, f"Loose {i}", None, 30, planned_date=now.date())
    stmts = []

    def cb(conn, cursor, statement, params, context, executemany):
        stmts.append(statement.split()[0].upper())

    async def measure(ac, path):
        stmts.clear()
        r = await ac.get(path, headers=h)
        assert r.status_code == 200, r.text
        return len(stmts), sum(1 for s in stmts if s in WRITES)

    event.listen(engine, "before_cursor_execute", cb)
    try:
        async with client() as ac:
            await measure(ac, "/api/v1/today")  # first reads may create rows (new user)
            await measure(ac, "/api/v1/flow")
            today_q, today_w = await measure(ac, "/api/v1/today")
            cal_q, cal_w = await measure(ac, f"/api/v1/calendar/day?date={now.date()}")
            flow_q, flow_w = await measure(ac, "/api/v1/flow")
    finally:
        event.remove(engine, "before_cursor_execute", cb)
    assert (today_w, cal_w, flow_w) == (0, 0, 0)
    assert today_q <= 14, today_q
    assert cal_q <= 7, cal_q
    assert flow_q <= 10, flow_q
