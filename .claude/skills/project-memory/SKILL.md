---
name: project-memory
description: Keeps the project's working memory in .mem/memory.md - summaries, decisions, assumptions, task state and open issues - and rotates the file into .mem/history/ when it exceeds 50 KB. Use at the start of a session, at every task transition, after a reviewer verdict, before ending a session, and whenever the user asks to remember, recall or summarize project context.
---

# Project memory

The project's memory is a set of plain Markdown files inside the repository.
Nothing is stored outside it.

## Layout

    .mem/
      memory.md     Active memory. Never larger than 50 KB.
      history/      Full copies of earlier memory files. Never edited or deleted.

If .mem/ does not exist, create it with a memory.md that contains only the
line "# Project memory", and an empty history/ folder with a .gitkeep file.

.mem/ is part of the repository: commit it together with the work.

## What goes into memory

Save what a new session would need to continue without rereading everything:

- The run settings: the target org, the mode, and whether the mode was
  chosen for one requirement or for the whole run.
- Decisions, and the reason for each.
- Assumptions made when a decision was missing.
- State of the work: the active task document, tasks done, in progress
  and blocked, a fix round in progress (point to the task line that holds
  the reviewer ids), and the next step.
- Each requirement's close: the gate result, the coverage, the review
  verdicts and the open findings, in one or two lines.
- Hardening: the round number, the counts by severity before and after, and
  the hardening task document. Cite SEC ids only.
- What was verified and how: the command or test, and its result in one line.
- Reviewer verdicts and the findings that are still open.
- Lessons about the environment: an error that was hit and the fix that
  worked.

Do not save: secrets, keys, tokens or passwords; source code; full command
output or logs; anything already written in the task document (point to it
instead); attack details of a security finding, such as payloads or the
steps to exploit it (memory is committed: cite the SEC id and the path, the
report stays in .security-reports/).

## Entry format

Append entries at the end. Do not rewrite earlier entries.

    ## YYYY-MM-DD HH:MM — short title
    - Type: decision | assumption | status | verification | review | close | hardening | environment
    - What: one or two sentences.
    - Why / evidence: one sentence, or a path, a commit or a command.
    - Next: the next step, if there is one.

Keep each entry short. Prefer a pointer (file path, commit hash, S#) over a
copy of the content.

## When to read

- At the start of every session, before any other work: read .mem/memory.md
  in full.
- Before resuming an interrupted task.
- Read a file in .mem/history/ only when the active memory points to it and
  the detail is needed.

## When to write

- The run starts or resumes: the org and the mode.
- A task starts, finishes, is blocked or is reopened.
- A decision or an assumption is made.
- A reviewer returns a verdict, and a fix round starts or closes.
- A requirement closes: before the close commit, so the entry is part of it.
- A hardening round starts or ends, and at the end of the run.
- Before ending the session, or when the context is about to be compacted.

## Size limit and rotation

After every write, check the size:

    wc -c .mem/memory.md

If it is larger than 50 KB (51200 bytes), rotate before doing anything else:

1. Write a summary of the current memory.md, at most 10 KB. Keep: the run
   settings (org, mode); the active task document and the next step;
   unfinished tasks and any fix round in progress; decisions still in force
   (only the final version of each); assumptions; open findings; the
   hardening round and its counts; environment lessons. Drop: resolved detail, superseded decisions, repeated
   status entries and verbose evidence (keep the pointer).
2. Move the full file to the history folder with a timestamped name:

       mv .mem/memory.md .mem/history/memory-YYYYMMDD-HHMM.md

3. Create a new .mem/memory.md that contains only:

       # Project memory

       ## Summary of memory up to YYYY-MM-DD HH:MM
       Full file: .mem/history/memory-YYYYMMDD-HHMM.md

       <the summary from step 1>

4. Confirm that the new file is under 50 KB and that the archived file
   exists, then continue with the work.

Rules for rotation:

- Archive the full file before replacing it. If the move fails, stop and
  report it; do not overwrite memory.md.
- Never delete or edit a file in .mem/history/.
- If a write would push the file over the limit, rotate first and then write.
