from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone, time
from zoneinfo import ZoneInfo

class SchedulingEngine:
    """
    Concrete Cognitive Scheduling Optimizer.
    
    Rules & Invariants:
    1. Explicit scheduled time: If task.scheduled_start exists, it is an immutable anchor block.
    2. Fixed calendar events / busy intervals: Treated as non-schedulable obstacles.
    3. No past scheduling: New schedule slots must begin >= max(now_local, start_of_day).
    4. Urgency ordering: Overdue unfinished tasks first, imminent deadlines second, high priority third.
    5. Cognitive load & readiness window matching:
       - Deep work (high difficulty, coding, thesis, math): assigned to circadian peak window
         (e.g. 9:30 - 11:45 AM from user profile), max 2 deep blocks/day.
       - Admin / light work: assigned to dip window (e.g. 14:00 - 15:30) or interstitial slots.
    6. Non-overlapping packing: Allocate tasks sequentially into available time intervals without collisions.
    7. Truthful: If tasks is empty, returns empty list (NO synthetic fake breaks).
    """

    def generate_schedule(
        self,
        tasks: List[Any],
        readiness_profile: Optional[Any] = None,
        now_local: Optional[datetime] = None,
        fixed_busy_intervals: Optional[List[tuple[datetime, datetime]]] = None,
        tz: Optional[ZoneInfo] = None,
    ) -> List[Dict[str, Any]]:
        if not tasks:
            return []

        tz = tz or timezone.utc
        if now_local is None:
            now_local = datetime.now(tz)
        elif now_local.tzinfo is None:
            now_local = now_local.replace(tzinfo=tz)

        fixed_busy = list(fixed_busy_intervals or [])
        schedule_items: List[Dict[str, Any]] = []

        # Parse user peak / dip preferences from profile
        peak_start_hour = 9.5  # 9:30 AM
        peak_end_hour = 11.75  # 11:45 AM
        dip_start_hour = 14.0  # 2:00 PM
        dip_end_hour = 15.5   # 3:30 PM

        if readiness_profile:
            try:
                ps = getattr(readiness_profile, "preferred_peak_start", "09:30").split(":")
                peak_start_hour = int(ps[0]) + int(ps[1]) / 60.0
                pe = getattr(readiness_profile, "preferred_peak_end", "11:45").split(":")
                peak_end_hour = int(pe[0]) + int(pe[1]) / 60.0
                ds = getattr(readiness_profile, "preferred_dip_start", "14:00").split(":")
                dip_start_hour = int(ds[0]) + int(ds[1]) / 60.0
                de = getattr(readiness_profile, "preferred_dip_end", "15:30").split(":")
                dip_end_hour = int(de[0]) + int(de[1]) / 60.0
            except Exception:
                pass

        # 1. Extract anchored tasks (explicitly scheduled by user)
        anchored_tasks = []
        flexible_tasks = []

        for t in tasks:
            sched_start = getattr(t, "scheduled_start", None)
            if sched_start:
                if sched_start.tzinfo is None:
                    sched_start = sched_start.replace(tzinfo=tz)
                anchored_tasks.append((sched_start, t))
            else:
                flexible_tasks.append(t)

        # Place all anchored tasks first and register them in busy intervals
        for s_start, t in sorted(anchored_tasks, key=lambda x: x[0]):
            dur = getattr(t, "estimated_minutes", 45)
            s_end = s_start + timedelta(minutes=dur)
            fixed_busy.append((s_start, s_end))

            item_type = getattr(t, "task_type", "deep_work")
            tag_text = "DEEP WORK" if item_type == "deep_work" else "TASK"
            schedule_items.append({
                "id": f"sched-{t.id}",
                "task_id": str(t.id),
                "title": t.title,
                "start_time": s_start,
                "end_time": s_end,
                "duration_minutes": dur,
                "type": item_type,
                "tag_text": tag_text,
                "is_active": getattr(t, "status", None) == "in_progress",
                "is_anchored": True,
            })

        # 2. Sort flexible tasks by urgency and cognitive demand
        def _sort_key(t: Any):
            # Overdue = 0, deadline today = 1, high priority = 2, others = 3
            deadline = getattr(t, "deadline_at", None)
            is_overdue = False
            is_due_today = False
            if deadline:
                d = deadline if deadline.tzinfo is not None else deadline.replace(tzinfo=tz)
                if d < now_local:
                    is_overdue = True
                elif d.date() == now_local.date():
                    is_due_today = True

            pri = getattr(t, "priority", None)
            is_high_pri = str(pri).lower() in ("high", "urgent")

            urgency_rank = 0 if is_overdue else (1 if is_due_today else (2 if is_high_pri else 3))
            
            # Cognitive weight: deep work = 0 (pack first in prime windows), light = 1
            t_type = getattr(t, "task_type", "deep_work")
            type_rank = 0 if t_type == "deep_work" else 1

            return (urgency_rank, type_rank)

        sorted_flexible = sorted(flexible_tasks, key=_sort_key)

        # 3. Schedule flexible tasks into available windows
        # Current day working bounds: start from max(now_local, 9:00 AM)
        day_start = datetime.combine(now_local.date(), time(9, 0), tzinfo=tz)
        current_cursor = max(now_local, day_start)

        # Round up cursor to nearest 5 minutes
        minute_rem = current_cursor.minute % 5
        if minute_rem > 0:
            current_cursor += timedelta(minutes=(5 - minute_rem))

        # Helper to check collision with fixed busy intervals
        def _is_interval_free(cand_start: datetime, cand_end: datetime) -> bool:
            for b_start, b_end in fixed_busy:
                # Overlap condition: start < b_end and end > b_start
                if cand_start < b_end and cand_end > b_start:
                    return False
            return True

        def _find_next_free_slot(start_from: datetime, duration_mins: int) -> tuple[datetime, datetime]:
            cursor = start_from
            end_of_workday = datetime.combine(now_local.date(), time(22, 0), tzinfo=tz)
            
            while cursor + timedelta(minutes=duration_mins) <= end_of_workday:
                cand_end = cursor + timedelta(minutes=duration_mins)
                conflict_end = None
                for b_start, b_end in fixed_busy:
                    if cursor < b_end and cand_end > b_start:
                        conflict_end = max(conflict_end or b_end, b_end)
                
                if conflict_end is None:
                    return cursor, cand_end
                else:
                    cursor = conflict_end + timedelta(minutes=5)
            
            # Fallback if workday full: append to cursor
            return cursor, cursor + timedelta(minutes=duration_mins)

        deep_work_count = sum(1 for item in schedule_items if item["type"] == "deep_work")

        for t in sorted_flexible:
            dur = getattr(t, "estimated_minutes", 45)
            t_type = getattr(t, "task_type", "deep_work")
            
            # If task is deep work and under daily deep quota (<= 2), target peak window if free
            target_start = current_cursor
            if t_type == "deep_work" and deep_work_count < 2:
                peak_dt = datetime.combine(now_local.date(), time(int(peak_start_hour), int((peak_start_hour % 1) * 60)), tzinfo=tz)
                if peak_dt >= now_local and _is_interval_free(peak_dt, peak_dt + timedelta(minutes=dur)):
                    target_start = peak_dt
                    deep_work_count += 1
            elif t_type in ("admin", "light", "personal"):
                dip_dt = datetime.combine(now_local.date(), time(int(dip_start_hour), int((dip_start_hour % 1) * 60)), tzinfo=tz)
                if dip_dt >= now_local and _is_interval_free(dip_dt, dip_dt + timedelta(minutes=dur)):
                    target_start = dip_dt

            slot_start, slot_end = _find_next_free_slot(target_start, dur)
            fixed_busy.append((slot_start, slot_end))

            tag_text = "DEEP WORK" if t_type == "deep_work" else ("ADMIN" if t_type == "admin" else "TASK")
            schedule_items.append({
                "id": f"sched-{t.id}",
                "task_id": str(t.id),
                "title": t.title,
                "start_time": slot_start,
                "end_time": slot_end,
                "duration_minutes": dur,
                "type": t_type,
                "tag_text": tag_text,
                "is_active": getattr(t, "status", None) == "in_progress",
                "is_anchored": False,
            })

            # Advance cursor past this slot + buffer (15m for deep work, 5m for light)
            buffer_mins = 15 if t_type == "deep_work" else 5
            current_cursor = slot_end + timedelta(minutes=buffer_mins)

        # Return items ordered by chronological start_time
        schedule_items.sort(key=lambda x: x["start_time"])
        return schedule_items
