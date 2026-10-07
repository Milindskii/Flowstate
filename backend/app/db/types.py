from datetime import timezone

from sqlalchemy import DateTime
from sqlalchemy.types import TypeDecorator


class UTCDateTime(TypeDecorator):
    """Timezone-aware instants that behave identically on SQLite and PostgreSQL.

    SQLite stores aware datetimes as naive wall-clock text, dropping the offset
    without converting it. This type converts to UTC on the way in and always
    returns aware UTC on the way out. A naive value is interpreted as UTC (the
    only convention existing rows can have, since clients send UTC).
    """

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
