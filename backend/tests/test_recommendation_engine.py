import pytest
from datetime import datetime, timezone, timedelta
from app.engines.recommendation_engine import (
    GenericRecommendationEngine,
    PersonalizedRecommendationEngine,
    TASK_VALUE_MAP,
)
from app.models.task import Task, TaskPriority, TaskType, TaskStatus
from app.models.recommendation import RecommendationDecision, RecommendationOutcome
from app.repositories.recommendation_repository import RecommendationRepository


@pytest.fixture
def db_session():
    from app.db.session import SessionLocal, Base, engine
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def make_dummy_task(
    id="task-1",
    title="Test Task",
    priority=TaskPriority.medium,
    task_type=TaskType.deep_work,
    deadline_at=None,
    estimated_minutes=45,
):
    t = Task(
        id=id,
        user_id="user-1",
        title=title,
        priority=priority,
        task_type=task_type,
        status=TaskStatus.todo,
        deadline_at=deadline_at,
        estimated_minutes=estimated_minutes,
    )
    return t


def test_priority_and_importance_weighting():
    """Verify high importance/priority beats lower priority even with same readiness."""
    engine = GenericRecommendationEngine()
    now = datetime.now(timezone.utc)

    urgent_task = make_dummy_task(id="t-urgent", priority=TaskPriority.urgent)
    low_task = make_dummy_task(id="t-low", priority=TaskPriority.low)

    score_urgent = engine.score_task(urgent_task, now, readiness_score=0.8)
    score_low = engine.score_task(low_task, now, readiness_score=0.8)

    assert score_urgent.score > score_low.score
    assert score_urgent.breakdown["task_value"] > score_low.breakdown["task_value"]


def test_completion_probability_is_multiplier_not_objective():
    """
    Core product invariant:
    A high-importance task should not be demoted beneath a trivial task just
    because the trivial task is 'easier' or has higher raw completion probability.
    """
    engine = GenericRecommendationEngine()
    now = datetime.now(timezone.utc)

    # Exam study (high importance, deep work)
    study_task = make_dummy_task(
        id="t-study",
        title="Study for Exam",
        priority=TaskPriority.high,
        task_type=TaskType.deep_work,
    )

    # Reply to message (low importance, admin)
    admin_task = make_dummy_task(
        id="t-admin",
        title="Reply to message",
        priority=TaskPriority.low,
        task_type=TaskType.admin,
    )

    # At normal readiness (0.75)
    score_study = engine.score_task(study_task, now, readiness_score=0.75)
    score_admin = engine.score_task(admin_task, now, readiness_score=0.75)

    assert score_study.score > score_admin.score, "Important deep work must outscore trivial low-priority work"


def test_overdue_and_deadline_urgency():
    """Overdue tasks and soon-deadline tasks must receive urgency boost."""
    engine = GenericRecommendationEngine()
    now = datetime.now(timezone.utc)

    overdue_task = make_dummy_task(
        id="t-overdue",
        priority=TaskPriority.medium,
        deadline_at=now - timedelta(hours=2),
    )
    future_task = make_dummy_task(
        id="t-future",
        priority=TaskPriority.medium,
        deadline_at=now + timedelta(days=5),
    )

    score_overdue = engine.score_task(overdue_task, now, readiness_score=0.70)
    score_future = engine.score_task(future_task, now, readiness_score=0.70)

    assert score_overdue.score > score_future.score
    assert any("Overdue" in r for r in score_overdue.reasons)


def test_suggest_next_window():
    """Tests that suggest_next_window provides a realistic future focus window for postponed tasks."""
    engine = GenericRecommendationEngine()
    now = datetime.now(timezone.utc)
    task = make_dummy_task(id="t-later")

    window = engine.suggest_next_window(task, now)
    assert "label" in window
    assert "Tomorrow" in window["label"] or "Today" in window["label"]
    assert "suggested_time" in window


def test_ranking_and_explanation():
    """Tests rank() returns sorted candidates with explanation reason bullets."""
    engine = GenericRecommendationEngine()
    now = datetime.now(timezone.utc)

    tasks = [
        make_dummy_task(id="t-low", priority=TaskPriority.low),
        make_dummy_task(id="t-urgent", priority=TaskPriority.urgent),
        make_dummy_task(id="t-med", priority=TaskPriority.medium),
    ]

    scored_list, strategy = engine.rank(tasks, now, readiness_score=0.80, allow_exploration=False)
    assert len(scored_list) == 3
    assert scored_list[0].task.id == "t-urgent"
    assert strategy == "exploitation"
    assert len(scored_list[0].reasons) > 0


def test_recommendation_repository_isolation(db_session):
    """Verifies user-isolated decision and outcome persistence."""
    import uuid
    repo = RecommendationRepository()
    dec_id = f"dec-{uuid.uuid4()}"

    decision = RecommendationDecision(
        id=dec_id,
        user_id="user-a",
        readiness_score=82.0,
        readiness_confidence=0.85,
        engine_version="generic_v1",
        recommended_task_id="t-1",
    )
    decision.candidate_scores = [{"task_id": "t-1", "score": 0.95}]
    decision.recommendation_reasons = ["High priority", "Optimal morning window"]

    repo.create_decision(db_session, decision)

    # Same user can access
    found = repo.get_decision(db_session, dec_id, "user-a")
    assert found is not None
    assert found.readiness_score == 82.0
    assert found.candidate_scores[0]["score"] == 0.95

    # Other user CANNOT access (strict user isolation)
    isolated = repo.get_decision(db_session, dec_id, "user-b")
    assert isolated is None

    # Log outcome
    outcome = RecommendationOutcome(
        decision_id=dec_id,
        user_id="user-a",
        task_id="t-1",
        user_action="accepted",
        outcome="completed",
        actual_minutes=45,
    )
    repo.create_outcome(db_session, outcome)

    found_outcome = repo.get_outcome_by_decision(db_session, dec_id, "user-a")
    assert found_outcome is not None
    assert found_outcome.user_action == "accepted"
    assert found_outcome.actual_minutes == 45
