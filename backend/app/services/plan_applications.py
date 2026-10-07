"""Idempotency store shared by Build My Day confirm and Replan apply (one place, spec sections 7 and 8.2).

A ``plan_applications`` row is written in the SAME transaction as the plan's changes, so a replayed
``plan_id`` can only ever find a plan that fully committed. Always scoped to ``user_id``.
"""
import json
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from ..models.plan_application import PlanApplication


def load_stored(db: Session, user_id: str, plan_id: str) -> Optional[Dict[str, Any]]:
    """The stored response of an already-applied plan (with ``idempotent_replay`` set), or None."""
    row = db.query(PlanApplication).filter(
        PlanApplication.user_id == user_id, PlanApplication.plan_id == plan_id).first()
    if row is None:
        return None
    data = json.loads(row.response_json)
    data["idempotent_replay"] = True
    return data


def stage(db: Session, user_id: str, plan_id: str, kind: str, response: Dict[str, Any]) -> None:
    """Stage the record in the caller's transaction (the caller commits)."""
    db.add(PlanApplication(user_id=user_id, plan_id=plan_id, kind=kind, response_json=json.dumps(response)))
