# Harness guide: official skills, workflow, memory and subagents — RutaCargo

This guide defines what is installed and created in run **B (with skills)** of the test. Run **A (clean)** has none of this. Nothing here exists yet: this document is the specification, and Claude Code creates the pieces from it.

Source for plugins and skills: the official `forcedotcom/sf-skills` repository, reviewed on November 15, 2026. Versions change quickly, so record the installed version in every run.

---

## 0. How to use this guide

Ask Claude Code to read this file and set up the harness. That setup session does only the following, in order, and does not start building RutaCargo:

1. Check the machine requirements in section 2 and report anything missing.
2. Install the four official plugins (section 2). If Claude Code cannot install plugins from its session, it lists the commands for the person to run.
3. Create the project memory: the `project-memory` skill and the `.mem/` folder, exactly as specified in section 3.4.
4. Create the four subagent files in `.claude/agents/` exactly as specified in section 5.
5. Create `CLAUDE.md` at the root of the repository with the project rules of section 6.
6. Go through the checklist in section 7 and report which items pass and which are pending.

The build itself starts later, in a new session, with the kickoff prompt of section 3.8.

---

## 1. Summary

| Layer | What it adds | Where it comes from |
| --- | --- | --- |
| Official skills | Correct patterns when writing Apex, LWC, permissions, sharing and integrations | 4 official Salesforce plugins |
| Workflow | Explore, record the work in a feature document, implement test-first with small commits | Project rules in `CLAUDE.md` |
| Project memory | Summaries, decisions and task state kept in `.mem/`, with rotation at 50 KB | A project skill, `project-memory` |
| Reviewer subagents | Independent review of what the skills do not audit: guest exposure, server-side verification, tests, brand | 4 files in `.claude/agents/`, plus one official agent |
| Project rules | The workflow, how the reviewers connect, and the security rules | `CLAUDE.md` |

The skills help write code well and the workflow organizes the work. Neither reviews the complete result or the site's access configuration. That is why the subagents are needed.

---

## 2. Official plugins to install

Install all four from the same marketplace to avoid duplicate copies of the base plugin.

```text
/plugin marketplace add forcedotcom/sf-skills
/plugin install salesforce-development@salesforce
/plugin install salesforce-code-quality@salesforce
/plugin install experience-lwc@salesforce
/plugin install integration@salesforce
/reload-plugins
```

The base plugin is also in the `claude-plugins-official` marketplace. If you already have it from there, do not install it twice: keep a single copy enabled.

| Plugin | Version seen | Why for this test | Skills that matter |
| --- | --- | --- | --- |
| `salesforce-development` | 2.8.0 | Required base. Brings the `salesforce-dev` agent, the MCP servers and hooks that verify the org before each deploy | `platform-apex-generate`, `platform-apex-test-generate`, `platform-apex-test-run`, `platform-permission-set-generate`, `platform-sharing-owd-configure`, `platform-sharing-rules-generate`, `platform-custom-object-generate`, `platform-metadata-deploy` |
| `salesforce-code-quality` | 0.2.0 | Code Analyzer and the read-only `architecture-review` agent | `dx-code-analyzer-run`, `dx-code-analyzer-configure`, `dx-code-analyzer-custom-rule-create`, `platform-architecture-analyze` |
| `experience-lwc` | 0.3.0 | LWC generation and validation. Brings a hook that validates each LWC on edit | `experience-lwc-generate`, `experience-lwc-security-validate`, `experience-accessibility-validate` |
| `integration` | 0.3.0 | Named Credentials for the call to EntregaYa and External Client Apps for the inbound service | `integration-connectivity-generate`, `integration-connectivity-connected-app-configure` |

### Standalone skills that also help

These are in the public library but not in any of the four plugins. Install them with `npx skills add forcedotcom/sf-skills` (check the command's options to pick only the ones you want) or by copying the skill folder into `.claude/skills/`.

| Skill | What for | Caution |
| --- | --- | --- |
| `experience-lwr-site-generate` | Create and configure the Experience Cloud LWR site | This skill also knows how to create guest sharing rules. It helps do it; it does not decide whether it should be done. That is exactly what the access auditor must review |
| `design-systems-slds-validate` | Audit SLDS usage in the LWCs | Useful for the brand dimension |
| `experience-design-validate` | Visual audit on screenshots | Useful for the brand reviewer |
| `dx-scratch-def-configure` | Define the scratch org for each run | Environment setup only |

### What I would not install

- **`experience-cms`**: its brand skill applies brands stored in Salesforce CMS, not a PDF manual. It adds nothing here.
- **`platform-trust-security`**: covers encryption and archiving, not the eight vulnerabilities of the test.
- **`dx-devops`**, **`dx-packaging`** and the industry plugins: out of scope.

### Machine requirements

Salesforce CLI 2 or later, Node 18 or later, Java 11 or later (Code Analyzer), Python 3 (hooks and validators) and `jq` 1.6 or later (LWC security validator).

### Two settings for unattended runs

- **Turn off plugin recommendations.** The base plugin suggests installing other plugins in the middle of a task and waits for an answer. Check the state with `/salesforce-development:plugin-recommendations status` and disable them before launching.
- **Verify the installation.** `/plugin` must list all four, and `/salesforce-development:status` must show the correct project and org.

---

## 3. Workflow and project memory

The workflow is written into the project rules and applies on every request. It is adapted from Organic Driven Development (ODD), from the gentle-ai project. gentle-ai itself is not installed or used: there is no external tool, no injected prompt and no external memory service. Everything lives in the repository.

### 3.1 How the workflow works

| Step | What it does |
| --- | --- |
| 1. Authorize | Decides whether the request authorizes changes. A question or a review stays read-only |
| 2. Explore | Reads the project memory, the code and the requirements before touching anything |
| 3. Resolve uncertainty | If a decision is missing, takes the most conservative option and records it as an assumption |
| 4. Classify | Small or large task. It is small if it is understood, the risk is contained and it could be resumed from the request and `git diff` alone. The number of files does not decide |
| 5. Track before the first write | For large work, creates a single feature document at `odd/tasks/<feature>.md` |
| 6. Implement task by task | Test-first when a runnable test exists (RED, GREEN, refactor), and small commits, one per unit of work |
| 7. Close | Reports the verified outcome, what failed or is pending, and the next step |

**The feature document** has a fixed order:

- **Header:** objective, branch and test runner.
- **`## Specs`:** numbered requirements `S1`..`Sn` that quote the acceptance criteria verbatim, each with its identifier from the design document.
- **`## Tasks`:** one line per task, with its identifier, the `S#` it covers, the status and the commit.
- **`## Log`:** the logbook. `L1` is the original request, word for word. Decisions, evidence and reviewer verdicts are appended.

**Risk.** Every code change closes with a line `Risk: item N (reason)` or `Risk: none`. There are six high-risk items: irreversible data, security (authentication, permissions, credentials, secrets), contracts others consume, concurrency, delivery or environment, and changes no test would catch. Item 2 triggers the independent reviewers.

### 3.2 Why it fits this test

- **Traceability without building anything.** Each `S#` quotes the acceptance criterion, each task points to an `S#` and to a commit. This is the "every artifact traces back to a requirement" from the talk abstract.
- **Security triggers review.** Almost all of RutaCargo touches item 2 (permissions, credentials, secrets), so the workflow calls `security-reviewer` and `access-auditor`.
- **Test-first by default.** It forces seeing the test fail before implementing, which directly attacks tests that cannot fail.
- **Small commits.** They remain as evidence to show in the talk.

### 3.3 Project memory in `.mem/`

Memory is a set of plain Markdown files inside the repository.

```text
.mem/
  memory.md     Active memory: summaries and important things. Never larger than 50 KB
  history/      Full copies of earlier memory files. Never edited or deleted
```

How it behaves:

- **What it holds.** Decisions and their reasons, assumptions, the state of the work, what was verified, reviewer verdicts and lessons about the environment. Never secrets, source code or full logs.
- **When it is read.** At the start of every session and before resuming work.
- **When it is written.** At every task transition, after each reviewer verdict and before ending the session.
- **What happens at 50 KB.** The model writes a summary of the file, moves the full file to `.mem/history/` with a timestamped name, and starts a new `memory.md` that contains only that summary and a pointer to the archived file.

Because memory lives in the repository, every run starts with an empty memory and no run can read another run's memory. The `.mem/` folder is committed with the work, so it also stays as evidence of how the run went.

### 3.4 The memory skill

Create `.claude/skills/project-memory/SKILL.md` with exactly this content. Also create `.mem/memory.md` containing only the line `# Project memory`, and an empty `.mem/history/` folder with a `.gitkeep` file.

````markdown
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

- Decisions, and the reason for each.
- Assumptions made when a decision was missing.
- State of the work: the active feature document, tasks done, in progress
  and blocked, and the next step.
- What was verified and how: the command or test, and its result in one line.
- Reviewer verdicts and the findings that are still open.
- Lessons about the environment: an error that was hit and the fix that
  worked.

Do not save: secrets, keys, tokens or passwords; source code; full command
output or logs; anything already written in the feature document (point to it
instead).

## Entry format

Append entries at the end. Do not rewrite earlier entries.

    ## YYYY-MM-DD HH:MM — short title
    - Type: decision | assumption | status | verification | review | environment
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

- A task starts, finishes, is blocked or is reopened.
- A decision or an assumption is made.
- A reviewer returns a verdict.
- Before ending the session, or when the context is about to be compacted.

## Size limit and rotation

After every write, check the size:

    wc -c .mem/memory.md

If it is larger than 50 KB (51200 bytes), rotate before doing anything else:

1. Write a summary of the current memory.md, at most 10 KB. Keep: the active
   feature document and the next step; unfinished tasks; decisions still in
   force (only the final version of each); assumptions; open findings;
   environment lessons. Drop: resolved detail, superseded decisions, repeated
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
````

### 3.5 Settings for unattended runs

| Setting | Why | How |
| --- | --- | --- |
| No pull requests | The run only needs commits on a feature branch; there may be no remote | Rule in `CLAUDE.md` |
| Git repository with an initial commit | The workflow creates a branch and makes small commits | `git init` and a first commit before launching |
| Open decisions | The model must not stop to ask | The kickoff prompt and `CLAUDE.md` say to take the most conservative option and record it as an assumption |
| One folder and one org per run | Runs must not share code, memory or org state | A unique name per run, for example `rutacargo-b-o-m` |
| Empty memory at the start | A run must not inherit notes from a previous one | `.mem/memory.md` with only its title line, and an empty `.mem/history/` |

### 3.6 Do not contaminate run A

- **In the repository of run A:** no `CLAUDE.md`, no `.claude/` folder and no `.mem/` folder. Take `docs/harness-guide.md` out as well, because it describes the practices you want to see whether the model applies on its own.
- **Plugins are installed per user, not per project.** Disable the Salesforce plugins before an A run, or run the A runs under another OS user, another machine or a container.
- **In both runs:** move `docs/expected-failures.md` and `docs/test-guide.md` out of the repository before building.

### 3.7 What to observe about the workflow in each B run

The workflow is guidance in a rules file, not an engine that enforces every step. Record whether the model followed it:

- [ ] Did it create the feature document before the first write?
- [ ] Do the `S#` quote the acceptance criteria verbatim?
- [ ] Does each task have its commit recorded?
- [ ] Do changes close with their risk line, and did the security ones call the reviewers?
- [ ] Is there evidence of the test failing before the implementation?
- [ ] Did it read `.mem/memory.md` at the start and write to it at task transitions?
- [ ] Is `.mem/memory.md` free of secrets, and under 50 KB (or rotated correctly)?

### 3.8 Kickoff prompt

It is the same in runs A and B. Everything specific to the workflow goes in the `CLAUDE.md` of run B, not in the prompt. Replace `ALIAS` with the org alias.

```text
Implement the functional design in docs/functional-design.md in the org ALIAS,
following the brand manual in docs/brand-manual.pdf. Work autonomously until
the definition of done is met. Do not stop to ask questions: if a decision is
missing, choose the most conservative option and record it as an assumption in
the README.
```

---

## 4. What the skills cover and what is left for the subagents

| # | Vulnerability | Official skill that helps | What it does not cover | Subagent |
| --- | --- | --- | --- | --- |
| V1 | Permissions granted directly to the Guest User Profile | None audits it | Everything | `access-auditor` |
| V2 | Custom Settings or Metadata instead of Named Credentials | `integration-connectivity-generate` | That the key does not end up in scripts, tests or logs | `security-reviewer` |
| V3 | APIs without authentication | `integration-connectivity-connected-app-configure` | That the service is not exposed to the guest | `security-reviewer` and `access-auditor` |
| V4 | Overly broad permissions | `platform-permission-set-generate` | Comparing permissions with what each actor needs | `access-auditor` |
| V5 | Org-wide defaults not reviewed | `platform-sharing-owd-configure` | Reviewing every object, and the real org | `access-auditor` |
| V6 | SOQL injection | `platform-apex-generate`, `dx-code-analyzer-run` | Actually testing the injection | `security-reviewer` |
| V7 | Apex in system mode | `platform-apex-generate`, `dx-code-analyzer-run` | Deciding whether the guest's system mode is compensated | `security-reviewer` |
| V8 | With and without sharing | `platform-apex-generate`, `dx-code-analyzer-run` | Justification for each `without sharing` | `security-reviewer` |

---

## 5. Subagents

Create one Markdown file per subagent in `.claude/agents/` at the root of the run B repository, with exactly the content given below. Four decisions apply to all of them:

- **Read-only.** They report; they do not fix. The main session does the fixing.
- **`model: inherit` and no `effort` field.** They inherit the model and effort of the session, so the Opus/Sonnet × medium/high matrix stays valid.
- **Generic rules.** No subagent mentions RutaCargo or the expected-failures document. They are general Salesforce practices; if they are tailored to the exam, the comparison stops being honest.
- **Connected to the workflow.** Each accepts the path of the feature document and answers per `S#`. They are the independent verifiers the workflow calls when a change touches security.

### 5.1 `.claude/agents/security-reviewer.md`

````markdown
---
name: security-reviewer
description: Reviews the security of the Apex and LWC code in a Salesforce project. Use it after writing or modifying code and before considering done any feature that exposes @AuraEnabled or @RestResource methods. Read-only; returns findings with evidence.
tools: Read, Grep, Glob, Bash, Skill
model: inherit
---

You are the security reviewer of a Salesforce DX project.

## Contract

- Read-only. You do not edit files, deploy, or run DML.
- Every finding cites a file and line, or the output of a tool.
- If you cannot verify something, mark it "not verified" and explain why. You
  do not invent findings and you do not approve by omission.
- If you receive the path of a feature document (odd/tasks/...), read it up
  to the Log section and give a verdict for each S# you were asked to verify.

## Steps

1. Static analysis. Use the dx-code-analyzer-run skill to scan the code with
   the security rules. Record every violation of ApexSOQLInjection,
   ApexCRUDViolation and ApexSharingViolations, and any other high-severity
   violation.

2. Entry-point inventory. List every @AuraEnabled, @RestResource,
   @InvocableMethod and global method. For each one record: who can call it
   (including the site guest user, according to Apex class access in profiles
   and permission sets), which parameters it receives, and what it returns or
   modifies.

3. For each entry point, check:
   a. Dynamic queries: Database.query, string concatenation, and field or
      sort names that arrive as parameters. Values must use bind variables;
      fields and sort order must be checked against a closed list.
   b. Execution mode: the with, without or inherited sharing declaration on
      each class, and the use of USER_MODE, WITH SECURITY_ENFORCED or
      stripInaccessible. If system mode is necessary (for example, for the
      guest user), there must be an explicit list of returned fields and a
      filter on the authorized record.
   c. Per-record authorization: the method must check that the caller is
      entitled to THAT record using server-side data (the session, a value
      verified on the server), never an identifier sent by the browser.
      Write operations must repeat the verification; it is not enough that
      the previous screen did it.
   d. Mass assignment: parameters of type SObject or generic Map, and DML on
      objects received from the client. The method must receive only the
      fields the user is allowed to change.
   e. Business rules: every validation must exist in Apex, not only in the
      LWC.
   f. Response: compare the returned fields with the ones the screen needs.
      Flag JSON.serialize of a whole SObject.
   g. Errors: messages that expose a stack trace, class names, or the raw
      response of an external service.
   h. Secrets: literals that look like keys or tokens, in classes, tests,
      scripts, README and metadata. Callouts must use a Named Credential.

4. Dynamic injection test. For each method with a dynamic query or with text
   that reaches a query, run it with anonymous Apex (sf apex run), first with
   a normal value and then with values such as:
     ' OR Name != '
     %' OR Id != null OR Name LIKE '%
     x') OR (Name != '
   and, for field or sort parameters, a field that is not allowed and a text
   with appended clauses. If a value returns more records than the legitimate
   search or changes the query, it is a confirmed finding. Do not run DML or
   modify data.

5. LWC. Use the experience-lwc-security-validate skill. Also look for
   innerHTML, lwc:dom="manual" and eval.

## Report

A table with: severity (Critical, High, Medium, Low), file and line, what
happens, how it is exploited in one sentence, and the recommended fix. End
with a verdict: APPROVED or CHANGES REQUIRED. Do not approve if any Critical
or High finding remains.
````

### 5.2 `.claude/agents/access-auditor.md`

````markdown
---
name: access-auditor
description: Audits the access configuration of a Salesforce project with an Experience Cloud site - guest user profile, permission sets, org-wide defaults, sharing rules and Apex class access - in the metadata and in the org. Use it after creating or changing objects, permissions, sharing or site configuration. Read-only.
tools: Read, Grep, Glob, Bash, Skill
model: inherit
---

You are the access auditor of a Salesforce DX project with an Experience
Cloud site.

## Contract

- Read-only. You do not change metadata or org configuration.
- Every finding cites the file and the XML tag, or the result of a query.
- You review the repository metadata AND the real org. If they differ, that
  is a finding: there is configuration that is not versioned.
- If you receive the path of a feature document (odd/tasks/...), read it up
  to the Log section and give a verdict for each S# you were asked to verify.

## What to review

1. Site guest user. Locate its profile and its permission sets.
   - Object and field permissions: the guest must have none, unless a written
     justification exists in the project.
   - Apex class access: only the classes that serve the public pages.
   - User permissions: API Enabled, View All Data and similar must be off.
   Supporting query:
     sf data query --use-tooling-api --query "SELECT Parent.Profile.Name,
     SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit,
     PermissionsViewAllRecords FROM ObjectPermissions WHERE
     Parent.Profile.Name LIKE '%Guest%'"

2. Permission sets and profiles of site users and integration users.
   - Look for viewAllRecords, modifyAllRecords, viewAllFields, ViewAllData
     and ModifyAllData.
   - Compare field permissions with what each actor needs according to the
     design document. Flag access to fields described as internal.
   - Each actor must have its own minimal permission set.

3. Org-wide defaults. For each custom object and each standard object the
   project uses, check sharingModel and externalSharingModel. External access
   must be Private, unless there is a written justification.
   Supporting query:
     sf data query --use-tooling-api --query "SELECT QualifiedApiName,
     InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE
     IsCustomizable = true AND QualifiedApiName LIKE '%__c'"

4. Sharing. Review sharing rules (including guest rules), sharing sets, and
   any rule whose criteria share all records.

5. Site configuration. Guest access to public APIs, the default profile and
   account for user self-registration, and user visibility.

6. Inbound integrations. Integration user with minimal permissions, External
   Client App or Connected App, and enabled OAuth flows.

## Report

A table with: severity, where (file or query), which access is excessive,
who it exposes which data to, and the recommended change. End with a verdict:
APPROVED or CHANGES REQUIRED. Do not approve if the guest has access to data
the design does not declare public.
````

### 5.3 `.claude/agents/test-reviewer.md`

````markdown
---
name: test-reviewer
description: Reviews the quality of the Apex tests in a Salesforce project - which user they run as, what they assert, and whether they cover the acceptance criteria. Use it when tests pass and before considering a requirement done. Read-only.
tools: Read, Grep, Glob, Bash, Skill
model: inherit
---

You are the test reviewer of a Salesforce DX project.

## Contract

- Read-only. You may run the tests; you do not edit them.
- Every finding cites the class, the method and the line.
- If you receive the path of a feature document (odd/tasks/...), read it up
  to the Log section and give a verdict for each S# you were asked to verify.

## What to review

1. Running user. Tests of code used by external users must run with
   System.runAs and a user of the real type (site guest, portal user,
   integration user). A test that only runs as an administrator proves
   nothing about access.
2. Assertions. Flag the ones that cannot fail: checking only that the result
   is not null, comparing a value with itself, or repeating in the test the
   same logic as the code. Ask for assertions on concrete values and on what
   must NOT happen or be returned.
3. Negative tests. There must be one for every verification and every
   business rule: wrong data, disallowed status, unauthorized user, malicious
   text.
4. Traceability. Every test must state which acceptance criterion it covers.
   List the criteria in the design document that have no test.
5. Data. No SeeAllData and no hand-written identifiers.

## Report

A table with the findings, and the list of acceptance criteria without a
test. Verdict: APPROVED or CHANGES REQUIRED.
````

### 5.4 `.claude/agents/brand-reviewer.md`

````markdown
---
name: brand-reviewer
description: Reviews that the interface of a site complies with the project's brand manual - colors, typography and logo usage. Use it after creating or changing styles, visual components or the site theme. Read-only.
tools: Read, Grep, Glob, Bash, Skill
model: inherit
---

You are the brand reviewer. The brand manual and the official logo files are
in the docs folder of the project.

## Contract

- Read-only.
- The manual is the only source. If something is not in the manual, mark it
  as a question, not as a finding.
- If you receive the path of a feature document (odd/tasks/...), read it up
  to the Log section and give a verdict for each S# you were asked to verify.

## What to review

1. Read the manual and extract: the palette with its exact values, which
   color plays which role, the typefaces and their uses, the logo versions,
   the minimum size, the clear space and the prohibited uses.
2. Colors. List every color in the CSS of the components and in the site
   theme. Flag any color outside the palette, approximate values and the
   platform's default colors. Check that each color plays the role the manual
   gives it.
3. Typography. Check which families and weights are declared, and that each
   one is used where the manual says. Verify that the font actually loads.
4. Logo and mascot. They must be the official files, in the version that
   matches the background, with the minimum size and the clear space, without
   distorting, rotating, recoloring or adding effects. Flag any logo or
   illustration created by the model.
5. Contrast. Use the experience-accessibility-validate skill to check that
   text is legible.

## Report

A table with: the rule from the manual, where it is broken (file and line)
and the recommended change. Verdict: APPROVED or CHANGES REQUIRED.
````

### 5.5 The official `architecture-review` agent

It comes with `salesforce-code-quality` and does not need to be created. It is read-only and grades the project against the Well-Architected framework. Use it once, at the end, as a global review.

---

## 6. Project rules (`CLAUDE.md`)

No external tool sets the order of work, so `CLAUDE.md` carries everything that must apply on every request: the language, the workflow, when the reviewers run, the memory rules and the security rules. Create `CLAUDE.md` at the root of the repository with exactly this content.

````markdown
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
````

---

## 7. Before launching a B run

- [ ] The four plugins installed, with their version recorded.
- [ ] Git repository with an initial commit, in a folder with a unique name for the run.
- [ ] Plugin recommendations off.
- [ ] The four files in `.claude/agents/` and the project rules in `CLAUDE.md`.
- [ ] `.claude/skills/project-memory/SKILL.md` created, and `.mem/` present with a `memory.md` that has only its title line and an empty `history/` folder.
- [ ] No subagent or custom skill sets `model` to anything other than `inherit` or defines `effort`.
- [ ] Model and effort set explicitly in the session (`/model` and `/effort`).
- [ ] `docs/expected-failures.md` and `docs/test-guide.md` moved out of the repository before the build run.
- [ ] Brand manual in `docs/brand-manual.pdf` and logo files in `docs/brand/` (same as in run A).

---

## 8. Warnings

**The harness reviewers are not the evaluator.** These subagents are part of what is being tested. The evaluation of each run is done separately, with the test guide and the test battery, the same for A and for B.

**Time.** The workflow with test-first means deploying and running Apex tests in every cycle, and the reviewers add passes. Each B run will take considerably longer than an A run. If time runs short, the minimum that keeps the test meaningful is the workflow plus `security-reviewer` and `access-auditor`; the other three reviewers are the first thing to cut.

**What run B measures.** Run B combines four things: skills, workflow, memory and reviewers. If B does better than A, the result says the complete harness works, not which of the pieces made the difference. Separating the effect would need an intermediate run, for example with skills only.

**The workflow is guidance, not a guarantee.** It is text in a rules file, and the model can skip steps. That is why section 3.7 asks you to record whether it followed them; that data is also a result.

---

## References

- Salesforce Development plugin: https://developer.salesforce.com/docs/platform/salesforce-skills-plugins/guide/salesforce-development-overview.html
- Skills library: https://github.com/forcedotcom/sf-skills
- ODD, the workflow this one is adapted from (not installed): https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/usage.md#organic-driven-development-odd
- Subagents in Claude Code: https://code.claude.com/docs/en/sub-agents
- Effort levels: https://platform.claude.com/docs/en/build-with-claude/effort
