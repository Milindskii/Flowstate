"""Build My Day input-limit benchmark (live Gemini calls; costs a little quota; NOT part of CI).

Drives the real extraction path (ai_gateway.call_provider -> AIService.extract_structured_plan_with_gemini), so the
25 s request deadline, the 12 s per-call timeout, the model fallback and the repair call all behave as in production.

    cd backend && venv/Scripts/python scripts/bmd_limit_benchmark.py --dry-run            # corpus sizes only, no calls
    cd backend && venv/Scripts/python scripts/bmd_limit_benchmark.py --runs 10 --concurrency 1 6

Writes <out>.json (raw) and <out>.md (table + verdict). The limit is NOT decided here by hand: `verdict()` applies the
pass gate and the 70-75% headroom rule from the plan, and prints the result.
"""
from __future__ import annotations

import argparse
import json
import logging
import random
import re
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# ---- pass gate (from the plan) --------------------------------------------------------------------------------------
GATE_SUCCESS = 0.98
GATE_MALFORMED = 0.01
GATE_TIMEOUT = 0.01
GATE_P95_SECONDS = 15.0
HEADROOM = (0.70, 0.75)
DEFAULT_SIZES = [150, 250, 350, 450, 600, 800, 1000]
# Provider-side or harness-side outcomes say nothing about input size, so they are excluded from the rates (not counted
# as failures). A row needs at least MIN_CONCLUSIVE of its samples to be conclusive at all.
INCONCLUSIVE_CODES = {"provider_quota", "provider_unavailable", "provider_auth", "model_not_found", "AIBusy"}
MIN_CONCLUSIVE = 0.7

# ---- corpus ---------------------------------------------------------------------------------------------------------
# Messy, realistic fragments grouped by what they stress. Everything a "genuinely complicated day" contains:
# tasks with durations, deadlines, fixed commitments, travel, priorities, dependencies, energy, fallbacks, reasoning.
TASKS = [
    "I need to finish the Python lab report, probably two hours, it's due Friday at 5pm and my TA is strict about it.",
    "Study graph algorithms for about 90 minutes, the quiz is on Monday so this is high priority.",
    "Call the dentist to reschedule my cleaning, takes 10 minutes, whenever I have a gap.",
    "Write the introduction for the economics essay, 45 minutes, I do my best writing in the morning.",
    "Go to the gym for an hour, legs today, I skipped it twice this week so it matters.",
    "Reply to the internship emails, about 30 minutes, two of them are time sensitive.",
    "Do the laundry and fold everything, maybe 40 minutes, can happen any time in the evening.",
    "Grocery run for the week, 45 minutes, need eggs, rice, vegetables and coffee.",
    "Prepare slides for the Thursday group presentation, around 2 hours, needs deep focus.",
    "Review the pull request from Arjun, 30 minutes, he is blocked until I do.",
    "Revise organic chemistry chapter 4, 1 hour, flashcards first then practice problems.",
    "Book train tickets for the weekend trip home, 15 minutes, prices go up tonight.",
    "Clean my desk and reorganize notes, 25 minutes, low priority but it bothers me.",
    "Finish the budget spreadsheet for the club, 50 minutes, treasurer needs it by Wednesday noon.",
    "Practice guitar for 30 minutes, just for fun, only if I still have energy.",
    "Pay the electricity bill online, 5 minutes, deadline is tomorrow so don't forget.",
    "Read two chapters of the networking textbook, an hour and a half, the afternoon dip is bad for this.",
    "Meal prep lunches for three days, 1 hour, after groceries obviously.",
    "Update my resume with the new project and send it to the career center, 40 minutes.",
    "Debug the failing integration test in the backend repo, could take 2 hours, super annoying.",
]
FIXED = [
    "I have a lecture from 10:00 to 11:30 that I can't move.",
    "Team standup at 9:30 sharp, only 15 minutes.",
    "Lunch with my cousin at 1pm, I'll be gone about an hour and a half.",
    "Dinner at 8 with the family, that is non-negotiable.",
    "Doctor's appointment at 4:15, plan for 45 minutes plus waiting.",
    "Lab session from 2 to 4 in the engineering block.",
]
TRAVEL = [
    "The commute to campus is about 45 minutes each way and I leave at 8:30.",
    "It takes 25 minutes to get to the gym by bike, so count that in.",
    "Getting to the clinic is a 30 minute drive, I'd rather not rush that.",
    "I need to be home by 6:30 so the trip back from the library is 20 minutes earlier than it looks.",
]
DEPENDENCIES = [
    "The slides have to wait until I've finished the lab report because they reuse the numbers.",
    "Don't schedule meal prep before groceries, that makes no sense.",
    "Email the TA only after the report is done, not before.",
    "I can only do the practice problems after reviewing the notes first.",
]
ENERGY = [
    "I'm sharpest from about 8 to 12, so put the hard stuff there.",
    "After lunch I crash, keep that window for easy admin things.",
    "Evenings are fine for light work but not for anything that needs real thinking.",
    "Try to keep one hour completely free as a buffer, I always run over.",
]
FALLBACKS = [
    "If the day gets crowded, drop guitar and the desk cleanup first.",
    "If I run out of time the essay introduction can slide to tomorrow, but the report cannot.",
    "Worst case, laundry goes to the weekend.",
    "The inbox cleanup is the first thing to cut if I fall behind.",
]
REASONING = [
    "I know I tend to overestimate what I can do, so be realistic with the durations.",
    "Last week I ignored my own plan by Wednesday, so please don't pack every minute.",
    "The report matters more than the presentation this week even though the presentation sounds bigger.",
    "I'd like to finish before 9pm so I can actually rest and sleep properly.",
    "Honestly the thing I'm most worried about is the quiz, everything else can flex around it.",
]

POOLS = [("task", TASKS, 0.45), ("fixed", FIXED, 0.12), ("travel", TRAVEL, 0.08), ("dep", DEPENDENCIES, 0.10),
         ("energy", ENERGY, 0.08), ("fallback", FALLBACKS, 0.08), ("reason", REASONING, 0.09)]


def words(text: str) -> int:
    return len(text.split())


def build_dump(target_words: int, seed: int) -> str:
    """Assemble a messy dump of ~target_words from the pools, deterministically per (size, seed)."""
    rng = random.Random(seed * 100003 + target_words)
    bag = {name: rng.sample(pool, len(pool)) for name, pool, _ in POOLS}
    used: List[str] = []
    total = 0
    guard = 0
    while total < target_words and guard < 500:
        guard += 1
        name = rng.choices([p[0] for p in POOLS], weights=[p[2] for p in POOLS])[0]
        if not bag[name]:
            pool = dict((n, p) for n, p, _ in POOLS)[name]
            bag[name] = rng.sample(pool, len(pool))
        sentence = bag[name].pop()
        if total + words(sentence) > target_words + 12 and total >= target_words - 15:
            break
        used.append(sentence)
        total += words(sentence)
    text = " ".join(used)
    # trim to the exact target at a word boundary so size buckets are honest
    parts = text.split()
    if len(parts) > target_words:
        text = " ".join(parts[:target_words])
    return text


# ---- measurement ----------------------------------------------------------------------------------------------------
@dataclass
class Sample:
    size: int
    concurrency: int
    seed: int
    words: int
    chars: int
    ok: bool
    code: str  # "ok" or a GeminiFailure/other code
    seconds: float
    tasks: int = 0
    ctx_items: int = 0
    input_tokens: Optional[int] = None
    output_tokens: Optional[int] = None


class _TokenCapture(logging.Handler):
    """Collects input/output token counts that ai_service logs on each successful Gemini call, keyed by request id."""
    PATTERN = re.compile(r"gemini_ok request_id=(\S+) .*input_tokens=(\S+) output_tokens=(\S+)")

    def __init__(self):
        super().__init__()
        self.by_request: Dict[str, tuple] = {}

    def emit(self, record):
        m = self.PATTERN.search(record.getMessage())
        if m:
            rid, i, o = m.groups()
            self.by_request[rid] = (int(i) if i.isdigit() else None, int(o) if o.isdigit() else None)


def run_one(size: int, seed: int, concurrency: int, tokens: _TokenCapture, idx: int) -> Sample:
    from app.core.logging import logger  # noqa: F401  (ensures the logger exists before the handler is attached)
    from app.services import ai_gateway
    from app.services.ai_service import AIService, GeminiFailure

    from app.core import ai_limits
    ai_limits.breaker.reset()  # measure Gemini, not our own circuit breaker
    text = build_dump(size, seed)
    rid = f"bm{size}{seed}{idx}"[-12:].ljust(12, "x")
    started = time.perf_counter()
    try:
        res = ai_gateway.call_provider(
            AIService.extract_structured_plan_with_gemini,
            raw_text=text, user_timezone_str="Asia/Kolkata", request_id=rid,
            now_local=datetime.now().astimezone(),
        )
        candidates, _amb, _needs, ctx = res[:4]
        ctx_items = 0
        if ctx is not None:
            for name in ("fixed_events", "travel_segments", "protected_periods", "availability_windows",
                         "task_dependencies", "priority_order", "deferred_tasks"):
                ctx_items += len(getattr(ctx, name, None) or [])
        elapsed = time.perf_counter() - started
        tin, tout = tokens.by_request.get(rid, (None, None))
        return Sample(size, concurrency, seed, words(text), len(text), True, "ok", elapsed, len(candidates), ctx_items, tin, tout)
    except GeminiFailure as e:
        code = e.code
    except Exception as e:  # AIBusy, RuntimeError (no key) and the rest
        code = type(e).__name__
    return Sample(size, concurrency, seed, words(text), len(text), False, code, time.perf_counter() - started)


def pctl(values: List[float], q: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))]


@dataclass
class Row:
    size: int
    concurrency: int
    n: int = 0
    success: float = 0.0
    malformed: float = 0.0
    timeout: float = 0.0
    other: float = 0.0
    p50: float = 0.0
    p95: float = 0.0
    tasks_avg: float = 0.0
    ctx_avg: float = 0.0
    tin_avg: Optional[float] = None
    tout_avg: Optional[float] = None
    codes: Dict[str, int] = field(default_factory=dict)
    inconclusive: int = 0

    @property
    def conclusive(self) -> bool:
        return self.n > self.inconclusive and (self.n - self.inconclusive) >= MIN_CONCLUSIVE * self.n

    @property
    def status(self) -> str:
        if not self.conclusive:
            return "INCONCLUSIVE"
        return "PASS" if self.passes else "FAIL"

    @property
    def passes(self) -> bool:
        return (self.success >= GATE_SUCCESS and self.malformed <= GATE_MALFORMED
                and self.timeout <= GATE_TIMEOUT and self.p95 <= GATE_P95_SECONDS)


def summarize(samples: List[Sample]) -> List[Row]:
    rows: List[Row] = []
    for size in sorted({s.size for s in samples}):
        for conc in sorted({s.concurrency for s in samples if s.size == size}):
            group = [s for s in samples if s.size == size and s.concurrency == conc]
            n = len(group)
            codes: Dict[str, int] = {}
            for s in group:
                codes[s.code] = codes.get(s.code, 0) + 1
            inconc = sum(v for k, v in codes.items() if k in INCONCLUSIVE_CODES)
            group_c = [s for s in group if s.code not in INCONCLUSIVE_CODES]
            nc = max(1, len(group_c))
            ok = [s for s in group if s.ok]
            tin = [s.input_tokens for s in ok if s.input_tokens]
            tout = [s.output_tokens for s in ok if s.output_tokens]
            rows.append(Row(
                size=size, concurrency=conc, n=n,
                success=len(ok) / nc,
                malformed=codes.get("malformed", 0) / nc,
                timeout=(codes.get("timeout", 0) + codes.get("network", 0)) / nc,
                other=sum(v for k, v in codes.items() if k not in ("ok", "malformed", "timeout", "network") and k not in INCONCLUSIVE_CODES) / nc,
                inconclusive=inconc,
                p50=statistics.median([s.seconds for s in group_c]) if group_c else 0.0,
                p95=pctl([s.seconds for s in group_c], 0.95) if group_c else 0.0,
                tasks_avg=statistics.mean([s.tasks for s in ok]) if ok else 0.0,
                ctx_avg=statistics.mean([s.ctx_items for s in ok]) if ok else 0.0,
                tin_avg=statistics.mean(tin) if tin else None, tout_avg=statistics.mean(tout) if tout else None,
                codes=codes,
            ))
    return rows


def verdict(rows: List[Row]) -> dict:
    """Failure boundary = smallest size that FAILS the gate at any concurrency, judged on conclusive rows only.
    Limit = largest size at or below 70-75% of that boundary, rounded down to a multiple of 50. Rows dominated by
    provider quota / 503 / busy outcomes are INCONCLUSIVE: they never count as passing and never as failing, and any
    inconclusive size at or below the answer makes the whole verdict inconclusive (re-run those sizes)."""
    sizes = sorted({r.size for r in rows})
    status = {sz: [r.status for r in rows if r.size == sz] for sz in sizes}
    failing = [sz for sz in sizes if "FAIL" in status[sz]]
    inconclusive = [sz for sz in sizes if "INCONCLUSIVE" in status[sz]]
    boundary = failing[0] if failing else None
    limit_to_check = boundary if boundary is not None else sizes[-1]
    blockers = [sz for sz in inconclusive if sz <= limit_to_check]
    if blockers:
        return {"boundary": boundary, "recommended": None, "inconclusive_sizes": blockers,
                "note": "INCONCLUSIVE: provider quota / 503 / busy outcomes hid the answer at these sizes. Wait for the quota "
                        "window to reset (or use a key with headroom) and re-run only these sizes with --sizes."}
    if boundary is None:
        return {"boundary": None, "recommended": sizes[-1], "note": "no size failed the gate; limit capped at the largest size measured"}
    lo, hi = (int(boundary * h) for h in HEADROOM)
    passing = [sz for sz in sizes if sz < boundary and all(x == "PASS" for x in status[sz])]
    within = [sz for sz in passing if sz <= hi]
    chosen = max(within) if within else (max(passing) if passing else None)
    return {"boundary": boundary, "headroom_window": [lo, hi], "largest_passing_in_window": chosen,
            "recommended": (chosen // 50 * 50) if chosen else None,
            "note": "round to a clean number at or below the window; re-run around the boundary if the window falls between sizes"}


def render(rows: List[Row], v: dict) -> str:
    out = ["| words | conc | n | inconclusive (429 / 503 / busy) | success | malformed | timeout | other | p50 s | p95 s | tasks | ctx items | in tok | out tok | gate |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        f = lambda x: "-" if x is None else f"{x:.0f}"
        out.append(f"| {r.size} | {r.concurrency} | {r.n} | {r.inconclusive} ({r.codes.get('provider_quota', 0)} / {r.codes.get('provider_unavailable', 0)} / {r.codes.get('AIBusy', 0)}) | {r.success:.0%} | {r.malformed:.0%} | {r.timeout:.0%} | {r.other:.0%} | "
                   f"{r.p50:.1f} | {r.p95:.1f} | {r.tasks_avg:.1f} | {r.ctx_avg:.1f} | {f(r.tin_avg)} | {f(r.tout_avg)} | {r.status} |")
    out += ["", f"Gate: success >= {GATE_SUCCESS:.0%}, malformed <= {GATE_MALFORMED:.0%}, timeout <= {GATE_TIMEOUT:.0%}, "
            f"p95 <= {GATE_P95_SECONDS:.0f}s, at every concurrency; rates are over conclusive samples only (quota/503/busy excluded).", "", "Verdict: `" + json.dumps(v) + "`"]
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sizes", type=int, nargs="+", default=DEFAULT_SIZES)
    ap.add_argument("--runs", type=int, default=10, help="samples per size per concurrency level")
    ap.add_argument("--dumps", type=int, default=3, help="distinct dumps per size")
    ap.add_argument("--concurrency", type=int, nargs="+", default=[1, 6])
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[2] / "docs" / "superpowers" / "plans" / "bmd-limit-benchmark"))
    ap.add_argument("--pause", type=float, default=4.0, help="seconds between calls at concurrency 1 (rate-limit courtesy)")
    ap.add_argument("--stop-after-429", type=int, default=1, help="abort the whole run after this many consecutive 429s (default: the first one)")
    ap.add_argument("--size-pause", type=float, default=20.0, help="seconds between size batches")
    ap.add_argument("--dry-run", action="store_true", help="print the corpus word/char counts and exit; makes no calls")
    args = ap.parse_args()

    if args.dry_run:
        for size in args.sizes:
            for seed in range(args.dumps):
                t = build_dump(size, seed)
                print(f"size={size:>5} seed={seed} words={words(t):>5} chars={len(t):>6}")
        return 0

    from app.core.config import settings
    if not settings.GEMINI_API_KEY:
        print("GEMINI_API_KEY is not configured; nothing to benchmark.")
        return 2

    from app.core.logging import logger
    tokens = _TokenCapture()
    logger.addHandler(tokens)
    logger.setLevel(logging.INFO)

    samples: List[Sample] = []
    aborted = False
    for conc in args.concurrency:
        if aborted:
            break
        for size in args.sizes:
            jobs = [(size, i % args.dumps) for i in range(args.runs)]
            got: List[Sample] = []
            if conc == 1:  # sequential and paced; stop at once if the key is rate limited
                quota_streak = 0
                for i, (sz, seed) in enumerate(jobs):
                    smp = run_one(sz, seed, conc, tokens, i)
                    got.append(smp)
                    quota_streak = quota_streak + 1 if smp.code == "provider_quota" else 0
                    if quota_streak >= args.stop_after_429:
                        aborted = True
                        break
                    time.sleep(args.pause)
            else:
                with ThreadPoolExecutor(max_workers=conc) as pool:
                    futures = [pool.submit(run_one, sz, seed, conc, tokens, i) for i, (sz, seed) in enumerate(jobs)]
                    got = [f.result() for f in futures]
                if sum(x.code == "provider_quota" for x in got) >= args.stop_after_429:
                    aborted = True
            samples += got
            ok = sum(x.ok for x in got)
            inc = sum(x.code in INCONCLUSIVE_CODES for x in got)
            print(f"conc={conc} size={size}: {ok}/{len(got)} ok, {inc} inconclusive, p95={pctl([x.seconds for x in got], 0.95):.1f}s", flush=True)
            if aborted:
                print("ABORTED: Gemini is rate limiting this key (429). Stopping instead of spending more quota; "
                      "wait for the quota window to reset and re-run the remaining sizes.", flush=True)
                break
            time.sleep(args.size_pause)

    rows = summarize(samples)
    v = verdict(rows)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.with_suffix(".json").write_text(json.dumps([s.__dict__ for s in samples], indent=1), encoding="utf-8")
    md = render(rows, v)
    out.with_suffix(".md").write_text("# Build My Day input-limit benchmark\n\n" + md + "\n", encoding="utf-8")
    print("\n" + md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
