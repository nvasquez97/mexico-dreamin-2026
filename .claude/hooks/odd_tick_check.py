#!/usr/bin/env python3
"""PreToolUse hook (Edit|Write|MultiEdit) on odd/tasks/**.md: a task is ticked only with
its sha, its evidence file and its review result, and the sha and the file must exist.
Fails open on any internal error."""
import json
import os
import re
import subprocess
import sys

TICK_RE = re.compile(r"^\s*-\s*\[[xX]\]\s*(T\d+)\b.*$", re.MULTILINE)
FULL_RE = re.compile(r"[—–-]\s*([0-9a-f]{7,40})\s*·\s*evidence:\s*(\S+)\s*·\s*review:\s*"
                     r"(clean|fixed in [0-9a-f]{7,40}.*|open\s*[—–-].+)\s*$")


def new_text(tool, ti):
    if tool == "Write":
        return ti.get("content") or ""
    if tool == "Edit":
        return ti.get("new_string") or ""
    if tool == "MultiEdit":
        return "\n".join(e.get("new_string") or "" for e in ti.get("edits") or [])
    return ""


def main():
    try:
        p = json.load(sys.stdin)
        ti = p.get("tool_input") or {}
        path = ti.get("file_path") or ""
        if "/odd/tasks/" not in path.replace("\\", "/") or not path.endswith(".md"):
            return
        root = os.environ.get("CLAUDE_PROJECT_DIR") or p.get("cwd") or os.getcwd()
        errs = []
        for m in TICK_RE.finditer(new_text(p.get("tool_name"), ti)):
            line, task = m.group(0).strip(), m.group(1)
            full = FULL_RE.search(line)
            if not full:
                errs.append(f"{task}: the tick needs '— <sha> · evidence: odd/evidence/<slug>/{task}.md · "
                            f"review: clean | fixed in <sha> | open — <finding>'")
                continue
            sha, ev = full.group(1), full.group(2)
            ok = subprocess.run(["git", "-C", root, "cat-file", "-e", sha + "^{commit}"],
                                capture_output=True).returncode == 0
            if not ok:
                errs.append(f"{task}: commit {sha} does not exist")
            if not os.path.isfile(os.path.join(root, ev)):
                errs.append(f"{task}: evidence file {ev} does not exist")
        if errs:
            reason = ("ODD tick check refused this edit:\n- " + "\n- ".join(errs) +
                      "\nTick a task only after its commit, its evidence file and its review exist.")
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "permissionDecision": "deny",
                                                     "permissionDecisionReason": reason}}))
    except Exception:
        return


if __name__ == "__main__":
    main()
