from typing import Optional, List, Dict, Any
from datetime import datetime, date
from pydantic import BaseModel, Field
from .task import TaskCreate, TaskResponse
from .today import WorkloadSummary

class DayScheduleItem(BaseModel):
    id: str
    task_id: Optional[str] = None
    title: str
    start_time: datetime
    end_time: datetime
    time: str              # e.g. "6:00"
    period: str            # e.g. "PM"
    duration_minutes: int
    type: str              # e.g. "deep_work", "physical", "meeting"
    tag_text: str          # e.g. "DEEP WORK", "FIXED", "MEETING"
    is_fixed: bool = False          # == time_locked: the user (or an import) fixed this time
    time_locked: bool = False
    is_commitment: bool = False     # a fixed block (e.g. going out): shown, never work
    is_completed: bool = False
    is_active: bool = False
    is_conflict: bool = False
    is_suggested: bool = False      # placement proposed for a task with no stored slot (not persisted)
    is_missed: bool = False         # stored slot has passed and the task was not started
    state: str = "scheduled"        # derived: scheduled|active|missed|failed|completed|skipped|deferred (see services/task_state.py)
    primary_reason: Optional[str] = None
    explanation: Optional[str] = None
    expected_updated_at: Optional[datetime] = None  # optimistic-concurrency token for apply
    is_skipped: bool = False         # skipped/deferred off this day (history node, see DayScheduleResponse.deviations)
    deviation: Optional[str] = None  # "skipped" | "deferred" | "missed": history node (DayScheduleResponse.deviations only)
    # Where this task's stop sits on the day path: the slot it was PLANNED for on this day (a completed task keeps its
    # planned slot, not its session time; a history node its original slot). The Calendar orders stops by it.
    anchor_start: Optional[datetime] = None

class DayCompleteStatus(BaseModel):
    eligible: bool = False   # every task of the day is done (fixed commitments do not count)
    claimed: bool = False    # the day's trophy XP was already collected
    xp: int = 0


class DayScheduleResponse(BaseModel):
    date: str                          # YYYY-MM-DD
    is_today: bool
    is_past: bool
    timeline: List[DayScheduleItem]
    fixed_commitments: List[DayScheduleItem]
    completed_tasks: List[DayScheduleItem]
    remaining_tasks: List[DayScheduleItem]
    unscheduled_tasks: List[DayScheduleItem] = Field(default_factory=list)
    # Tasks skipped/deferred off this day, at their original slot. Display-only history: not in
    # timeline, not busy time, not counted as planned work. The task itself now lives on a later day.
    deviations: List[DayScheduleItem] = Field(default_factory=list)
    conflicts: List[str]
    workload: WorkloadSummary
    focus_window: Optional[str] = None
    readiness_score: Optional[int] = None
    total_planned_minutes: int = 0
    remaining_capacity_minutes: int = 0
    timezone_used: Optional[str] = None
    day_complete: DayCompleteStatus = Field(default_factory=DayCompleteStatus)

# ── REPLAN SCHEMAS ────────────────────────────────────────────────────────────

class QuickAddTask(BaseModel):
    """A structured new task (e.g. the "Urgent work arrived" sheet): used as typed, never parsed from prose."""
    title: str = Field(min_length=1, max_length=255)
    duration_minutes: int = Field(default=45, ge=5, le=480)
    start_time: Optional[str] = Field(default=None, pattern=r"^\d{2}:\d{2}$")  # "HH:MM" local, optional


class ReplanRequest(BaseModel):
    selected_date: str                 # "YYYY-MM-DD"
    user_message: str = ""             # natural language instruction (may be empty when quick_add is given)
    quick_add: Optional[QuickAddTask] = None
    current_local_time: Optional[datetime] = None
    timezone: Optional[str] = None     # IANA name; abbreviations fall back to the stored preference

class ReplanOperation(BaseModel):
    op: str                            # add_task | move_task_date | move_task_time (target_time) | change_duration (delay_minutes = extra) | shift_task_preference | delay_remaining_schedule | cancel_task | change_duration | add_constraint | remove_constraint | move_later | prioritize | protect_block | unparsed
    task_id: Optional[str] = None
    task_query: Optional[str] = None   # keyword/title for task lookup
    title: Optional[str] = None
    duration_minutes: Optional[int] = None
    priority: Optional[str] = None
    task_type: Optional[str] = None
    target_date: Optional[str] = None  # "YYYY-MM-DD" or "tomorrow", "friday"
    target_time: Optional[str] = None  # "HH:MM" e.g. "16:30"
    preferred_window: Optional[str] = None # "morning" | "afternoon" | "evening" | "night"
    delay_minutes: Optional[int] = None
    constraint_type: Optional[str] = None # "earliest_start" | "latest_end" | "relative_after" | "relative_before"
    constraint_value: Optional[str] = None
    block_start: Optional[str] = None  # protect_block: "HH:MM" local, a window the planner must keep clear
    block_end: Optional[str] = None
    intent: Optional[str] = None       # move_task_date: "skipped" | "deferred" | "rescheduled"

class TaskDiffItem(BaseModel):
    task_id: str
    title: str
    change_type: str                   # "moved" | "new" | "unchanged" | "cancelled" | "unscheduled" | "protected"
    old_time: Optional[str] = None     # e.g. "5:00 PM"
    new_time: Optional[str] = None     # e.g. "7:30 PM"
    old_date: Optional[str] = None
    new_date: Optional[str] = None     # display label ("Tomorrow", "Friday")
    new_date_iso: Optional[str] = None # YYYY-MM-DD
    old_start: Optional[datetime] = None
    new_start: Optional[datetime] = None   # authoritative instants (aware); clients must not rebuild from strings
    new_end: Optional[datetime] = None
    old_end: Optional[datetime] = None
    old_time_range: Optional[str] = None   # "6:30 PM \u2013 8:30 PM": the full interval, never just a start
    new_time_range: Optional[str] = None
    is_fixed: bool = False
    time_locked: bool = False
    is_commitment: bool = False
    task_type: Optional[str] = None
    priority: Optional[str] = None
    duration_minutes: int = 45
    reason: Optional[str] = None
    expected_updated_at: Optional[datetime] = None
    suggestion_start: Optional[datetime] = None   # roll-over proposal for unscheduled items
    suggestion_end: Optional[datetime] = None
    apply_index: Optional[int] = None   # new tasks: index into apply_request.new_tasks (so the client can edit it)
    needs_title: bool = False           # new task still has the generic fallback name; the user must name it

class TaskScheduleUpdate(BaseModel):
    """One slot change. An explicit JSON null for scheduled_start/end clears the slot."""
    task_id: str
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    deadline_at: Optional[datetime] = None
    planned_date: Optional[date] = None
    expected_updated_at: Optional[datetime] = None  # stale-plan guard
    user_override: bool = False                     # permits changing a time_locked task / commitment (explicit user op only)
    estimated_minutes: Optional[int] = Field(default=None, ge=5, le=480)  # "takes longer": new planned duration

class ApplyReplanRequest(BaseModel):
    plan_id: str
    selected_date: str
    task_updates: List[TaskScheduleUpdate] = Field(default_factory=list)
    new_tasks: List[TaskCreate] = Field(default_factory=list)
    cancelled_task_ids: List[str] = Field(default_factory=list)
    # task_id -> why it changed ("skipped" | "deferred" | "rescheduled" | "delayed" | "preference_shift").
    # Server-authored; apply ignores unknown values and ids outside this request (they count as collateral).
    intents: Dict[str, str] = Field(default_factory=dict)
    timezone: Optional[str] = None
    current_local_time: Optional[datetime] = None

class ReplanIssue(BaseModel):
    """A typed note about the plan, so the app can tell a true clash from a capacity miss or a protected block.

    kind: conflict | capacity | protected | ambiguous | not_found | unparsed | past | note
    """
    kind: str
    message: str


class ReplanClarificationOption(BaseModel):
    """One contextual choice under a clarification. `message` is re-sent as a Replan request when tapped;
    `prefill` is put in the composer for the user to finish (e.g. "move going out to ")."""
    label: str
    message: Optional[str] = None
    prefill: Optional[str] = None


class ReplanClarification(BaseModel):
    """Noya recognised the task/intent but needs one more detail (or a choice). Nothing is proposed yet."""
    question: str
    options: List[ReplanClarificationOption] = Field(default_factory=list)
    task_id: Optional[str] = None
    task_title: Optional[str] = None


class PlanDiff(BaseModel):
    plan_id: str
    selected_date: str
    created_at: datetime
    before_schedule: List[DayScheduleItem]
    after_schedule: List[DayScheduleItem]
    moved_tasks: List[TaskDiffItem] = Field(default_factory=list)
    newly_scheduled_tasks: List[TaskDiffItem] = Field(default_factory=list)
    unchanged_tasks: List[TaskDiffItem] = Field(default_factory=list)
    cancelled_tasks: List[TaskDiffItem] = Field(default_factory=list)
    unscheduled_tasks: List[TaskDiffItem] = Field(default_factory=list)
    skipped_immutable: List[TaskDiffItem] = Field(default_factory=list)  # completed / in-progress, protected
    conflicts: List[str] = Field(default_factory=list)
    issues: List[ReplanIssue] = Field(default_factory=list)  # same notes as `conflicts`, typed
    explanation: str
    timezone_used: Optional[str] = None
    apply_request: Optional[ApplyReplanRequest] = None  # server-authored; post back verbatim to apply
    clarification: Optional[ReplanClarification] = None  # set instead of a proposal when a detail is missing

class ReplanResponse(BaseModel):
    success: bool
    plan_diff: PlanDiff
    user_intent_summary: str

class ApplyReplanResponse(BaseModel):
    success: bool
    updated_count: int
    created_count: int
    cancelled_count: int
    message: str
    updated: List[str] = Field(default_factory=list)
    created: List[str] = Field(default_factory=list)
    cancelled: List[str] = Field(default_factory=list)
    skipped: List[Dict[str, Any]] = Field(default_factory=list)   # [{task_id, reason}]
    persisted_tasks: List[TaskResponse] = Field(default_factory=list)
    idempotent_replay: bool = False
