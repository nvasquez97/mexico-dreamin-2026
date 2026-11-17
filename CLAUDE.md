# Project rules

## Language

Always respond in English, even when the user writes in Spanish.

## Workflow: ODD

- Every change follows the odd skill. Load it before writing or modifying any
  code or metadata, and follow its spine in order.
- ODD starts whenever the user asks to work on something, with or without
  the /work command.
- At the checkpoint, ask the user to approve the Problems and Solutions and
  to choose the mode, interactive or auto. Never assume the mode; skip the
  question only for what the request already states.
- One task document per requirement, in odd/tasks/.
- Analyze before executing: fill the Task analysis table (scope, executor and
  reviewers for every task) before the first worker is launched.
- Do not write production code in the main session for tier 1 and tier 2
  work. Launch one task-worker per task, with a Handoff block.
- After every task commit, and before ticking it, launch task-reviewer over
  that sha. If the task touches security, also launch security-reviewer and
  access-auditor.
- One committing worker at a time. One reviewer per role per task. One fix
  round per task, done by a task-worker in fix mode and closed by resuming
  the same reviewers; do not loop.
- Tick a task only with its sha, its evidence path and its review result.
- Close every requirement with the gate over the whole package at HEAD, then
  its requirement reviews. After the last requirement, run Hardening: audit
  the whole product, turn every Critical and High finding into tasks, and
  audit again, at most 3 audits in total.
- The main session commits the task document and .mem/; workers commit only
  their task files.
- In Mode: auto, if a decision is missing, choose the most conservative
  option and record it as an assumption. In Mode: interactive, ask.
- Humans own delivery: do not open pull requests, merge, or deploy anywhere
  except the project's development org.

## Agents

| Phase | Agent |
|---|---|
| Explore, when the scope is unknown | Explore (built-in) |
| Execute a task | task-worker |
| Review after every task | task-reviewer |
| Security lens, on tasks that touch security | security-reviewer, access-auditor |
| Close of a requirement | test-reviewer; brand-reviewer when there is interface; sf-security-auditor and access-auditor on tier 2 |
| After the last requirement | Hardening: sf-security-audit (scanner, Code Analyzer and the three sf-security specialists), at most 3 audits |
| End of run | salesforce-code-quality:architecture-review (report only) |
| Mechanical work (renames, bulk data) | A script, not an agent |

## Project memory

- Memory lives in .mem/memory.md. Follow the project-memory skill for what to
  save, when to save it and how to rotate the file.
- Read .mem/memory.md at the start of every session and before resuming work.
- Write to it at every task transition, after each review and before ending
  the session.
- Never write secrets, keys or tokens to memory.

## Security rules

The project security policy is
.claude/skills/sf-security-audit/references/security-policy.md (rules P1-P11
and X1-X16). Every security finding cites one of its rules. The short version:

- No secrets in the repository: not in code, tests, scripts, documentation,
  evidence or memory. Outbound calls use Named Credentials.
- Every method exposed to external users validates on the server who is
  calling and on which record, and returns only the fields that are needed.
- Methods receive individual fields, not whole records.
- Queries use bind variables; dynamic fields and sort order are validated
  against a closed list.
- Every class declares its sharing mode. System mode and `without sharing` are
  used only where necessary, with a comment
  `// SECURITY-JUSTIFICATION: <why, scope, compensating control> (<approver>, <date>)`.
- Guest and external actions are never authorized only by guessable or public
  facts such as a postal code, an email or a record number.
- External access to objects is Private unless there is a written
  justification.
- Permissions are granted with minimal permission sets, one per actor. The
  guest user receives no object permissions.
- Inbound services authenticate with OAuth.
- Every test states the acceptance criterion it covers.
