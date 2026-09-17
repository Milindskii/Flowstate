from typing import Optional
from sqlalchemy.orm import Session
from ..models.user import User
from ..models.user_preferences import UserPreferences
from ..repositories.user_repository import UserRepository
from ..schemas.user import UserPreferencesUpdate

class UserService:
    def __init__(self, user_repo: UserRepository = UserRepository()):
        self.user_repo = user_repo

    def get_user_profile(self, db: Session, user_id: str) -> Optional[User]:
        return self.user_repo.get_by_id(db, user_id)

    def update_preferences(self, db: Session, user_id: str, update: UserPreferencesUpdate) -> UserPreferences:
        data = update.model_dump(exclude_unset=True)
        return self.user_repo.update_preferences(db, user_id, data)
