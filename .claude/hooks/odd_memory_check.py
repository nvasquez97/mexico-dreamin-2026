#!/usr/bin/env python3
"""PostToolUse hook (Edit|Write|MultiEdit) on .mem/memory.md: tells the model to rotate the
memory when it passes 50 KB, and to remove anything that looks like a secret. Fails open."""
import json
import os
import re
import sys

LIMIT = 51200
SECRET_RE = re.compile(
    r"sk_live_[0-9A-Za-z]{8,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|force://\S+|"
    r"xox[baprs]-[0-9A-Za-z-]{10,}|gh[po]_[0-9A-Za-z]{30,}|eyJ[0-9A-Za-z_-]{20,}\.[0-9A-Za-z_-]{20,}|"
    r"(?i:(password|passwd|secret|client_secret|api[_-]?key|access[_-]?token)\s*[:=]\s*['\"]?[^\s'\"<>]{8,})")


def main():
    try:
        p = json.load(sys.stdin)
        ti = p.get("tool_input") or {}
        if p.get("tool_name") == "Bash":
            # A shell write to memory (a heredoc, echo >>) gets the same check.
            if ".mem/memory.md" not in (ti.get("command") or ""):
                return
            root = os.environ.get("CLAUDE_PROJECT_DIR") or p.get("cwd") or os.getcwd()
            path = os.path.join(root, ".mem", "memory.md")
            if not os.path.isfile(path):
                return
        else:
            path = (ti.get("file_path") or "").replace("\\", "/")
            if not path.endswith("/.mem/memory.md"):
                return
        msgs = []
        size = os.path.getsize(path)
        if size > LIMIT:
            msgs.append(f".mem/memory.md is {size} bytes, over the 50 KB limit (51200). Rotate it now, "
                        "following 'Size limit and rotation' in the project-memory skill, before any other work.")
        hits = SECRET_RE.findall(open(path, encoding="utf-8", errors="ignore").read())
        if hits:
            msgs.append("project memory seems to contain a secret (a key, a token, a password or an auth URL). "
                        "Remove it now: memory is committed and must never hold secrets. If it was real, "
                        "it must also be rotated.")
        if msgs:
            print(json.dumps({"decision": "block", "reason": " ".join(msgs)}))
    except Exception:
        return


if __name__ == "__main__":
    main()
