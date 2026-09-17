from typing import List
from sqlalchemy.orm import Session
from ..models.task_performance import TaskPerformance

class TaskPerformanceRepository:
    @staticmethod
    def create(db: Session, performance: TaskPerformance) -> TaskPerformance:
        db.add(performance)
        db.commit()
        db.refresh(performance)
        return performance

    @staticmethod
    def list_by_user(db: Session, user_id: str, limit: int = 100) -> List[TaskPerformance]:
        return db.query(TaskPerformance).filter(
            TaskPerformance.user_id == user_id
        ).order_by(TaskPerformance.created_at.desc()).limit(limit).all()
