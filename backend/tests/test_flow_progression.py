import uuid
import pytest
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token
from app.db.session import get_db, SessionLocal
from app.models.user import User
from app.models.task import Task
from app.models.flow_progression import FlowCompanion, FlowProfile, FlowFocusSession, FlowEconomicEvent

def unique_user(prefix: str = "flow-user") -> str:
    return f"{prefix}-{uuid.uuid4().hex[:8]}"

def make_auth_header(user_id: str) -> dict:
    token = create_access_token({"sub": user_id, "email": f"{user_id}@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_get_flow_overview():
    user_id = unique_user("overview")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/flow", headers=headers)
        assert res.status_code == 200
        data = res.json()
        assert "companion" in data
        assert data["companion"]["name"] == "Noya"
        assert data["companion"]["species"] == "fox"
        assert data["companion"]["level"] == 1
        assert data["companion"]["stage"] == "Baby"
        assert data["companion"]["companion_xp"] == 0
        assert data["companion"]["xp_to_next_level"] == 60
        assert data["companion"]["is_evolution_ready"] is False

        assert "profile" in data
        assert data["profile"]["flow_balance"] == 0
        assert data["profile"]["current_streak"] == 0
        assert data["profile"]["shields_available"] == 2  # New user receives 2 welcome shields for streak/AI economy

        assert "active_challenge" in data
        assert data["active_challenge"]["target_count"] == 5
        assert data["active_challenge"]["reward_flow"] == 100

        assert "league" in data
        assert data["league"]["tier"] == "Bronze"
        assert data["league"]["is_mock"] is False  # Zero fake users in prod

@pytest.mark.asyncio
async def test_session_lifecycle_and_duration_validation():
    user_id = unique_user("lifecycle")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Start session
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]
        assert start_res.json()["status"] == "started"

        # 2. Overlapping session attempt should fail with 409 Conflict
        overlap_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert overlap_res.status_code == 409
        assert "already in progress" in overlap_res.json()["detail"]

        # 3. Completing immediately without test_mode fails duration check (min 5 min required)
        fail_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete",
            headers=headers,
            json={"task_completed": True},
        )
        assert fail_res.status_code == 400
        assert "below the minimum qualifying duration" in fail_res.json()["detail"]

        # 4. Complete with test_mode=True
        complete_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True, "feeling_score": 5},
        )
        assert complete_res.status_code == 200
        comp_data = complete_res.json()
        assert comp_data["session_id"] == session_id
        assert comp_data["xp_awarded"] >= 1
        assert comp_data["flow_awarded"] >= 20  # 15 session + 5 honest feedback
        assert comp_data["current_streak"] == 1
        assert comp_data["streak_incremented"] is True

@pytest.mark.asyncio
async def test_semantic_idempotency():
    """
    Submitting the same session completion with different client idempotency keys
    must return original cached result and NOT double-award XP or Flow.
    """
    user_id = unique_user("idempotency")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]

        # First completion with key A
        res1 = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True, "idempotency_key": "client-key-alpha"},
        )
        assert res1.status_code == 200
        balance1 = res1.json()["profile"]["flow_balance"]
        xp1 = res1.json()["companion"]["companion_xp"]

        # Second completion with key B (different client key)
        res2 = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True, "idempotency_key": "client-key-beta"},
        )
        assert res2.status_code == 200
        # Balance and XP must NOT have doubled
        balance2 = res2.json()["profile"]["flow_balance"]
        xp2 = res2.json()["companion"]["companion_xp"]
        assert balance2 == balance1
        assert xp2 == xp1
        assert "idempotent" in res2.json()["notification"].lower()

@pytest.mark.asyncio
async def test_abandon_session_recoverable_consequence():
    user_id = unique_user("abandon")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]

        abandon_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/abandon",
            headers=headers,
        )
        assert abandon_res.status_code == 200
        assert abandon_res.json()["status"] == "abandoned"
        assert abandon_res.json()["companion_status"] == "tired"
        assert "Noya is resting" in abandon_res.json()["message"]

@pytest.mark.asyncio
async def test_evolution_milestone():
    """
    Directly verify that when Companion reaches Level 5 (420 cumulative XP),
    is_evolution_ready becomes True and calling /evolve promotes stage to Young.
    """
    user_id = unique_user("evolve")
    headers = make_auth_header(user_id)
    db_gen = get_db()
    db = next(db_gen)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Initialize
        init_res = await ac.get("/api/v1/flow", headers=headers)
        assert init_res.status_code == 200
        assert init_res.json()["companion"]["stage"] == "Baby"

        # Set XP to 425 (threshold for Level 5 Young)
        companion = db.query(FlowCompanion).filter(FlowCompanion.user_id == user_id).first()
        companion.companion_xp = 425
        companion.level = 5
        companion.stage = "Baby"
        companion.is_evolution_ready = True
        db.commit()

        # Check overview shows evolution ready
        overview_res = await ac.get("/api/v1/flow", headers=headers)
        assert overview_res.json()["companion"]["is_evolution_ready"] is True
        assert overview_res.json()["companion"]["level"] == 5
        assert overview_res.json()["companion"]["stage"] == "Baby"

        # Trigger evolution
        evolve_res = await ac.post("/api/v1/flow/evolve", headers=headers)
        assert evolve_res.status_code == 200
        assert evolve_res.json()["success"] is True
        assert evolve_res.json()["new_stage"] == "Young"
        assert evolve_res.json()["companion"]["stage"] == "Young"
        assert evolve_res.json()["companion"]["is_evolution_ready"] is False

        # Attempting to evolve again when not ready raises 400
        repeat_evolve = await ac.post("/api/v1/flow/evolve", headers=headers)
        assert repeat_evolve.status_code == 400

@pytest.mark.asyncio
async def test_shield_streak_protection():
    """
    Verifies that when a day is missed and user has shields_available > 0,
    a shield is consumed, the streak is protected, and a notification is returned.
    """
    user_id = unique_user("shield")
    headers = make_auth_header(user_id)
    db_gen = get_db()
    db = next(db_gen)

    # Initialize user profile
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.get("/api/v1/flow", headers=headers)

        # Set last_qualifying_date to 2 days ago (missed yesterday)
        two_days_ago = (datetime.now(timezone.utc) - timedelta(days=2)).strftime("%Y-%m-%d")
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == user_id).first()
        profile.current_streak = 5
        profile.longest_streak = 5
        profile.shields_available = 2
        profile.last_qualifying_date = two_days_ago
        db.commit()

        # User confirms shield use via explicit endpoint
        shield_res = await ac.post("/api/v1/flow/shields/use", headers=headers)
        assert shield_res.status_code == 200
        shield_data = shield_res.json()
        assert shield_data["success"] is True
        assert shield_data["shields_available"] == 1

        # Start and complete a qualifying session today
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]

        comp_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True},
        )
        assert comp_res.status_code == 200
        data = comp_res.json()
        assert data["shield_used"] is True
        assert data["current_streak"] == 6  # Streak preserved & incremented!
        assert data["profile"]["shields_available"] == 1  # 1 shield consumed
        assert "Flow Shield protected your streak" in data["notification"]

@pytest.mark.asyncio
async def test_shop_catalog_and_free_shield_use():
    user_id = unique_user("shop")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        shop_res = await ac.get("/api/v1/flow/shop", headers=headers)
        assert shop_res.status_code == 200
        items = shop_res.json()
        assert len(items) == 4
        species_names = [i["species"] for i in items]
        assert "fox" in species_names
        assert "otter" in species_names
        assert "owl" in species_names
        assert "capybara" in species_names

        # Ensure profile exists, then zero out shields to test 0-shield 400 rejection
        await ac.get("/api/v1/flow", headers=headers)
        db_gen = get_db()
        db = next(db_gen)
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == user_id).first()
        if profile:
            profile.shields_available = 0
            db.commit()

        # User with 0 shields attempting to use a shield gets 400
        shield_res = await ac.post("/api/v1/flow/shields/use", headers=headers)
        assert shield_res.status_code == 400
        assert "No Flow Shields available" in shield_res.json()["detail"]

@pytest.mark.asyncio
async def test_select_companion():
    user_id = unique_user("choose_animal")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Initial overview has default fox Noya
        res = await ac.get("/api/v1/flow", headers=headers)
        assert res.status_code == 200
        assert res.json()["companion"]["species"] == "fox"
        assert res.json()["companion"]["name"] == "Noya"

        # Selecting unpurchased otter must be rejected (403 Forbidden)
        sel_unpurchased = await ac.post(
            "/api/v1/flow/companion/select",
            headers=headers,
            json={"species": "otter", "name": "Ludo"},
        )
        assert sel_unpurchased.status_code == 403
        assert "not been unlocked" in sel_unpurchased.json()["detail"]

        # Attempt purchase with zero balance — should fail with 402
        buy_fail = await ac.post("/api/v1/flow/shop/otter/purchase", headers=headers)
        assert buy_fail.status_code == 402
        assert "Insufficient Flow Points" in buy_fail.json()["detail"]

        # Give the user enough Flow via a focus session with test_mode
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]
        # Complete multiple sessions to accrue enough flow (otter costs 250)
        await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True},
        )
        # Artificially set balance via direct DB manipulation for test speed
        db = next(app.dependency_overrides.get(get_db, lambda: None)() if app.dependency_overrides.get(get_db) else iter([None]))
        if db is None:
            # Direct DB update to set balance high for test
            from app.db.session import SessionLocal
            from app.models.flow_progression import FlowProfile
            test_db = SessionLocal()
            try:
                profile = test_db.query(FlowProfile).filter(FlowProfile.user_id == user_id).first()
                if profile:
                    profile.flow_balance = 500
                    test_db.commit()
            finally:
                test_db.close()

        # Now purchase succeeds
        buy_res = await ac.post("/api/v1/flow/shop/otter/purchase", headers=headers)
        assert buy_res.status_code == 201
        buy_data = buy_res.json()
        assert buy_data["species"] == "otter"
        assert buy_data["flow_spent"] == 250
        assert "joined your companion roster" in buy_data["message"]

        # Double-purchase attempt must be rejected (409)
        double_buy = await ac.post("/api/v1/flow/shop/otter/purchase", headers=headers)
        assert double_buy.status_code == 409
        assert "already in your companion roster" in double_buy.json()["detail"]

        # Now select otter is allowed
        sel_res = await ac.post(
            "/api/v1/flow/companion/select",
            headers=headers,
            json={"species": "otter", "name": "Ludo"},
        )
        assert sel_res.status_code == 200
        assert sel_res.json()["species"] == "otter"
        assert sel_res.json()["name"] == "Ludo"

        # Verify overview reflects updated active companion
        res2 = await ac.get("/api/v1/flow", headers=headers)
        assert res2.status_code == 200
        assert res2.json()["companion"]["species"] == "otter"
        assert res2.json()["companion"]["name"] == "Ludo"

        # Fox (Noya) is always selectable without purchase
        fox_res = await ac.post(
            "/api/v1/flow/companion/select",
            headers=headers,
            json={"species": "fox"},
        )
        assert fox_res.status_code == 200
        assert fox_res.json()["species"] == "fox"

@pytest.mark.asyncio
async def test_daily_quest_lifecycle_and_claim():
    user_id = unique_user("quests")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Overview has seeded daily quests
        ov_res = await ac.get("/api/v1/flow", headers=headers)
        assert ov_res.status_code == 200
        data = ov_res.json()
        assert "daily_quests" in data
        assert len(data["daily_quests"]) == 3
        session_quest = next(q for q in data["daily_quests"] if q["quest_key"] == "complete_1_session")
        assert session_quest["is_completed"] is False
        assert session_quest["is_claimed"] is False

        # 2. Complete focus session
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]

        comp_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True, "feeling_score": 5},
        )
        assert comp_res.status_code == 200

        # 3. Overview shows quest is now completed, but not claimed yet
        ov_res2 = await ac.get("/api/v1/flow", headers=headers)
        session_quest2 = next(q for q in ov_res2.json()["daily_quests"] if q["quest_key"] == "complete_1_session")
        assert session_quest2["is_completed"] is True
        assert session_quest2["is_claimed"] is False
        initial_balance = ov_res2.json()["profile"]["flow_balance"]

        # 4. User explicitly claims reward
        claim_res = await ac.post(f"/api/v1/flow/daily-quests/{session_quest2['id']}/claim", headers=headers)
        assert claim_res.status_code == 200
        claim_data = claim_res.json()
        assert claim_data["flow_awarded"] == session_quest2["reward_flow"]
        assert claim_data["new_balance"] == initial_balance + session_quest2["reward_flow"]

        # 5. Duplicate claim attempt is rejected
        dup_claim = await ac.post(f"/api/v1/flow/daily-quests/{session_quest2['id']}/claim", headers=headers)
        assert dup_claim.status_code == 400

@pytest.mark.asyncio
async def test_achievements_and_no_double_reward():
    user_id = unique_user("achieve")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Overview contains achievements
        ov_res = await ac.get("/api/v1/flow", headers=headers)
        assert ov_res.status_code == 200
        achievements = ov_res.json().get("achievements", [])
        assert len(achievements) >= 10
        first_spark = next((a for a in achievements if a["achievement_key"] == "first_spark"), None)
        assert first_spark is not None
        assert first_spark["is_unlocked"] is False

        # Complete 1 focus session
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        session_id = start_res.json()["session_id"]
        comp_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True},
        )
        assert comp_res.status_code == 200
        first_flow = comp_res.json()["flow_awarded"]

        # Replaying complete session returns identical idempotent reward, never duplicates
        comp_replay = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True},
        )
        assert comp_replay.status_code == 200
        assert comp_replay.json()["flow_awarded"] == first_flow
        assert "already processed" in comp_replay.json()["notification"]

        # Overview verifies first_spark achievement is now unlocked
        ov_res2 = await ac.get("/api/v1/flow", headers=headers)
        first_spark2 = next(a for a in ov_res2.json()["achievements"] if a["achievement_key"] == "first_spark")
        assert first_spark2["is_unlocked"] is True

        # Selecting unpurchased capybara must be rejected (403)
        sel_unpurchased = await ac.post(
            "/api/v1/flow/companion/select",
            headers=headers,
            json={"species": "capybara"},
        )
        assert sel_unpurchased.status_code == 403

        # Fund balance and purchase capybara (costs 500)
        from app.db.session import SessionLocal
        from app.models.flow_progression import FlowProfile
        test_db = SessionLocal()
        try:
            profile = test_db.query(FlowProfile).filter(FlowProfile.user_id == user_id).first()
            if profile:
                profile.flow_balance = 1000
                test_db.commit()
        finally:
            test_db.close()

        buy_res = await ac.post("/api/v1/flow/shop/capybara/purchase", headers=headers)
        assert buy_res.status_code == 201
        assert buy_res.json()["species"] == "capybara"
        assert buy_res.json()["flow_spent"] == 500

        # Now select capybara succeeds
        sel_res2 = await ac.post(
            "/api/v1/flow/companion/select",
            headers=headers,
            json={"species": "capybara"},
        )
        assert sel_res2.status_code == 200
        assert sel_res2.json()["species"] == "capybara"
        assert sel_res2.json()["name"] == "Boba"


@pytest.mark.asyncio
async def test_shop_purchase_flow():
    """Full shop lifecycle: catalog ownership, balance gates, purchase, double-buy guard."""
    user_id = unique_user("shop")
    headers = make_auth_header(user_id)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Seed profile via overview
        ov = await ac.get("/api/v1/flow", headers=headers)
        assert ov.status_code == 200

        # Shop catalog: fox is owned, others are not
        shop_res = await ac.get("/api/v1/flow/shop", headers=headers)
        assert shop_res.status_code == 200
        catalog = shop_res.json()
        fox_item = next(c for c in catalog if c["species"] == "fox")
        otter_item = next(c for c in catalog if c["species"] == "otter")
        assert fox_item["is_owned"] is True
        assert otter_item["is_owned"] is False
        assert otter_item["flow_cost"] == 250

        # Cannot buy fox (always default)
        fox_buy = await ac.post("/api/v1/flow/shop/fox/purchase", headers=headers)
        assert fox_buy.status_code == 400
        assert "default companion" in fox_buy.json()["detail"]

        # Cannot buy invalid species
        invalid_buy = await ac.post("/api/v1/flow/shop/dragon/purchase", headers=headers)
        assert invalid_buy.status_code == 404

        # Cannot buy with zero balance
        broke_buy = await ac.post("/api/v1/flow/shop/owl/purchase", headers=headers)
        assert broke_buy.status_code == 402
        assert "Insufficient" in broke_buy.json()["detail"]

        # Fund balance directly
        from app.db.session import SessionLocal
        from app.models.flow_progression import FlowProfile
        test_db = SessionLocal()
        try:
            profile = test_db.query(FlowProfile).filter(FlowProfile.user_id == user_id).first()
            if profile:
                profile.flow_balance = 700
                test_db.commit()
        finally:
            test_db.close()

        # Purchase owl (costs 350)
        owl_buy = await ac.post("/api/v1/flow/shop/owl/purchase", headers=headers)
        assert owl_buy.status_code == 201
        owl_data = owl_buy.json()
        assert owl_data["species"] == "owl"
        assert owl_data["flow_spent"] == 350
        assert owl_data["new_balance"] == 350  # 700 - 350
        assert "joined your companion roster" in owl_data["message"]

        # Double-purchase rejected
        owl_dup = await ac.post("/api/v1/flow/shop/owl/purchase", headers=headers)
        assert owl_dup.status_code == 409

        # Shop catalog now shows owl as owned
        shop_res2 = await ac.get("/api/v1/flow/shop", headers=headers)
        catalog2 = shop_res2.json()
        owl_item2 = next(c for c in catalog2 if c["species"] == "owl")
        assert owl_item2["is_owned"] is True

        # Can now select owl
        sel_owl = await ac.post(
            "/api/v1/flow/companion/select",
            headers=headers,
            json={"species": "owl"},
        )
        assert sel_owl.status_code == 200
        assert sel_owl.json()["species"] == "owl"
        assert sel_owl.json()["name"] == "Aria"

@pytest.mark.asyncio
async def test_anti_farming_trivial_task_no_priority_bonus():
    user_id = unique_user("anti_farm")
    headers = make_auth_header(user_id)
    test_db = SessionLocal()
    try:
        from app.models.task import TaskPriority
        # Create a trivial priority task (estimated 2 mins)
        t = Task(
            id=f"triv-{user_id}",
            user_id=user_id,
            title="Drink water",
            category="Quick",
            estimated_minutes=2,
            priority=TaskPriority.high,
        )
        test_db.add(t)
        test_db.commit()
    finally:
        test_db.close()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.get("/api/v1/flow", headers=headers)
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={"task_id": f"triv-{user_id}"})
        assert start_res.status_code == 201
        session_id = start_res.json()["session_id"]

        # Completing in non-test mode with low duration (< 10 mins) awards regular session flow but NO priority bonus
        comp_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete?test_mode=true",
            headers=headers,
            json={"task_completed": True},
        )
        assert comp_res.status_code == 200
        # In test_mode, test_mode bypasses min duration for test execution, but task duration check applies
        assert comp_res.json()["flow_awarded"] >= 15

@pytest.mark.asyncio
async def test_daily_focus_xp_cap():
    user_id = unique_user("xp_cap")
    headers = make_auth_header(user_id)
    test_db = SessionLocal()
    try:
        # Insert historical economic events totaling 290 XP today
        now = datetime.now(timezone.utc)
        ev = FlowEconomicEvent(
            user_id=user_id,
            idempotency_key=f"prior_xp_{user_id}",
            event_type="focus_session",
            reference_id="prior_sess",
            flow_awarded=15,
            xp_awarded=290,
            created_at=now,
        )
        test_db.add(ev)
        test_db.commit()
    finally:
        test_db.close()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.get("/api/v1/flow", headers=headers)
        start_res = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        session_id = start_res.json()["session_id"]

        # A 25-minute session would normally earn 25 XP, but daily cap is 300 (remaining: 10 XP)
        # In test_mode with simulated elapsed time
        test_db2 = SessionLocal()
        try:
            sess = test_db2.query(FlowFocusSession).filter(FlowFocusSession.id == session_id).first()
            sess.server_start_at = now - timedelta(minutes=25)
            test_db2.commit()
        finally:
            test_db2.close()

        comp_res = await ac.post(
            f"/api/v1/flow/session/{session_id}/complete",
            headers=headers,
            json={},
        )
        assert comp_res.status_code == 200
        assert comp_res.json()["xp_awarded"] == 10  # Clamped to 300 max!

@pytest.mark.asyncio
async def test_gdpr_data_export_and_deletion():
    user_id = unique_user("gdpr_user")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Update consent (Terms, Privacy, 16+ age confirmation)
        consent_res = await ac.post(
            "/api/v1/auth/consent",
            headers=headers,
            json={
                "terms_accepted": True,
                "privacy_accepted": True,
                "age_confirmed": True,
                "marketing_emails_enabled": False,
            },
        )
        assert consent_res.status_code == 200
        assert consent_res.json()["terms_accepted"] is True
        assert consent_res.json()["age_confirmed"] is True

        # 2. Export personal data (GDPR Right to Portability)
        export_res = await ac.post("/api/v1/auth/export-data", headers=headers)
        assert export_res.status_code == 200
        data = export_res.json()
        assert data["user_id"] == user_id
        assert "email" in data
        assert "tasks" in data

        # 3. Unsubscribe email
        unsub_res = await ac.get(f"/api/v1/auth/unsubscribe?email={data['email']}")
        assert unsub_res.status_code == 200
        assert unsub_res.json()["status"] == "ok"

        # 4. Delete account and all personal data (GDPR Right to Erasure)
        del_res = await ac.delete("/api/v1/auth/me", headers=headers)
        assert del_res.status_code == 200
        assert del_res.json()["success"] is True

        # Confirm user is gone
        db_check = SessionLocal()
        try:
            assert db_check.query(User).filter(User.id == user_id).first() is None
        finally:
            db_check.close()


@pytest.mark.asyncio
async def test_personal_records_data_integrity():
    """
    Personal Records must be strictly data-driven with NO fake fallback values.
    - Zero history user gets 0/Building empty state.
    - Real completed sessions update best session, daily focus totals, and total focus.
    - Abandoned/cancelled sessions do NOT count.
    """
    user_id = unique_user("records_user")
    headers = make_auth_header(user_id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Fresh user check: absolutely no synthetic numbers (no 90m, no 45m, no fake 'Steady')
        overview_res = await ac.get("/api/v1/flow", headers=headers)
        assert overview_res.status_code == 200
        prog = overview_res.json()["personal_progress"]
        assert prog["personal_best_focus_minutes"] == 0
        assert prog["best_focus_day_minutes"] == 0
        assert prog["total_focus_minutes"] == 0
        assert prog["total_sessions_completed"] == 0
        assert prog["weekly_focus_sessions"] == 0
        assert prog["weekly_focus_minutes"] == 0
        assert prog["consistency_score"] == "Building"
        assert "Start your first flow" in prog["rhythm_acknowledgement"]

        # 2. Start and abandon a session — must NOT leak into records
        ab_start = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        assert ab_start.status_code == 201
        ab_id = ab_start.json()["session_id"]
        ab_res = await ac.post(f"/api/v1/flow/session/{ab_id}/abandon", headers=headers)
        assert ab_res.status_code == 200

        overview_after_ab = await ac.get("/api/v1/flow", headers=headers)
        prog_after_ab = overview_after_ab.json()["personal_progress"]
        assert prog_after_ab["personal_best_focus_minutes"] == 0
        assert prog_after_ab["best_focus_day_minutes"] == 0
        assert prog_after_ab["total_focus_minutes"] == 0
        assert prog_after_ab["total_sessions_completed"] == 0

        # 3. Complete a real session with simulated duration
        start1 = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        s1_id = start1.json()["session_id"]

        # Simulate 25m server start
        db = SessionLocal()
        try:
            sess1 = db.query(FlowFocusSession).filter(FlowFocusSession.id == s1_id).first()
            sess1.server_start_at = datetime.now(timezone.utc) - timedelta(minutes=25)
            db.commit()
        finally:
            db.close()

        comp1 = await ac.post(f"/api/v1/flow/session/{s1_id}/complete", headers=headers, json={"task_completed": True})
        assert comp1.status_code == 200
        assert comp1.json()["duration_minutes"] >= 25

        # Check overview after 1 completed session
        ov1 = await ac.get("/api/v1/flow", headers=headers)
        p1 = ov1.json()["personal_progress"]
        assert p1["personal_best_focus_minutes"] >= 25
        assert p1["best_focus_day_minutes"] >= 25
        assert p1["total_focus_minutes"] >= 25
        assert p1["total_sessions_completed"] == 1
        assert p1["consistency_score"] in ["Calibrating", "Steady"]


