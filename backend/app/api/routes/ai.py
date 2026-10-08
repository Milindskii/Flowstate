from typing import Optional, List, Dict, Any
from datetime import datetime, timezone, time
import time as clock
import uuid
from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...core.logging import logger
from ...models.user import User
from ...schemas.ai import (
    AIPlanRequest,
    AIPlanResponse,
    AIUsageStatus,
    PlanningAttemptReport,
)
from ...schemas.calendar import ReplanRequest, ReplanResponse
from ...core.ai_limits import AIBusy
from ...services import ai_gateway
from ...services.ai_economy_service import AIEconomyService
from ...services.ai_service import AIService, GeminiFailure
from ...services.calendar_service import CalendarService
from ...services import planning_service, routine_planning, routine_service
from ...core.timezone import resolve_user_timezone
from ...core.economy_config import BMD_MAX_INPUT_CHARS, input_limit_for
from ...repositories.task_repository import TaskRepository

router = APIRouter(prefix="/ai", tags=["AI Planning Economy"])

# What a client may read about an AI failure: neutral Flowstate wording only. The provider's own reason text
# (model names, HTTP codes) goes to the diagnostics row and logs, never into an API response message.
_NEUTRAL_FAILURE_COPY = {
    "provider_quota": "Flowstate AI is at capacity right now",
    "provider_unavailable": "Flowstate AI is busy right now",
    "timeout": "Flowstate AI took too long to respond",
    "network": "Flowstate AI couldn't be reached",
    "malformed": "Flowstate AI's answer couldn't be read",
}
_NEUTRAL_FAILURE_DEFAULT = "Flowstate AI is temporarily unavailable"


class PlanFailure(Exception):
    """A Build My Day failure answered as {"detail": message, "failure_code": code} (spec §7)."""

    def __init__(self, http_status: int, code: str, message: str, headers: Optional[Dict[str, str]] = None,
                 extra: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.http_status, self.code, self.message, self.headers = http_status, code, message, headers or {}
        self.extra = extra or {}


def plan_failure_handler(_request, exc: "PlanFailure") -> JSONResponse:
    return JSONResponse(status_code=exc.http_status, content={"detail": exc.message, "failure_code": exc.code, **exc.extra},
                        headers=exc.headers or None)
calendar_service = CalendarService()


@router.get("/status", response_model=AIUsageStatus)
def get_ai_planning_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns the user's current AI planning usage status:
    - is_pro
    - free_uses_remaining
    - shields_available
    - can_plan_free
    - requires_shield
    """
    return AIEconomyService.get_usage_status(db, current_user.id)

@router.post("/plan", response_model=AIPlanResponse)
def generate_ai_plan(
    request: AIPlanRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Gemini Brain-Dump Task Planner (see services/ai_gateway.py for the lifecycle):
    - Replays a finished request by its per-user idempotency key (never charges or calls the provider twice).
    - Rate limits per user across all instances, and allows one in-flight AI request per user.
    - Atomically reserves exactly one allowance unit (Pro cap / free trial / Flow Shield) before the provider call.
    - Refunds the reservation on every failure; keeps it only for a successful plan.
    - Holds no database transaction while the provider is called; sheds load with 503 + Retry-After.
    """
    user_id = current_user.id
    tz_obj, user_tz = resolve_user_timezone(current_user, request.timezone)

    # 0. Input limit: before the idempotency lookup, the rate limit, any Shield reservation and any provider call, so an
    # oversized dump costs nothing and never takes a gateway slot. Words are counted exactly as the app counts them.
    word_count = len(request.raw_text.split())
    word_limit = input_limit_for(is_pro=False)  # same for everyone today; pass the real tier when Pro gets its own
    if word_count > word_limit or len(request.raw_text) > BMD_MAX_INPUT_CHARS:
        raise PlanFailure(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "input_too_long",
            f"That is a bit long for one plan. Please trim it to {word_limit} words or fewer. Nothing was charged.",
            extra={"limit_words": word_limit, "words": word_count},
        )

    # One stable planning request id (the client's idempotency key); every Gemini call is its own attempt.
    idempotency_key = request.idempotency_key or uuid.uuid4().hex
    request_id = idempotency_key

    def fail(http_status: int, code: str, message: str, reason: Optional[str] = None, latency_ms: Optional[int] = None,
             headers: Optional[Dict[str, str]] = None):
        AIEconomyService.record_attempt(db, user_id=user_id, request_id=request_id, status="failed",
                                        failure_code=code, failure_reason=reason or message, latency_ms=latency_ms)
        # `detail` stays the human message (existing contract); `failure_code` is the machine-readable reason.
        raise PlanFailure(http_status, code, message, headers)

    # 1-3. Idempotent replay, rate limit, and the atomic reservation.
    try:
        ticket = ai_gateway.begin(
            db, user_id=user_id, idempotency_key=idempotency_key,
            fingerprint=ai_gateway.request_fingerprint(request.raw_text, request.timezone, request.consume_shield),
            consume_shield=request.consume_shield,
        )
    except ai_gateway.QuotaExceeded as quota:
        fail(quota.status_code, quota.code, str(quota.detail))
    except ai_gateway.GatewayError as refusal:
        raise PlanFailure(refusal.http_status, refusal.code, refusal.message, refusal.headers)
    if isinstance(ticket, ai_gateway.Replay):
        cached_payload = ticket.payload
        cached_payload["usage"] = AIEconomyService.get_usage_status(db, user_id).model_dump()
        return cached_payload

    # 5. Execute Gemini Task Extraction (no DB transaction is open while the provider runs)
    if request.current_local_time is not None:
        now_local = request.current_local_time
        now_local = now_local.replace(tzinfo=tz_obj) if now_local.tzinfo is None else now_local.astimezone(tz_obj)
    else:
        now_local = datetime.now(tz_obj)
    not_charged = " Your free plans and shields were not charged."
    started = clock.perf_counter()
    db.rollback()  # end any implicit transaction so no pooled connection is held during the provider call
    try:
        res = ai_gateway.call_provider(
            AIService.extract_structured_plan_with_gemini,
            raw_text=request.raw_text,
            user_timezone_str=user_tz,
            request_id=request_id[:12],
            now_local=now_local,
        )
        if len(res) >= 4:
            candidates, ambiguities, needs_confirmation, planning_context = res[:4]
        else:
            candidates, ambiguities, needs_confirmation = res[:3]
            planning_context = None
    except AIBusy as busy:
        ai_gateway.fail(db, ticket, "ai_busy")
        retry = {"Retry-After": str(busy.retry_after)}
        fail(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_busy",
             "Flowstate AI is busy right now. Please try again in a moment." + not_charged,
             reason=busy.reason, headers=retry)
    except GeminiFailure as e:
        # Atomic guarantee: never consume the user's free credit or shield on failure; never fall back silently.
        ai_gateway.fail(db, ticket, e.code)
        logger.error(f"Gemini extraction failed for user {user_id}: code={e.code}")
        latency = round((clock.perf_counter() - started) * 1000)
        if e.code == "empty":
            fail(status.HTTP_422_UNPROCESSABLE_ENTITY, "empty",
                 "AI could not find any tasks in that text." + not_charged, latency_ms=latency)
        neutral = _NEUTRAL_FAILURE_COPY.get(e.code, _NEUTRAL_FAILURE_DEFAULT)
        fail(status.HTTP_502_BAD_GATEWAY, e.code, f"AI task structuring failed: {neutral}." + not_charged,
             reason=e.reason, latency_ms=latency)
    except Exception as e:
        ai_gateway.fail(db, ticket, "gemini_error")
        logger.error(f"Gemini extraction failed for user {user_id}: {type(e).__name__}")
        fail(status.HTTP_502_BAD_GATEWAY, "gemini_error", "AI task structuring failed." + not_charged, reason=type(e).__name__,
             latency_ms=round((clock.perf_counter() - started) * 1000))
    latency_ms = round((clock.perf_counter() - started) * 1000)

    if not candidates:
        # Nothing usable came back: an error, never an empty "success", and never charged.
        ai_gateway.fail(db, ticket, "empty")
        fail(status.HTTP_422_UNPROCESSABLE_ENTITY, "empty",
             "AI could not find any tasks in that text." + not_charged, latency_ms=latency_ms)

    # 5b. Shared planner (engines/planner.plan via services/planning_service adapters).
    # Failures are reported to the client (scheduling_error) instead of being swallowed.
    scheduling_error: Optional[str] = None
    plan_conflicts: List[Dict[str, Any]] = []
    routine_proposals: List[Any] = []
    try:
        from ...engines.scheduling_engine import PlanningProfile
        from ...repositories.readiness_repository import ReadinessRepository
        from ...repositories.task_performance_repository import TaskPerformanceRepository

        user_readiness = ReadinessRepository().get_by_user_id(db, current_user.id)
        perf_history = TaskPerformanceRepository().list_by_user(db, current_user.id, limit=20)
        plan_profile = PlanningProfile.from_user_context(
            readiness_profile=user_readiness,
            preferences=current_user.preferences,
            performance_history=perf_history,
        )

        # Learned weekly habits ("Gym, Tuesdays 7 PM") are soft suggestions for untimed tasks; a failure to load
        # them never affects the plan.
        learned_routines: List[Dict[str, Any]] = []
        try:
            from ...services import behavior_service
            learned_routines = behavior_service.routines(db, current_user.id, tz_obj, now_local)
        except Exception as learn_err:
            logger.warning(f"learned routines unavailable: {type(learn_err).__name__}")

        # The user's own order ("then", "after that") is kept when the model returned no ordering at all.
        AIService._link_from_text(candidates, request.raw_text)

        # Enforce segmentation outside the prompt: split multi-activity candidates before scheduling
        candidates = AIService.validate_and_segment_candidates(candidates, now_local, tz_obj)

        # Personal routines: keep the rolling 7-day horizon topped up, split routine statements out of the one-time
        # task list into proposals (confirmed by the user before anything is saved), and turn saved/stated routine
        # constraints into planner inputs. The deterministic planner still decides every flexible placement.
        today_local = now_local.date()
        routine_service.ensure_horizon(db, current_user.id, tz_obj, now_local)
        db.commit()
        saved_routines = routine_service.active_routines(db, current_user.id)
        candidates, routine_proposals = routine_planning.extract_proposals(
            candidates, planning_context, saved_routines, today=today_local, now_local=now_local, tz=tz_obj)
        routine_planning.apply_constraints(candidates, planning_context, saved_routines, today=today_local, tz=tz_obj)
        overridden = routine_planning.mark_overrides(candidates, saved_routines, tz=tz_obj, today=today_local)

        today_start_utc = datetime.combine(now_local.date(), time.min, tzinfo=tz_obj).astimezone(timezone.utc)
        existing_tasks = [t for t in TaskRepository.list_for_planning(db, current_user.id, today_start_utc)
                          if (t.routine_id, t.routine_date) not in overridden]

        base_day = next((c.temporal.target_date for c in candidates if c.temporal and c.temporal.target_date), now_local.date())
        planning_service.commitments_from_context(
            candidates, planning_context, request.raw_text, tz=tz_obj, base_date=base_day, now_local=now_local)
        plan_conflicts = planning_service.schedule_candidates(
            candidates,
            routine_planning.planning_context_with_routine_busy(planning_context, routine_proposals, tz_obj),
            existing_tasks,
            profile=plan_profile,
            tz=tz_obj,
            tz_name=user_tz,
            now_local=now_local,
            routines=learned_routines,
        )
    except Exception as sched_err:
        logger.error(f"Build My Day scheduling failed for user {user_id}: {type(sched_err).__name__}")
        scheduling_error = "scheduling_failed"
    else:
        # Nothing could be placed for capacity/deadline/dependency reasons: a failed plan, never charged.
        # (A stated time that already passed is user-fixable in the preview, so it is not a failure.)
        if candidates and all(c.unscheduled_reason and c.unscheduled_reason != "explicit_time_in_past" for c in candidates):
            scheduling_error = "no_tasks_scheduled"

    # 6. Finalize usage & commit deduction atomically
    response_data = {
        "tasks": [c.model_dump() for c in candidates],
        "planning_context": planning_context.model_dump() if planning_context else None,
        "ambiguities": ambiguities,
        "needs_confirmation": needs_confirmation,
        "shield_consumed": (ticket.charge_source == "shield"),
        "free_consumed": (ticket.charge_source == "free"),
        "timezone_used": user_tz,
        "scheduling_error": scheduling_error,
        "failure_code": "scheduling_failed" if scheduling_error else None,
        "conflicts": plan_conflicts,
        "routine_proposals": [p.model_dump(mode="json") for p in routine_proposals],
    }
    AIEconomyService.record_attempt(
        db, user_id=user_id, request_id=request_id,
        status="failed" if scheduling_error else "succeeded",
        failure_code="scheduling_failed" if scheduling_error else None,
        failure_reason=scheduling_error, latency_ms=latency_ms,
    )

    if scheduling_error is None:
        ai_gateway.succeed(db, ticket, response_data)
    else:
        # Tasks came back without slots: report it (scheduling_error) but never charge for a failed plan.
        ai_gateway.fail(db, ticket, "scheduling_failed")
        response_data["shield_consumed"] = response_data["free_consumed"] = False

    # 7. Return response with fresh usage status
    usage_status = AIEconomyService.get_usage_status(db, user_id)
    return AIPlanResponse(
        tasks=candidates,
        planning_context=planning_context,
        ambiguities=ambiguities,
        needs_confirmation=needs_confirmation,
        usage=usage_status,
        shield_consumed=response_data["shield_consumed"],
        free_consumed=response_data["free_consumed"],
        timezone_used=user_tz,
        scheduling_error=scheduling_error,
        failure_code=response_data["failure_code"],
        conflicts=plan_conflicts,
        routine_proposals=routine_proposals,
    )


@router.post("/planning-attempts", status_code=status.HTTP_204_NO_CONTENT)
def report_planning_attempt(
    report: PlanningAttemptReport,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Diagnostics for failures that never reached Gemini on the server (privacy declined, client network
    error). Records an attempt row; never charges and never calls Gemini."""
    AIEconomyService.record_attempt(
        db, user_id=current_user.id, request_id=report.request_id, status="failed",
        failure_code=report.failure_code, failure_reason=report.failure_reason,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@router.post("/replan", response_model=ReplanResponse)
def replan_day(
    request: ReplanRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Contextual Replan Endpoint:
    - Takes user's natural language change + current schedule context.
    - Generates a proposed PlanDiff (Before vs After) using existing SchedulingEngine.
    - Protects fixed appointments, completed tasks, and past time.
    - Does NOT mutate the database.
    """
    return calendar_service.generate_replan(
        db=db,
        user=current_user,
        request=request,
    )

