---
description: Start or resume work with ODD - a requirement, the whole design, hardening, or simply the next step
argument-hint: [<requirement or description> | hardening] [Org: <alias> | new scratch] [Mode: interactive | auto]
---

Start or resume ODD for: $ARGUMENTS

1. Load the odd and project-memory skills, and read .mem/memory.md in full.
2. Find the org: the `Org:` in the arguments, otherwise the one in project
   memory or in the active task document. If there is none, ask in Mode:
   interactive or when the mode is not known yet; in Mode: auto, stop and
   report it.
   - `Org: new scratch` creates a new scratch org for the run, from the
     default Dev Hub, with config/project-scratch-def.json (use the
     salesforce-development:dx-org-manage skill, or
     `sf org create scratch -f config/project-scratch-def.json -a <alias> -y 30 -w 15`).
     Scratch features can only be enabled when the org is created: before
     creating it, read the design and check that the definition enables
     every feature it needs (for example Communities and the site settings
     for an Experience Cloud site). If one is missing, add it to the
     definition first as a tier 0 change, and record it as an assumption.
     Before creating it, create every package directory listed in
     sfdx-project.json (`mkdir -p force-app/main/default`): git keeps no
     empty folders, and the create command fails without them.
     Record the new alias in project memory.
   - Verify the org: `sf org display --target-org <alias> --json` for its
     username and connection, and `sf org list --json` to read whether it is
     a scratch org or a sandbox (`isScratch`, `isSandbox`). Confirm it is not
     a production org.
   - Set it as the project's local default org:
     `sf config set target-org <alias>` (local and git-ignored). The plugin's
     deploy gate refuses deploys when there is no default org, even with
     `--target-org`.
3. Find where the work stands, and resume at the first step that applies:
   - A task document in odd/tasks/ (not archive/) for this work:
     - a task line with `review: findings (...)` and no tick: resume the fix
       round, or its closing check if the fix is already committed. If a
       reviewer id cannot be resumed, use the narrow fallback of the odd
       skill;
     - the Task analysis is filled and the `Plan review:` line is empty:
       resume at the plan review;
     - an unticked task: resume from it;
     - every task ticked: resume Close at its `Stage:` line (pending: the
       gate; gate or reviews: the requirement reviews, resuming reviewers by
       the ids on the `Reviewers:` line; fix round: its closing check;
       filled: ask before archiving in Mode: interactive, archive in Mode:
       auto);
     Keep the mode recorded in the document's header.
   - "hardening" in the arguments, or every requirement archived and no
     hardening done yet: start or resume Hardening, at the round project
     memory records.
   - odd/final-report.md already exists: report that the run is finished
     and stop.
   - No arguments: continue with the next step that project memory records.
4. Otherwise, start new work: follow "Starting work" in the odd skill (read,
   explore, Problems and Solutions, classify), then stop at the checkpoint
   to ask for the approval and for the mode, unless the arguments already
   state them. "Mode: auto, unattended" pre-approves the checkpoint.
5. Write to project memory what you resumed or started, the org and the
   mode.
