#!/usr/bin/env python3
"""Tick check on odd/tasks/**.md: a task is ticked only with its sha, its evidence file and
its review result, and the sha and the file must exist.

- PreToolUse on Edit|Write|MultiEdit: checks the file as it will be, and denies the edit.
- PostToolUse on Bash: when a shell command touched a task document, checks the file as it
  is now and tells the model to fix it (the change already happened).
Fails open on any internal error."""
import json
import os
import re
import subprocess
import sys

TICK_RE = re.compile(r"^\s*-\s*\[[xX]\]\s*(T\d+)\b.*$", re.MULTILINE)
# An unchecked task line that already carries tick data: the box was forgotten.
UNCHECKED_RE = re.compile(r"^\s*-\s*\[ \]\s*(T\d+)\b.*·\s*(evidence|review):.*$", re.MULTILINE)
REVIEW = r"(clean|fixed in [0-9a-f]{7,40}(?:,\s*open\s*[—–-][^·]+)?|open\s*[—–-][^·]+)"
FULL_RE = re.compile(r"[—–-]\s*([0-9a-f]{7,40})\s*·\s*evidence:\s*(\S+)\s*·\s*review:\s*"
                     + REVIEW + r"\s*(?:·\s*reviewers:[^·]*)?$")
TASKDOC_RE = re.compile(r"[\w./-]*odd/tasks/[\w./-]+\.md")


def apply(text, old, new, replace_all):
    if not old:
        return new
    return text.replace(old, new) if replace_all else text.replace(old, new, 1)


def new_text(tool, ti, path):
    """The file content as it will be after the edit, so a tick is checked as a whole line."""
    if tool == "Write":
        return ti.get("content") or ""
    try:
        current = open(path, encoding="utf-8").read()
    except OSError:
        current = ""
    if tool == "Edit":
        return apply(current, ti.get("old_string") or "", ti.get("new_string") or "",
                     ti.get("replace_all"))
    if tool == "MultiEdit":
        for e in ti.get("edits") or []:
            current = apply(current, e.get("old_string") or "", e.get("new_string") or "",
                            e.get("replace_all"))
        return current
    return ""


def check_text(text, root):
    errs = []
    for m in UNCHECKED_RE.finditer(text):
        errs.append(f"{m.group(1)}: the line has the tick data but the box is unchecked; write '- [x]'")
    for m in TICK_RE.finditer(text):
        line, task = m.group(0).strip(), m.group(1)
        full = FULL_RE.search(line)
        if not full:
            errs.append(f"{task}: the tick needs '— <sha> · evidence: odd/evidence/<slug>/{task}.md · "
                        f"review: clean | fixed in <sha> | open — <finding>' and optionally "
                        f"'· reviewers: <role id, ...>' at the end")
            continue
        sha, ev = full.group(1), full.group(2)
        ok = subprocess.run(["git", "-C", root, "cat-file", "-e", sha + "^{commit}"],
                            capture_output=True).returncode == 0
        if not ok:
            errs.append(f"{task}: commit {sha} does not exist")
        if not os.path.isfile(os.path.join(root, ev)):
            errs.append(f"{task}: evidence file {ev} does not exist")
    return errs


def main():
    try:
        p = json.load(sys.stdin)
        ti = p.get("tool_input") or {}
        root = os.environ.get("CLAUDE_PROJECT_DIR") or p.get("cwd") or os.getcwd()
        if p.get("tool_name") == "Bash":
            errs = []
            for rel in sorted(set(TASKDOC_RE.findall(ti.get("command") or ""))):
                path = rel if os.path.isabs(rel) else os.path.join(root, rel)
                if os.path.isfile(path):
                    errs += check_text(open(path, encoding="utf-8").read(), root)
            if errs:
                print(json.dumps({"decision": "block", "reason":
                    "ODD tick check: a shell command changed a task document and left it invalid:\n- "
                    + "\n- ".join(errs) + "\nFix it with the Edit tool. Edit task documents only with "
                    "Edit or Write, never with a shell command."}))
            return
        path = ti.get("file_path") or ""
        if "/odd/tasks/" not in path.replace("\\", "/") or not path.endswith(".md"):
            return
        errs = check_text(new_text(p.get("tool_name"), ti, path), root)
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
