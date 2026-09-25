from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func

from ...db.session import get_db
from ...core.security import require_admin
from ...models.user import User
from ...models.task import Task
from ...models.readiness_observation import ReadinessObservation
from ...models.readiness_evaluation import ReadinessEvaluation

router = APIRouter(prefix="/admin", tags=["Admin Operations"])

@router.get("/stats")
def get_system_stats(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin-only system overview metrics."""
    total_users = db.query(func.count(User.id)).scalar() or 0
    total_tasks = db.query(func.count(Task.id)).scalar() or 0
    total_observations = db.query(func.count(ReadinessObservation.id)).scalar() or 0
    total_evaluations = db.query(func.count(ReadinessEvaluation.id)).scalar() or 0

    return {
        "status": "authorized",
        "total_users": total_users,
        "total_tasks": total_tasks,
        "total_observations": total_observations,
        "total_evaluations": total_evaluations,
    }
