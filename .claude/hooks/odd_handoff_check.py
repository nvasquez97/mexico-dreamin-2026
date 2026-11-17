#!/usr/bin/env python3
"""PreToolUse hook (Agent|Task): an ODD agent is launched only with a complete handoff.

The main session must hand every ODD subagent the task and the data it needs, so the
subagent does not have to rebuild the context from zero. This hook refuses the launch
when the handoff block is missing, a required field is absent or empty, or a field still
holds a template placeholder such as <sha>.

A launch outside ODD (a probe, a one-off question) starts its prompt with
"Handoff-exempt: <reason>". On any internal error the hook allows the launch (fail open),
so a bug here can never stop a run.
"""
import json
import re
import sys

WORKER = "task-worker"

# Fields of each handoff block, by normalized name (text before " (" , lower case).
WORKER_FIELDS = ["goal", "task document", "task", "decided", "acceptance", "touch",
                 "org", "skills", "runners", "return"]
FIX_FIELDS = ["task document", "task", "findings", "acceptance", "touch", "org",
              "skills", "evidence", "runners", "return"]
REVIEW_CORE = ["task document", "task", "target", "org", "return"]
REVIEW_EXTRA = {
    "task-reviewer": ["acceptance", "scope", "evidence", "skills", "security"],
    "security-reviewer": ["acceptance", "scope"],
    "access-auditor": ["acceptance", "scope"],
    "test-reviewer": ["acceptance", "evidence", "coverage"],
    "brand-reviewer": ["scope"],
    "sf-security-auditor": ["scope"],
    "plan-reviewer": ["requirement"],
}
KNOWN = set(WORKER_FIELDS + FIX_FIELDS + REVIEW_CORE + ["do not read", "requirement", "scope",
            "evidence", "skills", "security", "coverage", "findings", "acceptance"])

FIELD_RE = re.compile(r"^\s*-\s+([A-Za-z][A-Za-z /()-]*?)\s*:\s?(.*)$")
PLACEHOLDER_RE = re.compile(r"^<[^<>]+>$|<(sha|alias|slug|paths?|file list|decisions|"
                            r"target org alias|what done looks like|full skill names[^>]*|list)>",
                            re.IGNORECASE)


def block(prompt, heading):
    """Return the text under '## <heading>' until the next '## ' heading, or None."""
    m = re.search(r"^##\s+" + re.escape(heading) + r"\s*$", prompt, re.MULTILINE | re.IGNORECASE)
    if not m:
        return None
    rest = prompt[m.end():]
    nxt = re.search(r"^##\s+\S", rest, re.MULTILINE)
    return rest[: nxt.start()] if nxt else rest


def fields(text):
    out, current = {}, None
    for line in text.splitlines():
        m = FIELD_RE.match(line)
        name = m.group(1).split(" (")[0].strip().lower() if m else None
        if m and name in KNOWN:
            current = name
            out[current] = m.group(2).strip()
        elif current is not None and line.strip():
            out[current] = (out[current] + "\n" + line.strip()).strip()
    return out


def problems(found, required):
    errs = []
    for f in required:
        v = found.get(f)
        if v is None:
            errs.append(f"missing field '{f}'")
        elif not v.strip():
            errs.append(f"field '{f}' is empty")
        elif PLACEHOLDER_RE.search(v.strip().splitlines()[0]) or PLACEHOLDER_RE.search(v):
            errs.append(f"field '{f}' still holds a template placeholder: {v.splitlines()[0][:60]}")
    return errs


def check(agent, prompt):
    if agent == WORKER:
        fix = block(prompt, "Fix handoff")
        if fix is not None:
            f = fields(fix)
            return problems(f, FIX_FIELDS)
        hand = block(prompt, "Handoff")
        if hand is None:
            return ["no '## Handoff' or '## Fix handoff' block (see the odd skill, Execute and Fix round)"]
        f = fields(hand)
        errs = problems(f, WORKER_FIELDS)
        acc = f.get("acceptance", "")
        if acc and "AC-" not in acc:
            errs.append("'acceptance' has no AC-<id> line: copy the acceptance lines verbatim")
        if acc and "mutation" not in acc.lower():
            errs.append("'acceptance' has no *Mutation:* line: every acceptance line carries one")
        sk = f.get("skills", "")
        if sk and ":" not in sk and not sk.lower().startswith("none"):
            errs.append("'skills' must use full plugin names (e.g. salesforce-development:platform-apex-generate) or say 'none (<reason>)'")
        return errs

    if agent in REVIEW_EXTRA:
        if agent == "sf-security-auditor" and "odd/tasks/" not in prompt:
            return []  # used outside ODD
        rev = block(prompt, "Review handoff")
        if rev is None:
            return ["no '## Review handoff' block (see the odd skill, Review)"]
        f = fields(rev)
        if "findings" in f:  # a fresh closing check: verify only these findings
            return problems(f, REVIEW_CORE + ["findings"])
        errs = problems(f, REVIEW_CORE + REVIEW_EXTRA[agent])
        if agent == "task-reviewer" and f.get("acceptance") and "AC-" not in f["acceptance"]:
            errs.append("'acceptance' has no AC-<id> line: copy the acceptance lines verbatim")
        return errs
    return []


def main():
    try:
        payload = json.load(sys.stdin)
        ti = payload.get("tool_input") or {}
        agent = (ti.get("subagent_type") or "").strip()
        agent = agent.split(":")[-1]
        prompt = ti.get("prompt") or ""
        if re.search(r"^\s*Handoff-exempt:\s*\S", prompt, re.MULTILINE):
            return
        errs = check(agent, prompt)
        if not errs:
            return
        reason = (f"ODD handoff check refused launching '{agent}':\n- " + "\n- ".join(errs) +
                  "\nComplete the handoff from the task document (the subagent must not rebuild "
                  "the context from zero) and launch again. Do not work around this check.")
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                 "permissionDecision": "deny",
                                                 "permissionDecisionReason": reason}}))
    except Exception:
        return  # fail open


if __name__ == "__main__":
    main()
