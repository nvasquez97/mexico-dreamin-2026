# Project rules

## Language

Always respond in English, even when the user writes in Spanish.

## Workflow

Follow these steps on every request, in this order.

1. Authorize. Decide whether the request authorizes a change. Questions,
   reviews and proposals stay read-only.
2. Explore. Read .mem/memory.md first, then the existing code and the
   requirements, before changing anything.
3. Resolve uncertainty. If a decision is missing, choose the most
   conservative option and record it as an assumption. Do not stop to ask.
4. Classify. A task is small when it is understood, its risk is contained,
   and it could be resumed from the request and git diff alone. Otherwise it
   is large. The number of files does not decide.
5. Track before the first write. For large work, create one feature document
   at odd/tasks/<feature-name>.md before the first source write:
   - Header: objective, branch and test runner.
   - Specs: numbered S1..Sn. Each S# keeps the identifier of the acceptance
     criterion from the design document (for example, AC-002.3) and its
     literal text.
   - Tasks: one line per task, with its ID, the S# it covers, its status and
     its commit.
   - Log: L1 is the original request, word for word. Decisions, evidence and
     reviewer verdicts are appended after it.
6. Implement task by task.
   - Test-first: when a runnable test exists, watch it fail before
     implementing, make it pass, then refactor. The test runner is Apex with
     sf apex run test against the project org.
   - Commits: work on a feature branch with small commits, one per unit of
     work, with the tests alongside the behavior. Do not open pull requests.
   - Risk line: close every code change with "Risk: item N (reason)" or
     "Risk: none". The high-risk items are: (1) irreversible data changes,
     (2) security: authentication, permissions, credentials, secrets,
     (3) contracts others consume, (4) concurrency, (5) delivery or
     environment, (6) changes no test would catch.
   - Check a task off only with observed proof, and record its commit in the
     feature document.
7. Close. Report the verified outcome, every failed or pending check, and the
   next step.

## Independent verification

- When the risk line of a change names item 2 (security), run the
  security-reviewer and access-auditor subagents. Pass them the path of the
  feature document and the S# of the change. Fix Critical and High findings
  before closing the task.
- Before closing the feature, run test-reviewer, brand-reviewer and
  architecture-review once each, and record their verdicts in the Log
  section.
- Do not close the feature with open Critical or High findings. If one cannot
  be resolved, record it in the Log section and in the README with the
  reason.

## Project memory

- Memory lives in .mem/memory.md. Follow the project-memory skill for what to
  save, when to save it and how to rotate the file.
- Read .mem/memory.md at the start of every session and before resuming work.
- Write to it at every task transition, after each reviewer verdict and
  before ending the session.
- Never write secrets, keys or tokens to memory.

## Security rules

- No secrets in the repository: not in code, tests, scripts, documentation
  or memory. Outbound calls use Named Credentials.
- Every method exposed to external users validates on the server who is
  calling and on which record, and returns only the fields that are needed.
- Methods receive individual fields, not whole records.
- Queries use bind variables; dynamic fields and sort order are validated
  against a closed list.
- Every class declares its sharing mode. System mode is used only where it is
  necessary and is justified in a comment.
- External access to objects is Private unless there is a written
  justification.
- Permissions are granted with minimal permission sets, one per actor. The
  guest user receives no object permissions.
- Inbound services authenticate with OAuth.
- Every test states the acceptance criterion it covers.
