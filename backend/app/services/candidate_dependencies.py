"""Build My Day task dependencies (spec 2026-10-03 §4).

Gemini names dependencies by its own task refs ("t1"); candidates are identified by stable
`candidate_id`s. These helpers translate refs to ids and drop every reference the planner cannot honour,
recording why in `validation_issues` so nothing disappears silently.
"""
from typing import Dict, List

from ..schemas.task import TaskCandidateResponse


def _issue(c: TaskCandidateResponse, code: str, message: str) -> None:
    c.validation_issues.append({"code": code, "field": "depends_on", "message": message})


def resolve_dependencies(candidates: List[TaskCandidateResponse], ref_map: Dict[str, str]) -> None:
    """Translate each candidate's raw Gemini refs (in `depends_on`) to candidate_ids, in place.

    Unknown refs and self-references are dropped (`unknown_dependency`); every edge on a cycle is
    dropped and each member flagged (`dependency_cycle`).
    """
    for c in candidates:
        ids: List[str] = []
        for ref in c.depends_on:
            target = ref_map.get(ref)
            if target is None or target == c.candidate_id:
                _issue(c, "unknown_dependency", f"'{c.title}' referred to a task that is not in this plan.")
            elif target not in ids:
                ids.append(target)
        c.depends_on = ids
    _break_cycles(candidates)


def prune_dangling(candidates: List[TaskCandidateResponse]) -> None:
    """Drop dependency ids that no longer exist (e.g. a candidate was removed by segmentation)."""
    present = {c.candidate_id for c in candidates}
    for c in candidates:
        kept = [d for d in c.depends_on if d in present and d != c.candidate_id]
        if len(kept) != len(c.depends_on):
            _issue(c, "unknown_dependency", f"'{c.title}' depended on a task that is no longer in this plan.")
            c.depends_on = kept


def _break_cycles(candidates: List[TaskCandidateResponse]) -> None:
    by_id = {c.candidate_id: c for c in candidates}
    WHITE, GREY, BLACK = 0, 1, 2
    color = {cid: WHITE for cid in by_id}
    cyclic_edges = set()

    def visit(cid: str, stack: List[str]) -> None:
        color[cid] = GREY
        stack.append(cid)
        for dep in by_id[cid].depends_on:
            if dep not in by_id:
                continue
            if color[dep] == GREY:  # back edge: the cycle is stack[from dep ..] -> dep
                cycle = stack[stack.index(dep):]
                for i, node in enumerate(cycle):
                    cyclic_edges.add((node, cycle[i + 1] if i + 1 < len(cycle) else dep))
            elif color[dep] == WHITE:
                visit(dep, stack)
        stack.pop()
        color[cid] = BLACK

    for cid in by_id:
        if color[cid] == WHITE:
            visit(cid, [])

    members = {n for edge in cyclic_edges for n in edge}
    for cid in members:
        c = by_id[cid]
        c.depends_on = [d for d in c.depends_on if (cid, d) not in cyclic_edges]
        _issue(c, "dependency_cycle", f"'{c.title}' was part of a circular dependency; the order was dropped.")


def link_sequential_from_text(candidates: List[TaskCandidateResponse], follows: List[bool]) -> bool:
    """Order candidates the way the user wrote them, when the model returned no ordering at all.

    ``follows[i]`` says clause i was introduced by a sequencing linker ("then", "after that", ...).
    Candidates are in mention order, so the flags are only applied when the counts match; anything
    else is left alone rather than guessed.
    """
    if not candidates or len(follows) != len(candidates) or any(c.depends_on for c in candidates):
        return False
    linked = False
    for i in range(1, len(candidates)):
        if follows[i]:
            candidates[i].depends_on = [candidates[i - 1].candidate_id]
            linked = True
    return linked
