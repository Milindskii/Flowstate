from typing import Optional
from sqlalchemy.orm import Session
from ..models.user import User
from ..models.user_preferences import UserPreferences

class UserRepository:
    @staticmethod
    def get_by_id(db: Session, user_id: str) -> Optional[User]:
        return db.query(User).filter(User.id == user_id).first()

    @staticmethod
    def get_by_email(db: Session, email: str) -> Optional[User]:
        return db.query(User).filter(User.email == email).first()

    @staticmethod
    def update_preferences(db: Session, user_id: str, prefs_dict: dict) -> UserPreferences:
        prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
        if not prefs:
            prefs = UserPreferences(user_id=user_id, **prefs_dict)
            db.add(prefs)
        else:
            for key, val in prefs_dict.items():
                if val is not None and hasattr(prefs, key):
                    setattr(prefs, key, val)
        db.commit()
        db.refresh(prefs)
        return prefs
