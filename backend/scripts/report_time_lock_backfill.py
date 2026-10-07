"""
Read-only report for the time_locked backfill (spec section 11.3).

Run BEFORE `alembic upgrade`. Issues SELECT statements only; never UPDATE/ALTER.

  python scripts/report_time_lock_backfill.py [--database-url URL] [--csv PATH]

A. Would be locked   - exactly the rows the migration's UPDATE will change.
B. Review list       - open rows with a start time that merely LOOK fixed
                       (meeting type / appointment keywords). NEVER auto-locked.
C. Totals            - by (source, status), with/without scheduled_start.
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text  # noqa: E402

from app.db.backfill import LOCK_BACKFILL_WHERE, OPEN_STATUSES, REVIEW_KEYWORDS  # noqa: E402

COLS = "id, user_id, title, source, task_type, status, scheduled_start"


def _query_a(conn):
    return conn.execute(text(f"SELECT {COLS} FROM tasks WHERE {LOCK_BACKFILL_WHERE} ORDER BY scheduled_start")).fetchall()


def _query_b(conn):
    kw = " OR ".join(f"lower(title) LIKE '%{k}%'" for k in REVIEW_KEYWORDS)
    open_list = ", ".join(f"'{s}'" for s in OPEN_STATUSES)
    sql = (
        f"SELECT {COLS} FROM tasks WHERE scheduled_start IS NOT NULL AND status IN ({open_list}) "
        f"AND NOT ({LOCK_BACKFILL_WHERE}) AND (task_type = 'meeting' OR {kw}) ORDER BY scheduled_start"
    )
    return conn.execute(text(sql)).fetchall()


def _query_c(conn):
    return conn.execute(text(
        "SELECT source, status, count(*), count(scheduled_start) FROM tasks GROUP BY source, status ORDER BY source, status"
    )).fetchall()


def _print_rows(title, rows, limit=200):
    print(f"\n{title} ({len(rows)})")
    print("-" * 100)
    for r in rows[:limit]:
        print(" | ".join("" if v is None else str(v) for v in r))
    if len(rows) > limit:
        print(f"... {len(rows) - limit} more (use --csv for the full list)")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--database-url", default=None)
    ap.add_argument("--csv", default=None, help="write sections A and B to this CSV file")
    args = ap.parse_args(argv)

    url = args.database_url
    if not url:
        from app.core.config import settings

        url = settings.DATABASE_URL
    engine = create_engine(url)
    with engine.connect() as conn:
        a, b, c = _query_a(conn), _query_b(conn), _query_c(conn)

    print("Predicate:", LOCK_BACKFILL_WHERE)
    _print_rows("A. WOULD BE LOCKED (these exact rows change)", a)
    _print_rows("B. REVIEW LIST - NOT locked, informational only", b)
    print("\nC. TOTALS by (source, status): rows / rows with scheduled_start")
    for src, st, n, ns in c:
        print(f"  {src:10} {st:12} {n:6} {ns:6}")

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["section"] + COLS.replace(" ", "").split(","))
            for r in a:
                w.writerow(["A_would_lock", *r])
            for r in b:
                w.writerow(["B_review_not_locked", *r])
        print(f"\nWrote {args.csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
