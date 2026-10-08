# Build My Day input-limit benchmark

| words | conc | n | inconclusive (429 / 503 / busy) | success | malformed | timeout | other | p50 s | p95 s | tasks | ctx items | in tok | out tok | gate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 150 | 1 | 10 | 0 (0 / 0 / 0) | 100% | 0% | 0% | 0% | 6.5 | 8.2 | 8.1 | 5.3 | 4449 | 2435 | PASS |
| 250 | 1 | 10 | 0 (0 / 0 / 0) | 100% | 0% | 0% | 0% | 11.7 | 22.4 | 15.5 | 10.9 | 4677 | 4770 | FAIL |
| 350 | 1 | 10 | 0 (0 / 0 / 0) | 100% | 0% | 0% | 0% | 9.9 | 11.7 | 14.7 | 10.5 | 4714 | 4513 | PASS |
| 450 | 1 | 10 | 2 (0 / 2 / 0) | 25% | 0% | 75% | 0% | 24.9 | 25.3 | 15.5 | 17.0 | 4848 | 5026 | FAIL |
| 600 | 1 | 10 | 8 (0 / 8 / 0) | 0% | 0% | 100% | 0% | 24.9 | 25.0 | 0.0 | 0.0 | - | - | INCONCLUSIVE |
| 800 | 1 | 4 | 4 (1 / 3 / 0) | 0% | 0% | 0% | 0% | 0.0 | 0.0 | 0.0 | 0.0 | - | - | INCONCLUSIVE |

Gate: success >= 98%, malformed <= 1%, timeout <= 1%, p95 <= 15s, at every concurrency; rates are over conclusive samples only (quota/503/busy excluded).

Verdict: `{"boundary": 250, "headroom_window": [175, 187], "largest_passing_in_window": 150, "recommended": 150, "note": "round to a clean number at or below the window; re-run around the boundary if the window falls between sizes"}`
