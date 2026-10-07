"""
Flowstate shared planner (spec sections 2 and 4).

ONE deterministic, side-effect-free function, ``plan()``, is the scheduling contract for
both Build My Day (``mode="build"``) and Replan (``mode="replan"``).

Purity contract (binding, enforced by tests/test_planner_purity.py):
  * imports only the standard library and ``scheduling_engine`` (itself pure);
  * no database, FastAPI, settings, logging, filesystem, network or Flutter concepts;
  * no clock (``now_local`` is an explicit argument), no randomness;
  * inputs are frozen dataclasses and are never mutated;
  * the same inputs always produce an equal ``PlanResult``.
Persistence, authentication, timezone *resolution* and schema mapping live in adapters,
which only (a) build ``PlanItem`` objects and (b) map ``PlanResult`` to responses.

Contract invariants (C1-C11) are documented in docs/superpowers/specs/build-my-day-replan.md.
"""
from dataclasses import dataclass, replace
from datetime import date, datetime, timedelta
from typing import Dict, List, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from .scheduling_engine import PlanningProfile, SchedulingEngine

MODES = ("build", "replan")
PAST_TOLERANCE = timedelta(seconds=60)
_ENGINE = SchedulingEngine()  # stateless scoring helper

# Immutable-bucket kinds
K_COMPLETED = "completed"
K_IN_PROGRESS = "in_progress"
K_LOCKED = "locked"
K_EXISTING = "existing"          # build mode: already-persisted flexible task, left alone
K_OUT_OF_SCOPE = "out_of_scope"  # replan mode: other date than the one being replanned
K_INACTIVE = "inactive"          # cancelled / archived / unknown status


class PlanInvariantError(AssertionError):
    """Raised when the planner would return a result that violates the contract (a bug)."""


@dataclass(frozen=True)
class PlanTemporal:
    """User-stated timing constraints. Hard: target_date, earliest_start, latest_end,
    relative_before/after. Soft: preferred_start, preferred_window_*."""
    target_date: Optional[date] = None
    earliest_start: Optional[datetime] = None
    latest_end: Optional[datetime] = None
    preferred_start: Optional[datetime] = None
    preferred_window_start: Optional[datetime] = None
    preferred_window_end: Optional[datetime] = None
    relative_before: Optional[str] = None
    relative_after: Optional[str] = None


@dataclass(frozen=True)
class PlanItem:
    id: str
    title: str
    estimated_minutes: int = 45
    status: str = "todo"                      # todo | postponed | in_progress | completed | other
    priority: str = "medium"
    task_type: str = "deep_work"
    start: Optional[datetime] = None          # persisted / requested slot (aware)
    end: Optional[datetime] = None
    time_locked: bool = False                 # user-fixed time: never moved
    is_commitment: bool = False               # fixed block the user is away for: busy time, never work
    deadline_at: Optional[datetime] = None
    temporal: Optional[PlanTemporal] = None
    planned_date: Optional[date] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    is_new: bool = False                      # candidate not yet persisted
    force_replace: bool = False               # an op targets it: drop its slot and re-place
    depends_on: Tuple[str, ...] = ()          # ids that must finish first
    rank: Optional[int] = None                # user-stated priority order (lower first)
    pinned: bool = False                      # existing item that this plan must not move (any mode)
    origin_start: Optional[datetime] = None   # persisted slot to report as 'previous' when `start` is a proposal
    yield_to_fixed: bool = False              # new explicit time that yields (is re-placed) if it collides with a fixed item
    focus_level: str = "medium"               # high -> same peak-hour preference as deep work
    deadline_kind: str = "hard"               # hard: never ends after deadline_at; soft: may, only when necessary


@dataclass(frozen=True)
class Placement:
    item_id: str
    start: datetime
    end: datetime
    moved: bool                               # True if it differs from the persisted slot
    previous_start: Optional[datetime]
    primary_reason: str
    secondary_reasons: Tuple[str, ...]
    explanation: str
    day_offset: int = 0


@dataclass(frozen=True)
class Immutable:
    item_id: str
    kind: str
    start: Optional[datetime]
    end: Optional[datetime]


@dataclass(frozen=True)
class Unplaced:
    item_id: str
    reason: str                               # no_capacity | deadline_infeasible | bound_infeasible | explicit_time_in_past | dependency_unschedulable
    message: str
    suggestion: Optional[Placement] = None    # proposed roll-over, never applied by the planner


@dataclass(frozen=True)
class Conflict:
    code: str
    message: str
    item_ids: Tuple[str, ...]


@dataclass(frozen=True)
class PlanResult:
    placements: Tuple[Placement, ...]
    immutable: Tuple[Immutable, ...]
    unscheduled: Tuple[Unplaced, ...]
    conflicts: Tuple[Conflict, ...]
    timezone_used: str
    mode: str

    def bucket_ids(self) -> Dict[str, str]:
        out: Dict[str, str] = {}
        for p in self.placements:
            out[p.item_id] = "placed"
        for i in self.immutable:
            out[i.item_id] = "immutable:" + i.kind
        for u in self.unscheduled:
            out[u.item_id] = "unscheduled"
        return out


class _View:
    """Duck-typed task the scoring engine reads. Flexible views never carry a start."""
    def __init__(self, item: PlanItem, temporal: Optional[PlanTemporal], ignore_deadline: bool = False):
        self.id = item.id
        self.title = item.title
        self.estimated_minutes = item.estimated_minutes
        self.priority = item.priority
        # A user-stated need for focus gets the same peak-hour placement as deep work.
        self.task_type = "deep_work" if item.focus_level == "high" else item.task_type
        self.deadline_at = None if ignore_deadline else item.deadline_at
        self.temporal = temporal
        self.scheduled_start = None
        self.status = item.status


def _aware(dt: Optional[datetime], label: str) -> Optional[datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        raise ValueError(f"planner requires timezone-aware datetimes ({label} is naive)")
    return dt


def _overlaps(a: Tuple[datetime, datetime], b: Tuple[datetime, datetime]) -> bool:
    return a[0] < b[1] and a[1] > b[0]


def completed_interval(
    started_at: Optional[datetime], completed_at: Optional[datetime],
    slot_start: Optional[datetime], slot_end: Optional[datetime], minutes: int,
) -> Tuple[Optional[datetime], Optional[datetime]]:
    """The time a finished task actually occupied, never negative and never a sliver.

    A task finished before its planned slot (or marked done at once) has ``completed_at`` earlier than the
    slot start, or a seconds-long span: the interval then ends at ``completed_at`` and lasts its estimate.
    """
    s = started_at or slot_start
    e = completed_at or slot_end
    if e is not None and (s is None or e - s < timedelta(minutes=1)):
        s = e - timedelta(minutes=minutes)
    return s, e


def _slot_of(it: PlanItem) -> Tuple[Optional[datetime], Optional[datetime]]:
    start = _aware(it.start, f"{it.id}.start")
    if start is None:
        return None, None
    end = _aware(it.end, f"{it.id}.end") or (start + timedelta(minutes=it.estimated_minutes))
    if end <= start:
        end = start + timedelta(minutes=it.estimated_minutes)
    return start, end



def _clock(dt: datetime) -> str:
    h = dt.hour % 12 or 12
    return f"{h}:{dt.minute:02d} {'AM' if dt.hour < 12 else 'PM'}"


def _bound_message(it: "PlanItem", t: Optional["PlanTemporal"], today: date, tz) -> str:
    """Why an item could not be placed inside a limit the user stated. Placement is never affected by this text.

    The only limit is a day (or a cut-off time): say there is no free time left in it, with the task's length, so the
    user can move it or make room. Anything combined/relative keeps the general wording.
    """
    only_day = t is not None and t.target_date and not (t.latest_end or t.earliest_start or t.relative_before or t.relative_after)
    only_cutoff = t is not None and t.latest_end and not (t.target_date or t.earliest_start or t.relative_before or t.relative_after)
    if only_day:
        d = t.target_date
        label = "today" if d == today else "tomorrow" if d == today + timedelta(days=1) else f"on {d:%a %b} {d.day}"
        return f"There isn't enough free time {label} for '{it.title}' ({it.estimated_minutes} min)."
    if only_cutoff:
        return f"There isn't enough free time before {_clock(t.latest_end.astimezone(tz))} for '{it.title}' ({it.estimated_minutes} min)."
    return f"'{it.title}' cannot be placed within the time limits you set."

def plan(
    items: Sequence[PlanItem],
    *,
    now_local: datetime,
    tz: ZoneInfo,
    profile: PlanningProfile,
    mode: str,
    scope_date: Optional[date] = None,
    extra_busy: Sequence[Tuple[datetime, datetime]] = (),
    extra_buffer_minutes: int = 0,
    tz_name: Optional[str] = None,
) -> PlanResult:
    if mode not in MODES:
        raise ValueError(f"mode must be one of {MODES}")
    now = _aware(now_local, "now_local").astimezone(tz)
    ids = [i.id for i in items]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate item ids")
    today = now.astimezone(tz).date()

    base_hard: List[Tuple[datetime, datetime]] = []
    for k, (s, e) in enumerate(extra_busy):
        base_hard.append((_aware(s, f"extra_busy[{k}].start"), _aware(e, f"extra_busy[{k}].end")))

    immutable: List[Immutable] = []
    unscheduled: List[Unplaced] = []
    conflicts: List[Conflict] = []
    fixed_intervals: List[Tuple[str, str, datetime, datetime]] = []   # (id, kind, s, e) for conflict checks
    end_by_id: Dict[str, datetime] = {}
    movable: List[PlanItem] = []
    yielding: List[PlanItem] = []

    # ── 1. Partition (C1-C3) ────────────────────────────────────────────────
    for it in items:
        start, end = _slot_of(it)
        _aware(it.deadline_at, f"{it.id}.deadline_at")
        _aware(it.started_at, f"{it.id}.started_at")
        _aware(it.completed_at, f"{it.id}.completed_at")
        if it.status == "completed":
            s, e = completed_interval(it.started_at, it.completed_at, start, end, it.estimated_minutes)
            if s is not None and e is not None and e > s:
                base_hard.append((s, e))
                fixed_intervals.append((it.id, K_COMPLETED, s, e))
                end_by_id[it.id] = e
            immutable.append(Immutable(it.id, K_COMPLETED, s, e))
        elif it.status == "in_progress":
            # D7: busy until the later of its planned end and now.
            s = it.started_at or start or now
            e = max(s + timedelta(minutes=it.estimated_minutes), now)
            base_hard.append((s, e))
            fixed_intervals.append((it.id, K_IN_PROGRESS, s, e))
            end_by_id[it.id] = e
            immutable.append(Immutable(it.id, K_IN_PROGRESS, s, e))
        elif it.status in ("todo", "postponed"):
            if it.time_locked and start is not None and not it.force_replace and it.is_new and it.yield_to_fixed:
                yielding.append(it)
                continue
            if it.time_locked and start is not None and not it.force_replace:
                if it.is_new and start < now - PAST_TOLERANCE:
                    unscheduled.append(Unplaced(
                        it.id, "explicit_time_in_past",
                        f"'{it.title}' is set for a time that has already passed. Choose a new time."))
                    conflicts.append(Conflict("explicit_time_in_past", f"{it.title}: requested time is in the past", (it.id,)))
                    continue
                base_hard.append((start, end))
                fixed_intervals.append((it.id, K_LOCKED, start, end))
                end_by_id[it.id] = end
                immutable.append(Immutable(it.id, K_LOCKED, start, end))
            else:
                movable.append(it)
        else:
            immutable.append(Immutable(it.id, K_INACTIVE, start, end))

    # A new explicit time that collides with an existing fixed item yields to it: the fixed item is
    # never touched; the new one is re-placed near its requested time and the collision is reported.
    for it in yielding:
        start, end = _slot_of(it)
        if start < now - PAST_TOLERANCE:
            unscheduled.append(Unplaced(
                it.id, "explicit_time_in_past",
                f"'{it.title}' is set for a time that has already passed. Choose a new time."))
            conflicts.append(Conflict("explicit_time_in_past", f"{it.title}: requested time is in the past", (it.id,)))
            continue
        clash = [f for f in fixed_intervals if _overlaps((start, end), (f[2], f[3]))]
        if clash:
            conflicts.append(Conflict(
                "explicit_time_conflicts_with_fixed",
                f"'{it.title}' conflicts with a fixed item; it was placed at the nearest feasible time instead.",
                tuple([it.id] + sorted({f[0] for f in clash})),
            ))
            base_t = it.temporal or PlanTemporal()
            movable.append(replace(it, time_locked=False, start=None, end=None, temporal=replace(base_t, preferred_start=start)))
        else:
            base_hard.append((start, end))
            fixed_intervals.append((it.id, K_LOCKED, start, end))
            end_by_id[it.id] = end
            immutable.append(Immutable(it.id, K_LOCKED, start, end))

    # ── 2. Decide who is movable (build vs replan) ───────────────────────────
    to_place: List[PlanItem] = []
    keep_candidates: List[PlanItem] = []
    for it in movable:
        start, end = _slot_of(it)
        if (mode == "build" and not it.is_new) or it.pinned:
            if start is not None:
                base_hard.append((start, end))
                fixed_intervals.append((it.id, K_EXISTING, start, end))
                end_by_id[it.id] = end
            immutable.append(Immutable(it.id, K_EXISTING, start, end))
            continue
        if mode == "replan" and not it.is_new and not it.force_replace and scope_date is not None:
            if start is not None and start.astimezone(tz).date() != scope_date:
                base_hard.append((start, end))
                fixed_intervals.append((it.id, K_OUT_OF_SCOPE, start, end))
                end_by_id[it.id] = end
                immutable.append(Immutable(it.id, K_OUT_OF_SCOPE, start, end))
                continue
            if start is None and it.planned_date is not None and it.planned_date != scope_date and it.planned_date > today:
                immutable.append(Immutable(it.id, K_OUT_OF_SCOPE, None, None))
                continue
        if mode == "replan" and start is not None and not it.is_new and not it.force_replace:
            keep_candidates.append(it)
        else:
            to_place.append(it)

    # locked-vs-fixed overlaps are the user's choice: reported, never "fixed" by moving anyone
    for a in range(len(fixed_intervals)):
        for b in range(a + 1, len(fixed_intervals)):
            ia, ib = fixed_intervals[a], fixed_intervals[b]
            if K_LOCKED in (ia[1], ib[1]) and _overlaps((ia[2], ia[3]), (ib[2], ib[3])):
                ids_pair = tuple(sorted((ia[0], ib[0])))
                conflicts.append(Conflict("locked_overlap", "Two fixed items overlap; neither was moved.", ids_pair))

    def order_key(it: PlanItem, idx: int):
        rank = it.rank if it.rank is not None else 50
        return (rank, _ENGINE.urgency_sort_key(_View(it, None), now, tz), idx)

    index_of = {it.id: n for n, it in enumerate(items)}

    # ── 3. Keep-if-valid pass (replan stability, C11) ────────────────────────
    kept: Dict[str, Tuple[PlanItem, datetime, datetime]] = {}
    for it in sorted(keep_candidates, key=lambda x: order_key(x, index_of[x.id])):
        start, end = _slot_of(it)
        busy_now = base_hard + [(s, e) for (_, s, e) in kept.values()]
        ok = (
            all(d not in kept or kept[d][2] <= start for d in it.depends_on)
            and start >= now
            and not any(_overlaps((start, end), b) for b in busy_now)
            and (it.deadline_at is None or it.deadline_kind == "soft" or end <= it.deadline_at)
            and _temporal_allows(it, start, end, tz)
        )
        if ok:
            kept[it.id] = (it, start, end)
        else:
            to_place.append(it)
    for _k_it, _s_k, e_k in kept.values():
        end_by_id[_k_it.id] = e_k

    # ── 4. Place everything else ─────────────────────────────────────────────
    placed: Dict[str, Placement] = {}
    unplaced_ids: Dict[str, Unplaced] = {}

    def busy_lists() -> Tuple[List[Tuple[datetime, datetime]], List[Tuple[datetime, datetime]]]:
        hard = list(base_hard)
        soft = list(base_hard)
        for it_k, s_k, e_k in kept.values():
            hard.append((s_k, e_k))
            soft.append((s_k, e_k + timedelta(minutes=_buf(it_k, extra_buffer_minutes))))
        for p in placed.values():
            it_p = items[index_of[p.item_id]]
            hard.append((p.start, p.end))
            soft.append((p.start, p.end + timedelta(minutes=_buf(it_p, extra_buffer_minutes))))
        return hard, soft

    def temporal_for(it: PlanItem) -> Optional[PlanTemporal]:
        t = it.temporal
        tgt = t.target_date if t else None
        if tgt is None:
            if it.planned_date is not None and it.planned_date >= today:
                tgt = it.planned_date
            elif mode == "replan" and scope_date is not None:
                tgt = scope_date
        earliest = t.earliest_start if t else None
        for dep in it.depends_on:
            d_end = end_by_id.get(dep)
            if d_end is not None and (earliest is None or earliest < d_end):
                earliest = d_end
        if tgt is None and earliest is not None and earliest.astimezone(tz).date() > today:
            tgt = earliest.astimezone(tz).date()
        if t is None and tgt is None and earliest is None:
            return None
        base = t or PlanTemporal()
        return replace(base, target_date=tgt, earliest_start=earliest)

    soft_exceeded: set = set()

    def try_place(it: PlanItem):
        hard, soft = busy_lists()
        temporal = temporal_for(it)
        passes = (False, True) if (it.deadline_at is not None and it.deadline_kind == "soft") else (False,)
        for ignore_deadline in passes:
            view = _View(it, temporal, ignore_deadline=ignore_deadline)
            res, _ = _ENGINE.evaluate_best_slot_with_reason(view, soft, profile, now, tz)
            if res is None and not (extra_buffer_minutes > 0 and it.priority == "low"):
                # soft buffers are relaxed before declaring "no capacity", except for low-priority work on a day
                # the user asked to keep spacious: that is the first thing to give way, not the breaks
                res, _ = _ENGINE.evaluate_best_slot_with_reason(view, hard, profile, now, tz)
            if res is not None:
                # A soft deadline is exceeded only when no slot before it exists.
                if ignore_deadline and res.slot.end_time > it.deadline_at:
                    soft_exceeded.add(it.id)
                else:
                    soft_exceeded.discard(it.id)
                return res
        return None

    def to_placement(it: PlanItem, res) -> Placement:
        prev_start = it.origin_start or _slot_of(it)[0]
        secondary = tuple(res.secondary_reasons) + (("soft_deadline_exceeded",) if it.id in soft_exceeded else ())
        return Placement(
            item_id=it.id, start=res.slot.start_time, end=res.slot.end_time,
            moved=(prev_start is not None and prev_start != res.slot.start_time),
            previous_start=prev_start, primary_reason=res.primary_reason,
            secondary_reasons=secondary, explanation=res.explanation,
            day_offset=res.slot.day_offset,
        )

    def classify(it: PlanItem) -> Tuple[str, str]:
        t = it.temporal  # only bounds the USER stated; scope/dependency bounds are not user limits
        if it.deadline_at is not None and it.deadline_kind != "soft":
            return "deadline_infeasible", f"'{it.title}' cannot be finished before its deadline in the time that is left."
        user_bound = t is not None and (t.target_date or t.latest_end or t.earliest_start or t.relative_before or t.relative_after)
        if user_bound or (it.planned_date is not None and it.planned_date >= today):
            return "bound_infeasible", _bound_message(it, t, today, tz)
        return "no_capacity", f"There is no room left for '{it.title}' in the remaining time."

    pending: List[PlanItem] = list(to_place)
    safety = 0
    while pending:
        safety += 1
        if safety > 10 * (len(items) + 5):
            raise PlanInvariantError("planner did not converge")
        pending_ids = {p.id for p in pending}
        ready = [p for p in pending if not any(d in pending_ids and d != p.id for d in p.depends_on)]
        pool = ready or pending  # a dependency cycle degrades to plain ordering
        it = min(pool, key=lambda x: order_key(x, index_of[x.id]))
        pending.remove(it)

        blocked_by = [d for d in it.depends_on if d in unplaced_ids]
        if blocked_by:
            names = ", ".join("'" + items[index_of[d]].title + "'" for d in blocked_by if d in index_of)
            unplaced_ids[it.id] = Unplaced(
                it.id, "dependency_unschedulable",
                f"'{it.title}' has to wait for {names}, which could not be scheduled.",
            )
            continue

        res = try_place(it)
        # Displacement (C11): an item with no room may take the slot of a strictly lower-urgency kept item.
        evicted: List[Tuple[PlanItem, datetime, datetime]] = []
        while res is None and kept:
            my_key = _ENGINE.urgency_sort_key(_View(it, None), now, tz)
            victims = [
                (k_it, s_k) for (k_it, s_k, _e) in kept.values()
                if _ENGINE.urgency_sort_key(_View(k_it, None), now, tz) > my_key
            ]
            if not victims:
                break
            victim = max(victims, key=lambda v: (_ENGINE.urgency_sort_key(_View(v[0], None), now, tz), v[1]))[0]
            evicted.append(kept.pop(victim.id))
            pending.append(victim)
            res = try_place(it)
        if res is None and evicted:
            # Displacement did not make room (e.g. the deadline already passed): nobody else moves.
            for k_it, s_k, e_k in evicted:
                kept[k_it.id] = (k_it, s_k, e_k)
                pending.remove(k_it)
        if res is None:
            reason, msg = classify(it)
            unplaced_ids[it.id] = Unplaced(it.id, reason, msg)
        else:
            placed[it.id] = to_placement(it, res)
            end_by_id[it.id] = placed[it.id].end

    # kept items become placements (unchanged slot)
    for it_k, s_k, e_k in kept.values():
        prev_k = it_k.origin_start or s_k
        placed[it_k.id] = Placement(
            item_id=it_k.id, start=s_k, end=e_k, moved=(prev_k != s_k), previous_start=prev_k,
            primary_reason="kept_in_place", secondary_reasons=(), explanation=("Kept at its current time." if prev_k == s_k else "Shifted to the new time."), day_offset=max(0, (s_k.astimezone(tz).date() - today).days),
        )
        end_by_id[it_k.id] = e_k

    # ── 5. Roll-over suggestions (never applied here) ────────────────────────
    final_unscheduled: List[Unplaced] = []
    _, soft_final = busy_lists()
    for uid in sorted(unplaced_ids, key=lambda x: index_of[x]):
        u = unplaced_ids[uid]
        suggestion = None
        it = items[index_of[uid]]
        t_it = temporal_for(it)
        if u.reason == "no_capacity" and (it.temporal is None or it.temporal.target_date is None) and it.planned_date is None:
            base_t = it.temporal or PlanTemporal()
            nxt = (scope_date or today) + timedelta(days=1)
            view = _View(it, replace(base_t, target_date=nxt, earliest_start=t_it.earliest_start if t_it else None))
            res, _ = _ENGINE.evaluate_best_slot_with_reason(view, soft_final, profile, now, tz)
            if res is not None:
                suggestion = to_placement(it, res)
                soft_final.append((suggestion.start, suggestion.end + timedelta(minutes=_buf(it, extra_buffer_minutes))))
        final_unscheduled.append(replace(u, suggestion=suggestion))
    unscheduled.extend(final_unscheduled)

    result = PlanResult(
        placements=tuple(sorted(placed.values(), key=lambda p: (p.start, p.item_id))),
        immutable=tuple(sorted(immutable, key=lambda i: i.item_id)),
        unscheduled=tuple(sorted(unscheduled, key=lambda u: u.item_id)),
        conflicts=tuple(conflicts),
        timezone_used=tz_name or getattr(tz, "key", "UTC"),
        mode=mode,
    )
    violations = check_invariants(items, result, now_local=now, tz=tz, extra_busy=tuple(base_hard[: len(extra_busy)]))
    if violations:
        raise PlanInvariantError("; ".join(violations))
    return result


def _buf(it: PlanItem, extra: int) -> int:
    return SchedulingEngine.buffer_minutes_for(it.task_type) + extra


def _temporal_allows(it: PlanItem, start: datetime, end: datetime, tz: ZoneInfo) -> bool:
    t = it.temporal
    if t is None:
        return True
    if t.target_date is not None and start.astimezone(tz).date() != t.target_date:
        return False
    if t.earliest_start is not None and start < t.earliest_start:
        return False
    if t.latest_end is not None and end > t.latest_end:
        return False
    return True


def check_invariants(
    items: Sequence[PlanItem],
    result: PlanResult,
    *,
    now_local: datetime,
    tz: ZoneInfo,
    extra_busy: Sequence[Tuple[datetime, datetime]] = (),
) -> List[str]:
    """Return a list of contract violations (empty = valid). Pure; used by plan() and by tests."""
    problems: List[str] = []
    by_id = {i.id: i for i in items}

    # C9 conservation: every input id is in exactly one bucket
    all_bucket_entries = (
        [p.item_id for p in result.placements]
        + [i.item_id for i in result.immutable]
        + [u.item_id for u in result.unscheduled]
    )
    if len(all_bucket_entries) != len(set(all_bucket_entries)):
        problems.append("an item appears in more than one bucket")
    missing = set(by_id) - set(all_bucket_entries)
    if missing:
        problems.append(f"items lost: {sorted(missing)}")
    extra = set(all_bucket_entries) - set(by_id)
    if extra:
        problems.append(f"unknown items in result: {sorted(extra)}")

    # C4 / C5 / C6 / C7 for every placement
    occupied: List[Tuple[str, datetime, datetime]] = [
        (f"extra{k}", s, e) for k, (s, e) in enumerate(extra_busy)
    ]
    for im in result.immutable:
        if im.start is not None and im.end is not None and im.kind != K_INACTIVE:
            occupied.append((im.item_id, im.start, im.end))
    for p in result.placements:
        it = by_id.get(p.item_id)
        if p.end <= p.start:
            problems.append(f"{p.item_id}: non-positive duration")
        if p.start < now_local - PAST_TOLERANCE:
            problems.append(f"{p.item_id}: placed in the past")
        if it is not None:
            if it.deadline_at is not None and it.deadline_kind != "soft" and p.end > it.deadline_at:
                problems.append(f"{p.item_id}: ends after deadline")
            t = it.temporal
            if t is not None and t.latest_end is not None and p.end > t.latest_end:
                problems.append(f"{p.item_id}: ends after latest_end")
            if t is not None and t.target_date is not None and p.start.astimezone(tz).date() != t.target_date:
                problems.append(f"{p.item_id}: wrong target date")
        for oid, s, e in occupied:
            if oid != p.item_id and _overlaps((p.start, p.end), (s, e)):
                problems.append(f"{p.item_id}: overlaps {oid}")
        occupied.append((p.item_id, p.start, p.end))
    return problems


@dataclass(frozen=True)
class Violation:
    code: str          # start_in_past | overlap | after_deadline
    item_id: str
    message: str


def busy_interval(it: PlanItem, now_local: datetime) -> Optional[Tuple[datetime, datetime]]:
    """The time an item occupies right now (D7 for in-progress), or None when it occupies none."""
    start, end = _slot_of(it)
    if it.status == "completed":
        s = it.started_at or start
        e = it.completed_at or end
        return (s, e) if s is not None and e is not None and e > s else None
    if it.status == "in_progress":
        s = it.started_at or start or now_local
        return (s, max(s + timedelta(minutes=it.estimated_minutes), now_local))
    if it.status in ("todo", "postponed") and start is not None:
        return (start, end)
    return None


def validate_placements(
    changed: Sequence[PlanItem],
    others: Sequence[PlanItem],
    *,
    now_local: datetime,
) -> List[Violation]:
    """Re-validate a proposed set of slot changes against the rest of the schedule.

    ``changed``: items whose slot is being written (new or moved). ``others``: every other open or
    completed item that stays as it is. Two user-locked items may overlap (the user's choice).
    Pure; used by Replan apply so the server never trusts a client-computed diff.
    """
    now = _aware(now_local, "now_local")
    out: List[Violation] = []
    occupied: List[Tuple[str, PlanItem, Tuple[datetime, datetime]]] = []
    for o in others:
        iv = busy_interval(o, now)
        if iv is not None:
            occupied.append((o.id, o, iv))
    for c in changed:
        start, end = _slot_of(c)
        if start is None:
            continue
        if start < now - PAST_TOLERANCE:
            out.append(Violation("start_in_past", c.id, f"'{c.title}' would start in the past."))
        if c.deadline_at is not None and c.deadline_kind != "soft" and end > c.deadline_at:
            out.append(Violation("after_deadline", c.id, f"'{c.title}' would end after its deadline."))
        for _oid, o, iv in occupied:
            if _overlaps((start, end), iv) and not (c.time_locked and o.time_locked):
                out.append(Violation("overlap", c.id, f"'{c.title}' would overlap '{o.title}'."))
        occupied.append((c.id, c, (start, end)))
    return out
