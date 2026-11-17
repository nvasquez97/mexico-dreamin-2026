---
name: odd
description: Organic Driven Development - the workflow for every change in this repository. Use before writing or modifying any code or metadata, when starting or resuming a requirement, when analyzing tasks, launching a worker, reviewing a task or closing a requirement.
---

# ODD — Organic Driven Development

Rigor proportional to risk. Every piece of work walks the same spine; the tier
decides how much ceremony the spine carries. Work comes first and review
follows it: a review runs over a committed task, never over intentions. Humans
own delivery: an agent never merges, opens a pull request, or deploys anywhere
except the project's development org.

## The spine

    Read & infer → Explore → Problems → Solutions → Classify → Checkpoint
      → Task analysis (scope, executor and reviewers per task) → Plan review
      → Execute (one worker per task: red → green → mutations → commit)
      → Review (after every task) → Fix round → Tick
      → Close (gate, requirement reviews, fix round) → Archive
    After the last requirement:
      → Hardening (security audit → tasks → re-audit, at most 3 audits)
      → End of run (architecture review, final report)

| # | Phase | Who | Output |
|---|---|---|---|
| 1 | Read & infer | Main session | Understanding of the requirement: its acceptance criteria and business rules |
| 2 | Explore | Main session. An Explore agent only when the scope is unknown | Findings with path:line |
| 3 | Problems → Solutions | Main session | P1.., and S1 → P1 with the discarded alternatives |
| 4 | Classify | Main session | The Tier line |
| 5 | Checkpoint | The owner, who approves Problems and Solutions and chooses the mode | The Approved line and the Mode line |
| 6 | Task analysis | Main session | Acceptance lines, and the task table with scope, executor and reviewers |
| 6b | Plan review | plan-reviewer | clean, or findings fixed by the main session in one round |
| 7 | Execute | task-worker, one per task | One commit per task and its evidence file |
| 8 | Review | task-reviewer after every task; the security lens when the task touches security | clean, or findings and one fix round |
| 9 | Tick | Main session | The task line checked, with sha, evidence and review result |
| 10 | Close | Main session; requirement reviewers in parallel | The gate result, the coverage, the review verdicts and the Close section |
| 11 | Archive | Main session | The close commit, with the task document moved to odd/tasks/archive/ |
| 12 | Hardening | sf-security-audit, then the normal spine for the fixes | Hardening task documents, until no Critical or High remains or 3 audits |
| 13 | End of run | salesforce-code-quality:architecture-review; main session | odd/final-report.md |

## Starting work

ODD starts whenever the user asks to work on something: a requirement, a
feature, a fix or the whole design. The /work command is the explicit entry
point, but a plain request such as "let's start on REQ-003" starts it too.

1. Run phases 1 to 4 (read, explore, Problems → Solutions, classify) and
   write them in the task document. Write no code yet. If the work is tier 0,
   there is no task document: follow "Tier 0" below instead.
2. Stop at the checkpoint and ask the user, in one message:
   - whether they approve the Problems and Solutions, and
   - which mode they want: interactive or auto, and whether that choice is
     for this requirement only or for the whole run.
   Show a short summary first: the tier and its reason, the solutions and
   what each one discards.
3. Record the answers in the header of the task document: `Mode: <mode>` and
   `Approved: <who>, <date>`. Only then continue with the task analysis.

Rules:

- Never assume the mode. If the request does not state it, ask.
- Do not ask again what the request already states. A request that says
  "Mode: interactive" or "Mode: auto" sets the mode; the approval of Problems
  and Solutions is still asked.
- A request that says "Mode: auto, unattended" pre-approves the checkpoint
  for that run. Record `Mode: auto` and
  `Approved: unattended run, per the request, <date>` and continue without
  stopping.
- If the user chose a mode for the whole run, later requirements keep that
  mode. In interactive, each requirement still stops at its checkpoint. In
  auto for the whole run, later checkpoints are recorded as
  `Approved: standing choice of <who>, <date>`.
- When resuming a task document that already has a Mode line, keep that mode
  unless the user changes it.

## Unit of work

One task document per requirement of the design document (REQ-001, REQ-002,
and so on), plus one for the shared foundation (objects, fields, site, test
data) when it is needed first. Work on the requirements in dependency order,
on one working branch for the whole run.

## Tiers

Decide the tier after Problems → Solutions, because only then are the touched
files and the impact known.

| Tier | When | What it carries |
|---|---|---|
| 0 | One understood step that changes no requirement, no permission and no contract, in at most 100 changed lines | A test watched failing, the fix, one commit. Problems and Solutions go in the commit message. Runs inline, with no task document |
| 1 (default) | Two or more real steps, or progress worth recovering after an interruption | A task document. Every task runs in a worker and is reviewed |
| 2 | The work defines or changes who can access what (permissions, sharing model, authentication), handles a secret, or implements a contract with an external system | Tier 1, plus the security lens on every task that touches those items |

Rules:

1. The task document opens with `Tier: <n> · Reason: <item>`. The item must
   be concrete: an acceptance criterion id, a business rule id or an existing
   file. "To be safe" is not a reason; classify lower.
2. The default is tier 1.
3. On tier 2, the checkpoint summary names each access, secret or contract
   item explicitly, so the owner approves them knowingly.

### Tier 0

Tier 0 runs inline in the main session, with no task document and no
worker:

1. In Mode: interactive, show the Problems, the Solution and the tier reason
   in one message and ask for approval. In Mode: auto, or when the request
   already approved it, continue. If the mode is not known, ask.
2. Write the test, watch it fail, fix, watch it pass.
3. Commit once. The message records `Tier: 0 · Reason: <item>`, the Problems
   and the Solution.
4. Launch task-reviewer over that sha, with the test as the acceptance line.
   One fix round, done in the main session, closed by resuming the same
   reviewer. Whatever stays open is recorded in project memory.
5. Write the result in project memory.

## Task document

Path: odd/tasks/<slug>.md, for example odd/tasks/req-003-reschedule.md.

```markdown
# <slug> — <one-line goal>
Tier: 1 · Reason: <item>
Mode: <interactive or auto>
Branch: <branch>
Org: <target org alias>
Approved: <who>, <date>
Base: <HEAD sha before the plan commit of this document>
Plan review: <clean | fixed | open — <finding>> (plan-reviewer <id>)

## Findings
- <fact> (`path:line`)

## Problems
- P1: <problem> (evidence: <finding or requirement id>)

## Solutions
- S1 → P1: <solution>. Discarded: <alternative> (<why>).

## Acceptance
- AC-003.2 — Given <state>, When <action>, Then <observable result>.
  *Mutation:* <production change that turns this red> — observed: <verbatim red>

## Task analysis
| Task | Solves | Acceptance | Scope (files to touch) | Security | Executor | Skills | Reviewers |
|---|---|---|---|---|---|---|---|
| T1 | S1 | AC-003.1, AC-003.2 | <paths> | yes | task-worker | <full skill names> | task-reviewer, security-reviewer, access-auditor |

## Tasks
- [ ] T1 (S1): <task> — test first

## Close
Stage: pending | gate | reviews | fix round | filled
Gate: <command @ sha, result>; re-run after the fix round: <sha, result> · Coverage: org <n>%, new classes <Class n%, ...>
Reviewers: <role id, ...>
Reviews: test-reviewer <verdict> · brand-reviewer <verdict or n/a> · sf-security-auditor <verdict or n/a> · access-auditor <verdict or n/a>
Observed: <what differed from this document>
Design impact confirmed: no — checked: <ids>
Open findings: <none, or the list>
Pre-existing (from reviewer notes): <none, or the list>
Skills not available: <none, or the list>
Pending for the owner: human test, delivery
Next step: <next requirement, hardening, or pull request by the owner>
```

Rules for the document:

- Every acceptance criterion of the requirement appears in at least one
  Acceptance line, with its identifier. Every Acceptance line has a Mutation.
- Problems name what could go wrong, not only what is missing. Solutions name
  the alternative that was discarded and why.

## Task analysis (phase 6)

Before any worker is launched, record `Base:` in the header: the HEAD sha
before the plan commit. Close reviews the range Base..HEAD; that range also
holds the bookkeeping commits (`odd(<slug>): ...`), which only touch odd/ and
.mem/ and which reviewers ignore. Then fill the Task analysis table. For each
task:

- Solves: the S# it implements.
- Acceptance: the lines it must satisfy.
- Scope: the files and metadata it may touch. A task touches nothing else.
- Security: yes if it touches permissions, sharing, authentication, a secret,
  or a method that external users or external systems can call.
- Executor: the agent that implements it.
- Skills: the official Salesforce skills the executor must load, by full
  plugin name (for example `salesforce-development:platform-apex-generate`).
  The task-worker file has the map of work to skill.
- Reviewers: the agents that review it when it is committed.

Keep each task small: one behavior, one commit, about 400 changed lines at
most. Order the tasks so that each one leaves the tests green.

## Plan review (phase 6b)

A plan is cheap to fix; code built from a wrong plan is not. After the Task
analysis is committed (`odd(<slug>): plan`) and before the first worker:

1. Launch plan-reviewer with a Review handoff: Target is the plan commit,
   Requirement is the requirement id and the path of the design document.
2. If it returns blocking findings, the main session fixes the task document
   itself, once (the plan is its own work), commits it as
   `odd(<slug>): plan fix`, and resumes the same plan-reviewer for the
   closing check. Low findings never require a fix, but since the plan is the
   main session's own document it may apply them in the same commit.
3. Record the result on the `Plan review:` line of the header. A finding
   still open after the closing check: in Mode: auto, record it there and
   continue; in Mode: interactive, show it to the owner.
4. In Mode: interactive, show the reviewed task table and ask whether to
   start.

Hardening task documents get the same plan review.

## Execute (phase 7)

- Every tier 1 and tier 2 task runs in a task-worker subagent. The main
  session does not write production code for those tasks; it analyzes,
  launches, reads the result and ticks.
- One committing worker at a time on the shared checkout.
- The main session commits the task document and .mem/ itself, never a
  worker: after the task analysis (`odd(<slug>): plan`), and before launching
  any worker whenever they changed since the last commit
  (`odd(<slug>): <what changed>`, for example a tick or reviewer ids). So
  every worker starts on a clean tree.
- When a worker stops and returns without a commit (the scope is too small,
  the org is missing or wrong, or a deletion is needed), fix the cause in the
  task document (widen the scope, add a task, name the org) and launch it
  again; in Mode: interactive, ask first. A deletion is the owner's decision:
  in Mode: interactive, ask; in Mode: auto, take the conservative option (no
  deletion), record it as an assumption and continue.
- A subagent does not inherit the plugin's skills-first context or its org
  banner. That is why the main session, which has the plugins loaded, picks
  the skills during the task analysis and names the org and the skills in
  every handoff.
- A hook (.claude/hooks/odd_handoff_check.py) refuses to launch an ODD agent
  whose prompt lacks its handoff block, misses a required field, or leaves a
  template placeholder such as `<sha>`. When it refuses, complete the handoff
  from the task document and launch again; never work around it. A launch
  outside ODD (a probe, a question) starts its prompt with
  `Handoff-exempt: <reason>`.
- Launch each worker with a Handoff block:

```markdown
## Handoff
- Goal: <what done looks like>
- Task document: odd/tasks/<slug>.md
- Task: T# (S#)
- Decided (do not re-derive or re-open): <decisions>
- Acceptance: <the lines VERBATIM, with their *Mutation:* lines>
- Touch: <file list>
- Org: <target org alias>; never production
- Skills: <full skill names to load first>
- Do NOT read: <what the main session already digested>
- Runners: LOOP <deploy and test command for the classes in scope> · GATE <full test command>
- Return: the sha, odd/evidence/<slug>/T#.md and the skills used
```

- Runners for this project: LOOP is
  `sf project deploy start --source-dir <paths> --target-org <alias>` followed by
  `sf apex run test --class-names <TestClass> --result-format human --wait 10 --target-org <alias>`.
  GATE deploys the whole package at HEAD and runs every local test in one
  step: `sf project deploy start --source-dir force-app --test-level RunLocalTests --coverage-formatters json-summary --results-dir <tmp dir> --wait 30 --target-org <alias> --json`.

## Review (phase 8)

- After every task commit, and before ticking the task, launch task-reviewer
  (read-only) over that sha, with a Review handoff.
- Every reviewer, at every phase (task, plan, close), is launched with a
  Review handoff, so it starts from the task's data instead of from zero:

```markdown
## Review handoff
- Task document: odd/tasks/<slug>.md
- Task: T# (S#) | Plan of <slug> | Close of <slug>
- Target: <sha> (a task or the plan commit) | <Base>..<HEAD> (a close)
- Acceptance: <the lines VERBATIM, with their *Mutation:* lines>
- Scope: <the files the task may touch, or the requirement's files>
- Evidence: <odd/evidence/<slug>/T#.md, or odd/evidence/<slug>/ at Close>
- Org: <target org alias>; never production
- Skills: <the task's skills, by full name>
- Security: yes | no
- Coverage: <the gate's coverage, for test-reviewer>
- Requirement: <the requirement id and the design document path, for plan-reviewer>
- Return: <the format of the agent's Return section>
```

  Required fields: every reviewer needs Task document, Task, Target, Org and
  Return. On top of those: task-reviewer needs Acceptance, Scope, Evidence,
  Skills and Security; security-reviewer and access-auditor need Acceptance
  and Scope; test-reviewer needs Acceptance, Evidence and Coverage;
  brand-reviewer and sf-security-auditor need Scope; plan-reviewer needs
  Requirement. A fresh closing check (when the reviewer cannot be resumed)
  needs only the five common fields plus `- Findings:` with the findings
  verbatim.
- If the Task analysis marks the task Security: yes, also launch
  security-reviewer and access-auditor over the same sha. The reviewers are
  read-only, so launch them in parallel, in one message.
- If task-reviewer reports "security lens missing", launch security-reviewer
  and access-auditor over the same sha before ticking, and correct the
  Security mark in the Task analysis. That finding is never sent to a worker:
  launching the lens closes it.
- A review runs over a committed sha, never over a dirty worktree.
- Blocking findings. Judge by the findings, not by the verdict word (clean,
  APPROVED, PASS, CHANGES REQUIRED, FAIL...). A finding is blocking when it
  is Critical, High or Medium, the reviewer lists it under Findings, and this
  task or requirement caused it. Low findings and reviewer Notes never start
  a fix round: copy them to the Close section, under Observed and
  Pre-existing.
- The fix round starts only when every reviewer of the task has returned,
  including a security lens launched late.
- Every reviewer launch returns an agent id. When a reviewer returns
  findings, write its id on the task line at once, so it survives a
  compaction:
  `- [ ] T2 (S1): <task> — review: findings (task-reviewer <id>, security-reviewer <id>)`
- One reviewer per role per task.

## Fix round

- One fix round per task. Send all the blocking findings of the task, from
  every reviewer, to one task-worker in fix mode, with a Fix handoff:

```markdown
## Fix handoff
- Task document: odd/tasks/<slug>.md
- Task: T# (S#) · reviewed sha: <sha>
  (at Close: `Close of <slug>` · reviewed range: <Base>..<HEAD>)
- Findings (VERBATIM, with reviewer and severity): <list>
- Acceptance: <the task's lines VERBATIM, with their *Mutation:* lines>
  (at Close: the lines of the criteria the findings touch)
- Touch: <the task's original file list> (at Close: the requirement's files)
- Org: <target org alias>; never production
- Skills: <full skill names>
- Evidence: odd/evidence/<slug>/T#.md, append a Fix section
  (at Close: odd/evidence/<slug>/close.md)
- Runners: LOOP <deploy and test command> · GATE <full test command>
- Return: the fix sha and, for each finding, fixed, rejected (reason) or out of scope
```

- Close the round with the same reviewers, not new ones: resume each
  reviewer that reported findings with SendMessage, addressed to the id on
  the task line, and ask only whether its findings are closed at the fix sha.
  Resumed reviewers are read-only, so resume them in parallel.
- If a reviewer cannot be resumed (another session, or the id was lost),
  launch a fresh agent of the same role with a narrow brief: verify only
  these findings, verbatim, at the fix sha, and review nothing else.
- A finding the worker rejected stays open unless the reviewer accepts the
  rejection in the closing check.
- A finding the worker returned as out of scope becomes a new task in the
  same task document when this requirement caused it; otherwise it goes to
  Open findings.
- There is no second fix round. If a finding is still open after the closing
  check, do not loop. In Mode: auto, record it under Open findings in Close
  and continue. In Mode: interactive, stop and show it to the owner.

## Tick (phase 9)

    - [x] T1 (S1): <task> — <sha> · evidence: odd/evidence/<slug>/T1.md · review: clean
    - [x] T2 (S1): <task> — <sha> · evidence: odd/evidence/<slug>/T2.md · review: fixed in <sha>
    - [x] T3 (S2): <task> — <sha> · evidence: odd/evidence/<slug>/T3.md · review: fixed in <sha>, open — <finding>
    - [x] T4 (S2): <task> — <sha> · evidence: odd/evidence/<slug>/T4.md · review: open — <finding> (not resolved in the fix round)

A task is ticked only with its sha, its evidence path and its review result.
When ticking, the main session also copies each Mutation's observed red from
the evidence file into its Acceptance line (`observed:`); the task document
is the main session's, so workers never write it.
A hook (.claude/hooks/odd_tick_check.py) refuses a tick line without them,
whose commit or evidence file does not exist, or that has the tick data but
an unchecked box.

## Close and Archive (phases 10 and 11)

Close runs once per requirement, when every task of its task document is
ticked. A task review looks at one commit; Close looks at what the tasks
built together, over the range Base..HEAD.

Keep the `Stage:` line of the Close section current (gate, reviews, fix
round, filled) and commit it, so an interrupted Close can be resumed.

1. Preconditions. Every task is ticked, the task document and .mem/ are
   committed, the worktree is clean, and you record the HEAD sha.
2. Gate. Load salesforce-development:platform-metadata-deploy and run the
   GATE: the whole package deployed at HEAD, with every local test. Keep only
   the summary in the main session: pass or fail, the failing tests, and the
   coverage.
   - Coverage: the org-wide coverage must be at least 75%, and every class
     the requirement created at least 85%. Below that is a finding for
     test-reviewer.
   - If the gate is red, run one gate-fix round: a task-worker in fix mode,
     with a Close-variant Fix handoff, the failing tests verbatim as findings
     and the requirement's files as scope. Then run the gate once more. If it is still red, stop and show
     it, in both modes.
3. Requirement reviews. Launch them in parallel, in one message, over
   Base..HEAD, and write each reviewer's id on the `Reviewers:` line of the
   Close section as it returns:
   - test-reviewer, always, with the requirement scope: every acceptance
     criterion has a test that can fail, the gaps between tasks, and the
     coverage from the gate.
   - brand-reviewer, when the requirement has interface.
   - sf-security-auditor, on tier 2: the requirement's change against the
     project security policy, widened to its callers, the permissions that
     expose it, and what a guest or an external system can reach.
   - access-auditor, on tier 2: the access configuration of the real org
     against the repository at HEAD. A difference is configuration that is
     not versioned.
4. Fix round. If the reviews return blocking findings, run one fix round as
   in "Fix round": one task-worker in fix mode with a Close-variant Fix
   handoff, all the findings and the requirement's files as scope, closed by
   resuming the same reviewers. No
   second round; whatever stays open goes under Open findings in Mode: auto,
   or stops the work in Mode: interactive. After a fix round, run the gate
   again, so the gate covers the code that is archived, and record both runs
   on the Gate line.
5. Close section. Fill it: gate, coverage, review verdicts, what was
   observed, open findings, the pre-existing weaknesses from reviewer notes
   and the skills that were not available. Set `Stage: filled`. The human
   test and delivery belong to the owner: record them as pending, never as
   done.
6. Archive. Write the close entry in project memory, move the document with
   `git mv odd/tasks/<slug>.md odd/tasks/archive/<date>-<slug>.md` (`<date>`
   is today's local date from `date +%Y-%m-%d`, never the org's clock), and
   commit the document and .mem/ together as `close <slug>`.

## Hardening (phase 12, once per run)

After the last requirement is archived, the product exists as a whole, and
weaknesses that span several requirements become visible. Hardening audits
the whole product, turns the serious findings into tasks, and audits again.

1. Audit. Run the sf-security-audit skill over the whole project with
   `--org <alias>`. It runs the heuristic scanner, Code Analyzer (Security
   and AppExchange rules, and the graph engine when Java is present) and the
   three specialists in parallel: sf-security-code-reviewer,
   sf-security-access-reviewer and sf-security-exposure-reviewer. Its report
   goes to .security-reports/<run>/security-audit.md.
   - The skill asks to confirm the org before reading it. In Mode: auto, the
     confirmation is `sf org display --target-org <alias> --json` showing the
     run's org and that it is not production. Record it and do not stop.
   - The skill audits only. Its closing offer to fix is replaced by step 3.
   - Also run salesforce-code-quality:dx-code-analyzer-run over the whole
     project with the non-security rules (performance, best practices,
     error-prone). Its severity 1 and 2 violations count as High findings,
     with ids CA-###.
2. Stop check. If the audit has no Critical and no High finding (SEC or CA),
   hardening is done. It is also done after the third audit: at most 3
   audits, the first one and two re-audits, so at most two hardening task
   documents. Never run a fourth audit.
3. Triage. Every Critical and High finding becomes part of a task document
   odd/tasks/hardening-<round>.md, Tier 2, with `Reason:` naming the SEC and
   CA ids.
   Medium and Low findings go to the final report, with no tasks. A finding
   you dismiss as a false positive or a duplicate is listed in Findings with
   the reason; nothing is dropped silently.
   - Each finding becomes a Problem, a Solution, and an Acceptance line that
     reproduces the weakness as an attack, for example:
     `AC-H1.1 — Given a guest who knows a record number and a postal code,
     When they try to edit that record, Then the edit is rejected and nothing
     changes.` Its Mutation reintroduces the weakness.
   - A CA finding is not an attack: its Acceptance line states that the
     violation is gone, proved by the code analyzer or by a test, and its
     Mutation brings the violation back.
   - Cite SEC ids and path:line. Never copy secret values; the report itself
     stays in .security-reports/, which is not committed.
   - In Mode: interactive, show the triage and ask before creating the
     document.
4. Fix. Work the hardening document like any requirement: checkpoint (in
   auto for the whole run, the standing choice), task analysis with every
   task marked Security: yes, one task-worker per task, review with the
   security lens, fix round, tick, Close and archive.
5. Re-audit. Run the full audit again, over the whole project, not only the
   diff: a fix can open another hole. Then go back to the stop check.

## End of run (phase 13)

- Launch the salesforce-code-quality:architecture-review agent once over the
  whole project. If that agent is not available, run the
  salesforce-code-quality:platform-architecture-analyze skill in the main
  session instead. It is report only: no tasks are created from it
  automatically.
- Write odd/final-report.md: each requirement with its gate result and open
  findings; each hardening round with the counts by severity before and
  after, SEC and CA counted separately; the security findings still open and
  the Medium and Low ones; the pre-existing weaknesses recorded in each
  Close; the architecture verdict per pillar; the skills that were not available; and
  what is pending for the owner (human test, delivery, merge). Cite SEC ids
  and path:line, never secret values.
- Write the end of the run in project memory and commit the report and .mem/
  together as `end of run`.

## Modes

The user chooses the mode at the checkpoint. The mode changes how often the
main session stops; it never changes the spine, the reviews or the gates.

| | Mode: interactive | Mode: auto |
|---|---|---|
| After the task analysis | Show the task table and ask whether to start | Start |
| After each task | Show the tick and the evidence summary, and ask whether to continue | Chain to the next task |
| After a review finding | Show the findings and ask whether to fix or discuss | Apply the one fix round |
| When a decision is missing | Ask the user | Choose the most conservative option and record it as an assumption |
| On a red the worker cannot resolve | Stop and show it | Stop and show it |
| Before archiving | Show the Close section and ask | Archive |
| Hardening triage | Show which findings become tasks and ask | Create the hardening task document |
| Next requirement | Stop at its checkpoint | Continue, if the choice was for the whole run |
| Human test and delivery | The owner | Recorded as pending for the owner; never done by an agent |

The user can switch modes at any time by saying so. Update the Mode line and
note the change in the task document.
