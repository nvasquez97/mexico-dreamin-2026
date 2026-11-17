# foundation — Close evidence

## Fix - 58e8ba6

- Reviewed range: 18a2aa5..e6084ee · fix commit: 58e8ba6 (`close fix foundation: ...`)
- Org: cargo-opus-t1 (scratch, `sf org list` isScratch=true, 00DEk00000qop2zMAA); never production
- Skills: not available - the Skill tool returns "Unknown skill" for plugin skills
  (`salesforce-development:platform-apex-test-generate` tried 2026-11-17). Each SKILL.md
  was read from ~/.claude/plugins/cache/salesforce/... and followed:
  salesforce-development:platform-apex-test-generate (runAs tests, Assert with messages),
  salesforce-development:platform-apex-test-run (LOOP runs), salesforce-development:platform-metadata-deploy
  (scoped deploys, GATE), salesforce-development:platform-soql-query (FieldDefinition,
  FieldPermissions, PermissionSetAssignment queries), salesforce-development:platform-metadata-retrieve
  (Settings:Apex retrieve in schema-check.sh), experience-lwc:experience-lwc-generate (rcHeader),
  experience-lwc:experience-lwc-accessibility-jest-run (standalone Sa11y Jest; its assets/ folder is
  missing from the cache, so the module-level `setup()` of the @sa11y/jest README was used),
  experience-lwc:experience-accessibility-validate (alt text, names, contrast),
  salesforce-code-quality:dx-code-analyzer-run (scan), and
  ~/.claude/plugins/marketplaces/salesforce/skills/experience-lwr-site-generate/SKILL.md with
  references configure-content-brandingSet.md and configure-content-themeLayout.md.
  Conflict noted: that skill asks for the `execute_metadata_action` MCP tool, which is not
  available; the existing content.json files were edited in place (Purpose B, editing).
- Temporary mutations deployed outside the commit's files (DeliveryAccessCode.cls,
  Shipment__c.object-meta.xml, Estimated_Delivery__c, Apex.settings-meta.xml,
  RutaCargo Profile) were each reverted in source and redeployed; the GATE below redeployed
  force-app at the committed state.

### Finding 1 — test-reviewer [High] AC-F.6: no repeatable check of field history and Apex settings — fixed

- `ShipmentSchemaTest.fieldHistory_isTrackedOnStatusEstimatedDeliveryAndInstructions`: runs as a
  Standard Platform User with RutaCargo_Support_Agent (Apex sees FieldDefinition rows only for
  fields with FLS) and asserts the map {Delivery_Instructions__c, Estimated_Delivery__c,
  Status__c} = true. The out-of-date comment ("field permissions arrive with task T3") is replaced.
- New `scripts/checks/schema-check.sh`: Tooling FieldDefinition history (3 fields),
  EntityDefinition sharing models, and a retrieve of Settings:Apex (enableGaplessTestAutoNum).
- First run: green (the org was right; the gap was the missing repeatable check), so proven by mutation.
- Mutation (acceptance line): trackHistory false on Estimated_Delivery__c, deployed:
  ```
  ShipmentSchemaTest.fieldHistory_isTrackedOnStatusEstimatedDeliveryAndInstructions  Fail     System.AssertException: Assertion Failed: Status__c, Estimated_Delivery__c and Delivery_Instructions__c must be history tracked: Expected: {Delivery_Instructions__c=true, Estimated_Delivery__c=true, Status__c=true}, Actual: {Delivery_Instructions__c=true, Estimated_Delivery__c=false, Status__c=true}
  ```
  ```
  FAIL: Shipment__c.Estimated_Delivery__c IsFieldHistoryTracked is 'false', expected true
  info: 2 of 3 fields history tracked
  schema-check: 1 violation(s) in cargo-opus-t1
  ```
- Mutation (sharing test, asked by the finding): Shipment__c sharingModel Private → Read, deployed:
  ```
  ShipmentSchemaTest.sharingModels_arePrivateForShipmentAndAccount  Fail     System.AssertException: Assertion Failed: Shipment__c internal sharing must be Private: Expected: Private, Actual: Read
  ```
  ```
  FAIL: Shipment__c InternalSharingModel is 'Read', expected Private
  schema-check: 1 violation(s) in cargo-opus-t1
  ```
- Mutation (Apex settings): enableGaplessTestAutoNum false, deployed (the OWD revert was still
  recalculating, hence its line):
  ```
  FAIL: Shipment__c InternalSharingModel is 'Read', expected Private
  FAIL: Settings:Apex enableGaplessTestAutoNum is 'false', expected true
  schema-check: 2 violation(s) in cargo-opus-t1
  ```
  All three reverted and redeployed; EntityDefinition back to Private/Private; schema-check passed.

### Finding 2 — test-reviewer [Medium] AC-F.17: verify never run as a user without access — fixed

- `verify_returnsTrue_asTheAgent_forSharedShipmentsTheyDoNotOwn`: A and B owned by the test admin,
  shared with the agent by a manual Edit share, codes reissued by the agent; runAs agent → true, true;
  asserts the agent owns neither.
- `verify_returnsFalse_asAUserWithoutAShare_withTheSameHashWork`: runAs the reader (Read on
  Shipment__c, no share on A or B) with A's and B's own codes → false, false; hashesComputed +2
  (one per call, as on a shared shipment).
- First run: green (the class behaves as documented). Proven by mutation of DeliveryAccessCode:
  `with sharing` → `without sharing` (only the new test caught it; 45 tests ran):
  ```
  DeliveryAccessCodeTest.verify_returnsFalse_asAUserWithoutAShare_withTheSameHashWork                  Fail     System.AssertException: Assertion Failed: A user without a share on A must not verify A's own code
  ```
  Stronger variant for the positive test: `WITH SYSTEM_MODE` → `WITH USER_MODE` in verify — 9 tests red, including:
  ```
  DeliveryAccessCodeTest.verify_returnsTrue_asTheAgent_forSharedShipmentsTheyDoNotOwn                  Fail     System.QueryException: No such column 'Delivery_Access_Code_Hash__c' on entity 'Shipment__c'. ...
  ```
  Both reverted and redeployed. DeliveryAccessCode.cls is unchanged by the commit, so the AC-F.17
  acceptance mutation (compare against any shipment's hash) needed no re-run.

### Finding 3 — test-reviewer [Medium] AC-F.10: no Sa11y tests — fixed

- `npm install --save-dev @sa11y/jest@^8.3.1` (package.json, package-lock.json). Each test file
  calls `setup()` in beforeAll. New rcHeader.accessibility.test.js and rcHome.accessibility.test.js:
  `await expect(element).toBeAccessible()`.
- jest.config.js: `globals["lwc-jest"].nativeShadow = true`. Reason, from a red that did not
  happen: with the preset's synthetic shadow, removing the full logo's alt still passed
  (`✓ ... no Sa11y (axe WCAG A/AA) violations`); a debug run showed axe evaluated 1 of the 2 <img>
  (`v 0 p 1`), while the same markup in plain DOM gave `v=1`. With native shadow DOM axe walks the tree.
- Mutation rcHeader (alt of logo-negative.png removed):
  ```
  ✕ AC-F.10: the rendered header has no Sa11y (axe WCAG A/AA) violations (31 ms)
  Expected: no accessibility violations
      (1) [image-alt] Ensure <img> elements have alternative text or a role of none or presentation
  ```
- Mutation rcHome: `aria-labelledby` pointing at a missing id is not reported by the base preset
  (green); the misspelling `aria-labeledby` is:
  ```
  ✕ AC-F.10: the rendered home hero has no Sa11y (axe WCAG A/AA) violations (25 ms)
  Expected: no accessibility violations
      (1) [aria-valid-attr] Ensure attributes that begin with aria- are valid ARIA attributes
  ```
- Green: `Test Suites: 4 passed, 4 total` · `Tests: 17 passed, 17 total` (existing tests unchanged in
  behavior under native shadow).

### Finding 4 — brand-reviewer [High] logo below the 360 px minimum — fixed

- rcHeader (A14 decision): below 30em (480 px) `isotype-tinto.png` 3rem high on an #016BFA tile; from
  30em `logo-negative.png` at `width: 360px` on the night-blue header (360 x 190 px). alt
  "Coffee Blazers Summit" on both; only one is displayed at a time.
- brand-check.sh section 12 (new) parses the component CSS per breakpoint for every <img> that shows a
  full logo. Before (HEAD source, new check):
  ```
  FAIL: rcHeader: logo-negative.png at every width: 91 px wide, below 360 px
  FAIL: rcHeader: logo-negative.png at min-width 768px: 121 px wide, below 360 px
  ```
  After: `ok: rcHeader: logo-negative.png is never below 360 px wide (min-width 480px: 360 px)`.
  Mutations: `width: 300px` → `FAIL: rcHeader: logo-negative.png at min-width 480px: 300 px wide, below 360 px`;
  `max-width: 100%` added → `FAIL: ... max-width '100%' can shrink it below 360 px`.

### Finding 5 — brand-reviewer [Medium] tricolor as state background — fixed

- _DestructiveColor #0D1F5F (hover #016BFA, 2-3 #0D1F5F, foreground #FFFFFF); _WarningColor #D6E0EA
  (1 #D6E0EA, 2 #016BFA, 3 #0D1F5F; foregrounds #0D1F5F, #0D1F5F, #FFFFFF, #FFFFFF). Contrast:
  #FFFFFF on #0D1F5F 15.24:1, #FFFFFF on #016BFA 4.68:1, #0D1F5F on #D6E0EA 11.40:1 (all AA).
  State is not color-only: DXP alerts and buttons keep their icon and text (A14).
- brand-check.sh section 9. Before: `FAIL: branding set uses tricolor #FF3636 for _DestructiveColor ...`
  and `... #FFC91D for _WarningColor ...`. Mutations: `_WarningColor` back to #FFC91D →
  `FAIL: branding set uses tricolor #FFC91D for _WarningColor (manual p.6: never a background or state color)`;
  `background-color: #ff3636` in rcHome.css → `FAIL: CSS paints a background with tricolor #FF3636 in: force-app/main/default/lwc/rcHome/rcHome.css`.
- Live after publish: `--dxp-g-destructive:#0D1F5F`, `--dxp-g-warning:#D6E0EA`.

### Finding 6 — brand-reviewer [Medium] #EFF0F2 band around header and footer — fixed

- Source of the gray: the published scopedHeaderAndFooter view sets
  `.community_byo-scoped-header-and-footer__header-content {background-color: rgb(239, 240, 242)}`
  (and `__footer-content`). The community_layout:section always renders its
  `background-image-overlay` div (absolute, full size, `background-color: var(--dxp-c-section-image-overlay-color)`),
  so the header and footer sections' `backgroundImageOverlay` is set to #0D1F5F (was rgba(0,0,0,0)).
- brand-check.sh section 11. Before: `FAIL: theme header band sections have background 'RGBA(0,0,0,0)' ...`
  (and footer). After: `ok: theme header band ... (#0D1F5F)`, footer likewise. Mutation (header
  overlay back to rgba(0,0,0,0)) → `FAIL: theme header band sections have background 'RGBA(0,0,0,0)', expected #0D1F5F or #FFFFFF over the platform's gray`.
- Live: the published scopedHeaderAndFooter_view carries `backgroundImageOverlay:"#0D1F5F"` twice.

### Finding 7 — brand-reviewer [Low] derived shades off the palette — fixed

- _BackgroundColor2/3 #D6E0EA; _InfoColor1 #016BFA, 2-3 #0D1F5F; _NeutralColor1-2 #D6E0EA, 3 #016BFA
  (foreground #FFFFFF, 4.68:1); _PrimaryAccentColor1 (hover) and 3 #0D1F5F; _TextColor1-3 #0D1F5F;
  _DestructiveForegroundColor #FFFFFF.
- brand-check.sh section 10. Before: `FAIL: branding set colors off the palette: _BackgroundColor2=#B3C2D3, ... (25 values)`.
  Mutation `_PrimaryAccentColor1` #0157CC → `FAIL: branding set colors off the palette: _PrimaryAccentColor1=#0157CC`.
- Not changed (not named by the finding): _Success* (#4bca81 ...) and _Offline* (#444444 ...); the
  check skips them explicitly and says so in its output, for the owner (A14).

### Finding 8 — test-reviewer [Low] SupportAgentAccessTest:197-202 — fixed

- Structural proof (grep), before: no `codes.size()` or `Status__c` assertion; after:
  `Assert.areEqual(2, codes.size(), ...)`, `Assert.areEqual('Requested', created.get(rows[0].Id).Status__c, ...)`
  and the same for rows[1]. Green in the 75-test run.

### Finding 9 — access-auditor [Low] ACC-001 credit-field holders — fixed

- shipment-access-check.sh section 7: every profile or permission set with Read on
  Account.Credit_Limit__c, Credit_Risk__c or Customer_Type__c, except RutaCargo_Support_Agent and
  System Administrator, must have 0 assignees (active or not). Real org:
  `ok: permset:AncCrmIntegrationUser can read Account.Credit_Limit__c, Account.Credit_Risk__c, Account.Customer_Type__c and has 0 assignees`.
- Mutation: AncCrmIntegrationUser carries a user license (LicenseId 100Ek00000xJCExIAO) with no
  assignable user, and a new permission set would need a deletion afterwards, so the red is shown
  on real data by removing the RutaCargo_Support_Agent exemption (1 real assignee):
  ```
  FAIL: permset:RutaCargo_Support_Agent can read Account.Credit_Limit__c, Account.Credit_Risk__c, Account.Customer_Type__c and has 1 assignee(s): test-tzfzdztrb3cf@example.com
  shipment-access-check: 1 violation(s) in cargo-opus-t1
  ```

### Finding 10 — access-auditor [Low] EXP-001 guest field permissions — fixed

- guest-access-check.sh section 3b: 0 FieldPermissions rows on Shipment__c and on Account fields
  ending in __c, for the guest profile and every permission set assigned to the guest (the platform
  keeps rows on 28 standard Account fields for the guest profile; with no object permission they
  grant nothing and are not counted).
- Mutation: guest profile granted Read on Account.Customer_Type__c, deployed:
  ```
  FAIL: the guest has 1 FieldPermissions rows on Shipment__c or Account custom fields: X00eEk00000IL4hQIAT:Account.Customer_Type__c
  guest-access-check: 1 violation(s) in cargo-opus-t1
  ```
  Revoked by deploying `<readable>false</readable>`, source restored; check green again (0 rows).

### Finding 11 — task-reviewer T4 [Low] non-200 counted as refused — fixed

- Section 7 passes only on 401, 403, 404, a 3xx whose Location is `https://<site host>/<prefix>/login...`,
  or the existing 200 whose body only redirects to login; anything else (000, 5xx, other) fails.
  SELF_REG_TIMEOUT (default 60 s) bounds each GET.
- Before (HEAD script, only its max-time set to 0.001 s):
  ```
  ok:   anonymous GET https://data-energy-2854-dev-ed.scratch.my.site.com/rutacargovforcesite/SiteRegister returns 000 (refused)
  guest-access-check: passed in cargo-opus-t1
  ```
  After (`SELF_REG_TIMEOUT=0.001`):
  ```
  FAIL: anonymous GET https://data-energy-2854-dev-ed.scratch.my.site.com/rutacargovforcesite/SiteRegister returns 000, expected 401, 403, 404 or a redirect to login (refusal not proven)
  guest-access-check: 2 violation(s) in cargo-opus-t1
  ```
  Real org: both pages return 401 (refused).

### Re-applied acceptance mutation (branding file changed)

- AC-F.10: PrimaryAccentColor #0176D3 → `FAIL: branding PrimaryAccentColor is '#0176D3', expected #016BFA (primary: electric blue)` (plus the palette line).

### Green (LOOP runners at 58e8ba6 content)

- `sf apex run test --class-names ShipmentSchemaTest --class-names DeliveryAccessCodeTest --class-names SupportAgentAccessTest ...`: Outcome Passed, Tests Ran 75, Pass Rate 100%.
- `npm run test:unit -- force-app/main/default/lwc`: 4 suites, 17 tests passed.
- `sf community publish --name RutaCargo`: Live; home page carries the new branding.
- brand-check, guest-access-check, shipment-access-check, schema-check: each "passed in cargo-opus-t1";
  scripts/seed/verify.sh: "all checks passed", `120 of 120 access codes verify` (seed.sh not run).
- GATE: `sf project deploy start --source-dir force-app --test-level RunLocalTests ...` →
  0AfEk00000h46cPKAQ Succeeded, 101 tests, 0 failures, 92 components; coverage org 90.79%,
  DeliveryAccessCode 98.42%, ShipmentTriggerHandler 95.45%, ShipmentTrigger 100%. All checks re-run
  after the GATE: exit 0.

### Code analyzer

- `sf code-analyzer run --target <3 test classes> --target lwc/rcHeader --target lwc/rcHome --rule-selector Recommended`:
  sev1 0, sev2 0, sev3 76, sev4 75 (HEAD baseline on the same targets: 0/0/72/74). The +5: MethodNamingConventions
  on the new underscore test names (project convention), one @lwc/lwc/no-async-operation (setTimeout flush in
  rcHeader.accessibility.test.js, as in rcHeader.test.js), SLDS hard-coded values for the new isotype/logo rules
  (#016bfa tile, 3rem, 360px: no SLDS hook for a logo size or a brand color). FieldDeclarationsShouldBeAtStart from
  the first draft was fixed (constants moved to the class top).

### Governor-limit notes

- verify stays 1 SOQL and one 100-round hash (~8 ms CPU) per call; the new tests make 2 calls each.
- ShipmentSchemaTest now inserts 1 Standard Platform User (3 Salesforce Platform licenses; each test class
  stays at or below 3 users in its own transaction).

### Commands

- `sf org display --target-org cargo-opus-t1 --json`; `sf org list --skip-connection-status --json`
- `sf project deploy start --source-dir <changed paths> --target-org cargo-opus-t1` (each deploy alone)
- `sf apex run test ... --result-format human --wait 10 --target-org cargo-opus-t1`
- `npm install --save-dev @sa11y/jest@^8.3.1`; `npm run test:unit -- force-app/main/default/lwc`; `npx sfdx-lwc-jest -- <file>`
- `sf community publish --name RutaCargo --target-org cargo-opus-t1`
- `scripts/checks/{brand-check,guest-access-check,shipment-access-check,schema-check}.sh cargo-opus-t1`; `scripts/seed/verify.sh cargo-opus-t1`
- `sf data query [--use-tooling-api] --target-org cargo-opus-t1 --json --query ...`
- `sf code-analyzer run ... --output-file <scratchpad>/code-analyzer-results-close-fix-final.json`
- GATE as in the handoff.
