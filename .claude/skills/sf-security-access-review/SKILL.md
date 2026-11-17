---
name: sf-security-access-review
description: "Least-privilege review of Salesforce access control: organization-wide defaults (internal and external sharing model), sharing rules, role hierarchy access, profiles, permission sets, permission set groups and muting, object permissions (View All / Modify All / View All Fields), field-level security on sensitive fields, Modify All Data / View All Data and other admin-level system permissions, and the number of admin users. Works on source metadata and, with an org alias, on live assignments. TRIGGER when reviewing .profile-meta.xml, .permissionset-meta.xml, .permissionsetgroup-meta.xml, .object-meta.xml sharingModel, .sharingRules-meta.xml, or when asked who can see/edit data, whether access follows least privilege, or how many admins exist. DO NOT TRIGGER for guest/site exposure or credentials (sf-security-exposure-review) or Apex code review (sf-security-code-review)."
---

# Salesforce access-control review (least privilege)

Policy: `.claude/skills/sf-security-audit/references/security-policy.md` — this skill owns **P3, P4, P5, P6,
P7, X11** (and guest-profile permissions together with the exposure reviewer for P1).
Finding format & severity: `.claude/skills/sf-security-audit/references/severity-and-report.md`.
Org queries: `.claude/skills/sf-security-audit/references/org-audit-queries.md`.

## Inputs
- Source: `force-app/**/profiles`, `permissionsets`, `permissionsetgroups`, `mutingpermissionsets`,
  `objects/*/*.object-meta.xml`, `sharingRules`, `customPermissions`, `roles`.
- Retrieved org metadata (if provided) — same layout under `<RUN>/org/metadata`.
- Caveat: a retrieved **Profile** only contains object/field permissions for components that were also in the
  manifest. "No View All in profile X" is only proven for the objects that were retrieved.

## Procedure

### P3 — Org-wide defaults
For every `*.object-meta.xml` (skip `__mdt`, custom settings, `__e`):
- `sharingModel` (internal) and `externalSharingModel` must be `Private` (or `ControlledByParent`).
  Anything else needs evidence that **every** user needs the data **and** it contains nothing private —
  read the object's fields to judge (PII, financial, notes, attachments → not public).
- Public **external** OWD on any object with customer data → High (Critical if guest can read it too).
- Sharing rules to `allInternalUsers` / `allPartnerUsers` / `allCustomerPortalUsers` make the OWD effectively
  public — same bar. Owner-based rules from a role to a broad group deserve the same question.
- Custom objects with `Grant Access Using Hierarchies` disabled: confirm intentional.

### P4 — Field-level security
- Build a matrix for sensitive fields (names/descriptions suggesting PII, financial, health, credentials,
  or fields marked with data classification `securityClassification`/`complianceGroup`):
  field → which permission sets/profiles grant read/edit.
- FLS granted in profiles (other than admin) → Low (move to permission sets).
- `viewAllFields` on objects → Medium (bypasses FLS for reads).
- Editable access to fields that drive authorization/approval (Status, Approved__c, OwnerId-like lookups,
  Amount) for users who shouldn't change them → Medium.

### P5 — View All / Modify All on objects
`viewAllRecords` / `modifyAllRecords` in any non-admin profile or permission set → High. Recommend sharing
rules, teams, territory, or Apex managed sharing. With an org, count assignees for each offending set.

### P6 — MAD / VAD and admin-level system permissions
- `ModifyAllData` / `ViewAllData` anywhere except the System Administrator profile → Critical.
- Also High: `ModifyMetadata`, `CustomizeApplication`, `AuthorApex`, `ManageUsers`, `AssignPermissionSets`,
  `ManageProfilesPermissionsets`, `ManageSharing`, `ViewEncryptedData`, `ManageEncryptionKeys`,
  `BypassMFAForUiLogins`, `QueryAllFiles`, `ManageNamedCredentials` in non-admin sets.
- Permission set **groups**: the effective set is the union of members minus muting — resolve it before
  judging.
- Custom permissions that gate `without sharing` Apex (`FeatureManagement.checkPermission`) are
  privileged — list who gets them.

### P7 — Admin count (needs org)
Run the P6/P7 queries. Report: number of active users with admin-level access (profile + permission set),
ratio to active internal users, dormant admins (90 days), integration users on the System Administrator
profile (should be Minimum Access – API Only + scoped permission sets), shared/generic admin usernames.
Without an org, mark P7 "Not verifiable from source" and give the exact queries.

### X11 — External users
Partner/customer community profiles and permission sets get the same P3–P6 checks; also `ViewAllUsers`,
sharing sets, and the default profile for self-registration (CustomSite/Network metadata).

## Output
Findings in the standard format with IDs `ACC-###`, plus a **least-privilege matrix** appendix:

| Permission set / profile | Assignees (org) | MAD/VAD | Admin-level perms | View/Modify All objects | Sensitive FLS |
|---|---|---|---|---|---|

## Remediation guidance
Generate corrected permission sets with the `salesforce-development:platform-permission-set-generate` skill (permission sets over
profiles, minimal object/field grants). Change OWDs with `salesforce-development:platform-sharing-owd-configure`, replace broad access
with targeted rules via `salesforce-development:platform-sharing-rules-generate`. Warn that tightening OWD triggers sharing
recalculation and can break users — propose a test plan with realistic permission sets.
