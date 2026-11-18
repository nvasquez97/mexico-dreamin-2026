# Deploy order from zero: the RutaCargo site, its guest profile and the customer access

Use this order in a new org (for example a fresh scratch org from
`config/project-scratch-def.json`, which enables Communities). One
`sf project deploy start --source-dir force-app` alone is not enough in a new
org, for two reasons:

- The guest profile `RutaCargo Profile` is created by the platform when the
  site (Network and CustomSite) is created. If the Profile file is deployed
  before the site exists, the deploy can fail or create a separate profile.
- The Visualforce page `MicrobatchSelfReg` is created by the platform together
  with the site (its CreatedDate equals the site's). The guest profile lists it
  in `pageAccesses`, so the profile must be deployed after the site.

The other 22 Visualforce pages the profile lists (SiteRegister, CommunitiesLogin,
the error pages and so on) are created when Communities is enabled, so they
exist before step 1.

The customer self-registration (req-005 S1) adds a third reason:

- force-app's Network lists the customer profile `RutaCargo Customer` as a
  member and as its self-registration profile. The platform refuses a
  self-registration profile that is not already a member of the site ("You
  can only select profiles that are associated with the experience."), and it
  refuses both in one deploy. So the profile is deployed first (step 0), the
  site is created with a member-only copy of the Network
  (`scripts/setup/templates/RutaCargo.network-bootstrap`: force-app's Network
  with the profile as a member and self-registration off, step 1), and
  force-app's Network turns self-registration on later (step 2).

## Steps

Replace `<alias>` with the target org. Run each command on its own.

0. The customer access metadata (req-005 S1): the profile
   `RutaCargo Customer`, its password policy, the permission set
   `RutaCargo_Customer` and the role `RutaCargo_Customer_Owner`. None of them
   needs the site. Check the password policy first with `--dry-run`, then
   deploy:

   ```bash
   sf project deploy start --dry-run --source-dir "force-app/main/default/profiles/RutaCargo Customer.profile-meta.xml" --source-dir force-app/main/default/profilePasswordPolicies --source-dir force-app/main/default/permissionsets/RutaCargo_Customer.permissionset-meta.xml --source-dir force-app/main/default/roles --target-org <alias> --wait 30
   sf project deploy start --source-dir "force-app/main/default/profiles/RutaCargo Customer.profile-meta.xml" --source-dir force-app/main/default/profilePasswordPolicies --source-dir force-app/main/default/permissionsets/RutaCargo_Customer.permissionset-meta.xml --source-dir force-app/main/default/roles --target-org <alias> --wait 30
   ```

1. Site first: Network, CustomSite, DigitalExperienceConfig, the
   DigitalExperienceBundle and the site's navigation menu. This creates the site,
   its guest user, the guest profile `RutaCargo Profile` and `MicrobatchSelfReg`.
   The Network is the member-only bootstrap copy (see the third reason above):
   convert the site to metadata format in a temporary folder, replace its
   Network with the bootstrap, and deploy that folder:

   ```bash
   tmp="$(mktemp -d)"
   sf project convert source --source-dir force-app/main/default/networks --source-dir force-app/main/default/sites --source-dir force-app/main/default/digitalExperienceConfigs --source-dir force-app/main/default/digitalExperiences --source-dir force-app/main/default/navigationMenus --output-dir "$tmp/site"
   cp scripts/setup/templates/RutaCargo.network-bootstrap "$tmp/site/networks/RutaCargo.network"
   sf project deploy start --metadata-dir "$tmp/site" --target-org <alias> --wait 30
   ```

   The bootstrap must equal force-app's Network except for the
   `selfRegistration` and `selfRegProfile` lines; `customer-owner.sh` (step 4b)
   fails if it does not, so update both files together.

1b. The EntregaYa proof credential and the guest's permission sets
   (req-002-003 E11). Idempotent. The platform refuses to create the
   password-authenticated Named Credential `EntregaYa_API` from force-app,
   because the file has no password, so this step creates it first with a
   non-secret placeholder password. It never changes an existing credential.
   It also removes a `RutaCargo_Guest_Proof_Download` assignment from the guest
   if one exists:

   ```bash
   scripts/setup/guest-proof-access.sh <alias>
   ```

   The owner then enters the real URL and the rotated key in Setup (README,
   "EntregaYa proof of delivery").

2. Everything else, the guest profile included (it now exists, so the deploy
   updates it; `EntregaYa_API` now exists, so the deploy updates it without a
   password):

   ```bash
   sf project deploy start --source-dir force-app --test-level RunLocalTests --target-org <alias> --wait 30
   ```

3. Publish the site, then wait until the job is Complete
   (`SELECT Status FROM BackgroundOperation WHERE Id = '<jobId>'`):

   ```bash
   sf community publish --name RutaCargo --target-org <alias> --json
   ```

4. Guest user time zone (idempotent):

   ```bash
   scripts/setup/site-guest-user.sh <alias>
   ```

4b. The owner of customer accounts and the self-registration (req-005 S1).
   Idempotent; it refuses an org that is not a sandbox or scratch org:

   ```bash
   scripts/setup/customer-owner.sh <alias>
   ```

   It gives the site's guest default record owner (`Site.GuestRecordDefaultOwnerId`,
   by default the user who created the site) the role
   `RutaCargo_Customer_Owner`: records the guest creates are owned by that
   user, and an account that owns external users must be owned by a user with a
   role. It fails if no owner is set, and it never replaces another role. It
   never touches `sites/RutaCargo.site-meta.xml`. Then it applies the two
   Network phases when they are missing (member first with the bootstrap, then
   force-app's Network with self-registration on) and reads the result back.
   After steps 1 and 2 both phases are already done; in an org whose site was
   created before req-005 (for example cargo-opus-t1) this step applies them,
   and a force-app deploy before it fails on the Network with the message
   above.

5. Check the guest (AC-F.9: Live, 0 object permissions, time zone, home 200,
   guest Visualforce pages equal to the allow-list, self-registration refused;
   req-002-003 AC-002.6: no permission set besides the profile's own, no key
   or password in the repository, EntregaYa_API with no password and the
   placeholder URL in source):

   ```bash
   scripts/checks/guest-access-check.sh <alias>
   ```

5b. Check the customer access (req-005 AC-005.7 and AC-005.4: the profile's
   license, no object or field permission on the profile or on
   `RutaCargo_Customer`, the Network member and self-registration with no
   default account, the owner's role, the retrieved password policy):

   ```bash
   scripts/checks/customer-access-check.sh <alias>
   ```

   The site users of the two seeded customers are created after the seed
   (README, "Setup from zero", step 3b).

6. EntregaYa integration (REQ-004, AC-004.6), after step 2 deployed the
   External Client App "EntregaYa Status", the permission set and the group
   `RutaCargo_EntregaYa_Integration`. Idempotent; it refuses an org that is not
   a sandbox or scratch org:

   ```bash
   scripts/setup/entregaya-integration.sh <alias>
   ```

   It creates the integration user `entregaya-integration@<org id>.rutacargo.dev`
   (profile "Minimum Access - API Only Integrations") together with its
   "Salesforce API Integration" permission set license, assigns
   `RutaCargo_EntregaYa_Integration`, adds the user to the group, then renders
   `scripts/setup/templates/EntregaYa_Status_oauth_defaultPolicy.ecaOauthPlcy.template`
   with that username into a temporary folder and deploys it (client
   credentials as that user, the permission set pre-authorized, IP restrictions
   enforced), and reads the policy back. The policies are not in force-app
   because the username differs per org. Do not deploy them from anywhere else:
   a later step-2 deploy does not touch them.

7. Check the EntregaYa access and that anonymous callers are refused:

   ```bash
   scripts/checks/entregaya-access-check.sh <alias>
   scripts/entregaya/attack-check.sh <alias>
   ```

   The consumer key and secret are handed to EntregaYa by the owner from Setup
   (README, "EntregaYa integration").

## Notes

- Proxy cache: the CustomSite has `cachePublicVisualforcePagesInProxyServers`
  true, so a public Visualforce page answers with `s-maxage=600`. After
  disabling a guest page on a site that already served it, shared caches can
  keep serving the old page for up to 10 minutes. Wait 10 minutes before step 5
  in that case. A new org has no cached pages.
- Style files: `sfdc_cms__styles/*/content.json` carry `"ref"` set to the CSS
  file name. The platform requires the key but does not resolve its value: on
  each deploy it stores the file and issues a new media Id, which a retrieve
  writes back as `0sN...`. Do not commit that Id; keep the file name.
- Sender address: the Network uses `noreply@example.com`, which stays pending
  verification. Set a real, verified sender address per org.
- `enableSecureGuestAccess` is not versioned. The platform enforces secure
  guest record access and reads the setting back as false, so a settings file
  would state something the org does not do (assumption A11 in
  odd/tasks/foundation.md).
- What has been proven: steps 1 to 5 ran in this order in the development
  org cargo-opus-t1, where the site already existed (a redeploy). For req-005,
  step 0, step 4b (both Network phases, the first time and again as a no-op)
  and step 5b ran in cargo-opus-t1; step 1 with the bootstrap was validated
  there only with `--dry-run --metadata-dir` (a redeploy of an existing site). Creating the
  site from zero in a second org has not been run, because deploys are allowed
  only to cargo-opus-t1 (A11). Run these steps in the next new org and record
  the result.
