# Deploy order from zero: the RutaCargo site and its guest profile

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

## Steps

Replace `<alias>` with the target org. Run each command on its own.

1. Site first: Network, CustomSite, DigitalExperienceConfig, the
   DigitalExperienceBundle and the site's navigation menu. This creates the site,
   its guest user, the guest profile `RutaCargo Profile` and `MicrobatchSelfReg`.

   ```bash
   sf project deploy start --source-dir force-app/main/default/networks --source-dir force-app/main/default/sites --source-dir force-app/main/default/digitalExperienceConfigs --source-dir force-app/main/default/digitalExperiences --source-dir force-app/main/default/navigationMenus --target-org <alias> --wait 30
   ```

2. Everything else, the guest profile included (it now exists, so the deploy
   updates it):

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

5. Check the guest (AC-F.9: Live, 0 object permissions, time zone, home 200,
   guest Visualforce pages equal to the allow-list, self-registration refused):

   ```bash
   scripts/checks/guest-access-check.sh <alias>
   ```

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
  org cargo-opus-t1, where the site already existed (a redeploy). Creating the
  site from zero in a second org has not been run, because deploys are allowed
  only to cargo-opus-t1 (A11). Run these steps in the next new org and record
  the result.
