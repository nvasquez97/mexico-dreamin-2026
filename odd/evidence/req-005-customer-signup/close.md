# Close of req-005-customer-signup - fix round evidence

## Fix - 0bb3a33

- Reviewed range: 3c64ca7..5b7a061 (HEAD at start 29d6a48, bookkeeping only since)
- Fix commit: 0bb3a33 `close fix req-005-customer-signup: close review findings 1-13`
- Org: cargo-opus-t1. `sf org list --skip-connection-status`: `isScratch: true`, `isDevHub: false`, org Id 00DEk00000qop2zMAA. Confirmed with `sf org display` before the first org operation. Not production.
- Skills used: salesforce-development:platform-apex-generate (controller, registration and nickname changes), salesforce-development:platform-apex-test-generate (new test methods and seams), salesforce-development:platform-apex-test-run (synchronous class runs), salesforce-development:platform-metadata-deploy (LOOP deploys), salesforce-development:platform-metadata-retrieve (stale-conflict proof), salesforce-development:platform-soql-query (Network options query), experience-lwc:experience-lwc-generate (rcLogin, rcSignUp and rcForgotPassword code, CSS and Jest), experience-lwc:experience-lwc-security-validate (LWS catalog sweep), salesforce-code-quality:dx-code-analyzer-run (analyzer), sf-security-code-review (P11 sharing keywords, X4 redirect, open-redirect trace).
- No live sign-up. The standard self-register action was never called: the opt-in mode of customer-pages-check.sh was not run. No password is printed or stored in this file. Test values are the existing non-secret rule values.

### Finding 1 - test-reviewer, Medium (AC-005.7): no check of the sharing keywords, justification comments and callers - FIXED

`scripts/checks/customer-access-check.sh` section 8 (source) now checks:
- the two guest controllers are `public with sharing class <Name>` and contain no `without sharing`;
- CustomerRegistration and CustomerPermissionAssigner are `public without sharing class <Name>`, directly below a `// SECURITY-JUSTIFICATION:` comment block that ends with `(<approver>, <YYYY-MM-DD>)`;
- neither builds dynamic SOQL or SOSL (binds only);
- every class in the six req-005 classes, inner classes included, has a sharing keyword (this also enforces finding 10);
- only the allow-listed `.cls`/`.trigger` files name CustomerRegistration or CustomerPermissionAssigner. CustomerPermissionAssigner is allowed to name CustomerRegistration because it reads the constant CUSTOMER_PROFILE_NAME;
- no LWC or Aura component imports either helper.

A grep error exits 3.

Mutation, applied to the real tree in one run and reverted from backups. Primary: `CustomerLoginController` changed to `public without sharing class`. Extras: the `// SECURITY-JUSTIFICATION:` prefix removed in CustomerRegistration, and `private static final String MUTATION_REF = CustomerRegistration.CUSTOMER_PROFILE_NAME;` added to TestDataFactory. The run happened before the network deploy, so the direct-messages line is also red:
```
FAIL: Network RutaCargo has direct messages on (OptionsDirectMessagesEnabled true), expected false
FAIL: CustomerLoginController: expected one 'public with sharing class CustomerLoginController' and no 'without sharing' (found 0 declaration(s), 1 without sharing)
FAIL: CustomerRegistration is without sharing with no SECURITY-JUSTIFICATION comment block (with approver and date) right above its declaration
FAIL: Apex source outside the allow-list names the without-sharing CustomerRegistration: TestDataFactory.cls
customer-access-check: 4 violation(s) in cargo-opus-t1
```
Reverted. `git status` showed TestDataFactory.cls clean. Green after the network deploy (exit 0):
```
ok:   CustomerSignUpController is declared with sharing and has no without sharing class
ok:   CustomerLoginController is declared with sharing and has no without sharing class
ok:   CustomerRegistration is without sharing right below its SECURITY-JUSTIFICATION comment (approver and date)
ok:   CustomerRegistration builds no dynamic SOQL or SOSL (binds only)
ok:   CustomerPermissionAssigner is without sharing right below its SECURITY-JUSTIFICATION comment (approver and date)
ok:   CustomerPermissionAssigner builds no dynamic SOQL or SOSL (binds only)
ok:   every class in CustomerSignUpController.cls declares a sharing keyword
... (the six files)
ok:   only CustomerRegistration.cls,CustomerSignUpController.cls,CustomerLoginController.cls,CustomerPermissionAssigner.cls,CustomerSignUpControllerTest.cls,CustomerLoginControllerTest.cls name CustomerRegistration in the Apex source
ok:   only CustomerPermissionAssigner.cls,CustomerRegistration.cls,CustomerSignUpControllerTest.cls name CustomerPermissionAssigner in the Apex source
ok:   no LWC or Aura component imports CustomerRegistration or CustomerPermissionAssigner
customer-access-check: passed in cargo-opus-t1
```
AC-005.7's own mutation (Read on Account.Credit_Limit__c) was not re-applied. This round did not change sections 1-3 or the permission set.

### Finding 2 - test-reviewer, Medium: the password is not asserted at the seams - FIXED

FakeSite now records `pass` in both `validatePassword` and `createExternalUser`. `assertPasswordReachesPlatformUnchanged` checks one call to each seam and an exact, case-sensitive `typed.equals(...)` match. It runs with two inputs: `abcd12345X`, and a second value with mixed case plus inner and outer spaces (`OTHER_VALID_PASS`). Both tests were green on the first run, so the reds come from mutations.
- Mutation `register(applicant, password.toLowerCase())`:
  ```
  CustomerSignUpControllerTest.signUp_passwordOfTenWithLettersAndDigits_isAccepted  Fail  System.AssertException: Assertion Failed: Site.validatePassword gets the typed password exactly
  CustomerSignUpControllerTest.signUp_passwordWithSpacesAndMixedCase_reachesPlatformUnchanged  Fail  System.AssertException: Assertion Failed: Site.validatePassword gets the typed password exactly
  ```
- Mutation `register(applicant, password.trim())`: only the second input turns red, which shows that input is needed:
  ```
  CustomerSignUpControllerTest.signUp_passwordWithSpacesAndMixedCase_reachesPlatformUnchanged  Fail  System.AssertException: Assertion Failed: Site.validatePassword gets the typed password exactly
  Tests Ran  46  Pass Rate  98%
  ```
- Swapping in the confirmation is equivalent: the controller already proved `password.equals(confirmPassword)` before register, so the two values are identical.

### Finding 3 - test-reviewer, Low: no test of the 128-character maximum - FIXED

Server: `signUp_passwordOf128Characters_isAccepted` (it also checks the value reaches both seams) and `signUp_passwordOf129Characters_isRejected`. Client: `a password longer than its maximum (129 characters) is rejected` and `a password at its maximum (128 characters) is accepted and sent`.
- Server mutation `MAX_PASSWORD = 129`: `CustomerSignUpControllerTest.signUp_passwordOf129Characters_isRejected  Fail  System.AssertException: Assertion Failed: The sign-up must be rejected`
- Client mutation `const MAX_PASSWORD = 129;` (rcSignUp.js): `AC-005.1: a password longer than its maximum (129 characters) is rejected with the password message` - `Expected: "The password needs at least 10 characters, with letters and numbers." Received: null` - `Tests: 1 failed, 74 passed, 75 total`

### Finding 4 - test-reviewer, Low: forgotPassword has one input - FIXED

New test `forgotPassword_secondRegisteredCustomer_resetsHerUsername` with ` MARTA.Ruiz@Example.COM `. It asserts the reset list equals `[martaUsername()]` and is not Ana's username. Mutation: the reset hard-coded to Ana's username (`gateway.forgotPassword(CustomerRegistration.activeCustomerUsername('ana.lopez@example.com'))`). Ana's test stays green; Marta's turns red:
```
CustomerLoginControllerTest.forgotPassword_secondRegisteredCustomer_resetsHerUsername  Fail  System.AssertException: Assertion Failed: Site.forgotPassword gets Marta's username once: Expected: (marta.ruiz@example.com.00dek00000qop2zmaa), Actual: (ana.lopez@example.com.00dek00000qop2zmaa)
```

### Finding 5 - test-reviewer, Low (F14): no parity check between KNOWN_SERVER_MESSAGES and the Apex constants - FIXED

rcSignUp.test.js has a new `describe("AC-005.10 (F14): the known messages are the Apex constants")`. It parses every `public static final String MESSAGE_* = '...';` in `classes/CustomerSignUpController.cls` (12 found) and asserts they equal the test's copy. For each Apex constant, it then asserts the component shows the message as-is, which means the message is in the component's allow-list.
- Mutation: an Apex constant changes (MESSAGE_PHONE "up to 40" becomes "up to 41"; the source was edited and not deployed):
  ```
  ● ... the test's copy of the server messages equals the MESSAGE_* constants of CustomerSignUpController.cls
  ● ... the component shows the Apex constant MESSAGE_PHONE as it is (it is in the allow-list)
  Expected: "Enter a valid phone number (digits, spaces, +, -, parentheses; up to 41 characters)."
  Received: "We could not create your account. Please try again later."
  Tests: 2 failed, 73 passed, 75 total
  ```
- Mutation: MESSAGE_PASS_POLICY dropped from the component's KNOWN_SERVER_MESSAGES gives `Tests: 3 failed, 72 passed, 75 total`, including `the component shows the Apex constant MESSAGE_PASS_POLICY as it is`.

### Finding 6 - test-reviewer, Low (F13): customer-pages-check.sh calls the standard self-register action on every run and puts the password in curl `--data` - FIXED

- Section 4 now runs only with `--probe-standard-selfreg`. The default run prints `skip: section 4 (F9, the standard self-registration action called live) is opt-in: run with --probe-standard-selfreg` and finishes. Unknown options and a missing alias exit 2 with the usage line.
- In the opt-in path, the password goes to jq on stdin (`printf` is a shell builtin) and jq's body goes to curl on stdin (`--data @-`). Neither is ever a process argument.
- Before (HEAD) `customer-pages-check.sh:209-211`: `body="$(jq -nc ... --arg p "$password" ...)"` and `curl ... --data "$body" .../webruntime/api/apex/execute...`. After: `grep -n -- '--data "\$body"\|--arg p' scripts/checks/customer-pages-check.sh` gives no match.
- Proof that the default run never calls the action: the script ran in default mode with a logging `curl` shim on PATH that records URL arguments only. Exit 0, `customer-pages-check: passed in cargo-opus-t1`, 8 URLs requested (3 pages, 3 view modules, 2 logout hops), `apex/execute calls: 0`.
- The opt-in body was checked offline with a dummy value; nothing was sent: `{"pw_eq":true,"email":"x@example.com","accountId":"","method":"selfRegisterGetRedirectUrl"}`. The opt-in mode was NOT run, as the handoff requires.

### Finding 7 - test-reviewer, Low: the blank-password rule has no test; success never asserts `message` is null - FIXED

New tests `login_emptyPassword_failsWithoutCallingSiteLogin` (`''`) and `login_passwordOfSpaces_failsWithoutCallingSiteLogin` (`'   '`) assert the one failure message and that Site.login is not called. The two success tests now also check `Assert.isNull(result.message, ...)`. Mutation: the rule dropped (`if (username == null) {`):
```
CustomerLoginControllerTest.login_emptyPassword_failsWithoutCallingSiteLogin  Fail  System.AssertException: Assertion Failed: Site.login is not called for an empty password: Expected: 0, Actual: 1
CustomerLoginControllerTest.login_passwordOfSpaces_failsWithoutCallingSiteLogin  Fail  System.AssertException: Assertion Failed: Site.login is not called for a blank password: Expected: 0, Actual: 1
```

### Finding 8 - test-reviewer, Low: no direct null test for customerType, password, confirmPassword - FIXED

New tests `signUp_nullCustomerType_isRejected`, `signUp_nullPassword_isRejected` and `signUp_nullConfirmPassword_isRejected` call the @AuraEnabled method as the real site guest. They assert the field, the generic message, no Account or Contact, no createExternalUser call and no job. They were green on the first run. Mutations, one per field, in the same deploy (each red belongs only to its own test): a null-tolerant type guard (`customerType != null && !CUSTOMER_TYPES.contains(...)`), no null check in `isValidPassword`, and `confirmPassword.equals(password)`:
```
CustomerSignUpControllerTest.signUp_nullConfirmPassword_isRejected  Fail  System.NullPointerException: Attempt to de-reference a null object
CustomerSignUpControllerTest.signUp_nullCustomerType_isRejected  Fail  System.AssertException: Assertion Failed: The sign-up must be rejected
CustomerSignUpControllerTest.signUp_nullPassword_isRejected  Fail  System.NullPointerException: Attempt to de-reference a null object
```

### Finding 9 - security-reviewer, Low (F11): CommunityNickname built from the email local part - FIXED

`CustomerRegistration.buildUser` now sets `CommunityNickname = 'customer-' + 12 random hex characters` (48 bits from `Crypto.generateAesKey`). The test `signUp_sameLocalPart_buildsDifferentNicknames` still proves ana@x.com and ana@y.com get different nicknames. The new `signUp_nickname_neverContainsTheEmailLocalPart` checks the `customer-[0-9a-f]{12}` format and that neither `ana` nor `luis.garza` appears in the nickname. Red before the fix:
```
CustomerSignUpControllerTest.signUp_nickname_neverContainsTheEmailLocalPart  Fail  System.AssertException: Assertion Failed: Nickname = "customer-" + 12 random hex characters: ana-37aa2c
Tests Ran  46  Pass Rate  98%
```
Uniqueness: the nickname is not looked up in the org. A collision (about 1 in 2.8e14 per pair) makes Site.createExternalUser throw DUPLICATE. The savepoint then rolls back the Account and Contact, and the visitor gets the generic failure message. That is a safe failure.

### Finding 10 - security-reviewer, Low (F11, P11): inner classes without a sharing keyword - FIXED

`inherited sharing` was added to SignUpResult, LoginResult, RegistrationException and Applicant. The test classes are now `private with sharing class` (as the other test classes in the repo are), and their inner FakeSite and SignUpForm classes are `inherited sharing`. Interfaces and enums take no keyword. CustomerPermissionAssigner has no inner class. Before: the new section 8 run on HEAD's source (a throwaway worktree) gave:
```
FAIL: CustomerSignUpController.cls: class(es) without a sharing keyword: public class SignUpResult
FAIL: CustomerLoginController.cls: class(es) without a sharing keyword: public class LoginResult
FAIL: CustomerRegistration.cls: class(es) without a sharing keyword: public class RegistrationException extends Exception;public class Applicant
FAIL: CustomerSignUpControllerTest.cls: class(es) without a sharing keyword: private class CustomerSignUpControllerTest;private class FakeSite implements CustomerRegistration.SiteGateway;private class SignUpForm
FAIL: CustomerLoginControllerTest.cls: class(es) without a sharing keyword: private class CustomerLoginControllerTest;private class FakeSite implements CustomerLoginController.SiteAuthGateway
```
After: `ok:   every class in <file> declares a sharing keyword` for all six files. Both test classes stay green under `with sharing`: 46/46 and 24/24.

### Finding 11 - task-reviewer/security (T3), Low (F13, X4) - FIXED (a, c); (b) already in place, locked by a test

(a) rcLogin opened any `https://` redirect. `isOpenableUrl` now opens only a site-relative path, or an `https:` URL whose `new URL(url).origin === window.location.origin`. The Jest file runs on an https site origin (`@jest-environment-options {"url": "https://rutacargo-test.my.site.com/rutacargo/login"}`). Red before the fix, then the mutation `return Boolean(new URL(url).origin);` (any https):
```
● c-rc-login › AC-005.5 (X4): a redirect URL "https://evil.example/rutacargo/secur/frontdoor.jsp?sid=TOKEN_C" outside the site's own https origin is not opened
● c-rc-login › AC-005.5 (X4): a redirect URL "https://rutacargo-test.my.site.com.evil.example/rutacargo/secur/frontdoor.jsp" outside the site's own https origin is not opened
Expected number of calls: 0
Received number of calls: 1
Tests: 2 failed, 33 passed, 35 total
```
Not verified live: a real login needs a customer password, and none is held. Site.login's redirect is expected on the site's own host. T3's live smoke and the logout check show the site and its platform pages on `https://data-energy-2854-dev-ed.scratch.my.site.com`. If the redirect came from another host, rcLogin would show the generic error instead of opening it.

(b) `autocomplete="organization"` on the name field: rcSignUp.html already has `autocomplete="organization"` on accountName, `given-name` on firstName and `family-name` on lastName (lines 69, 92, 113 at HEAD). The handoff's target state was already met, so no markup changed. A new Jest test locks all seven autocomplete values. Mutation `autocomplete="name"`: `AC-005.1 (F13): the name or legal name autocompletes as an organization ...` gives `Tests: 1 failed, 74 passed, 75 total`.

(c) A startURL with the base path prefix fell back to "/". On the server, `CustomerLoginController.START_URLS` is now a closed map. The listed pages and their `/rutacargo` forms (`/rutacargo`, `/rutacargo/`, `/rutacargo/my-shipments`, `/rutacargo/request-shipment`) map to the listed page passed to Site.login; anything else gives "/". The client (rcLogin `START_URLS`) now passes the same prefixed forms to the server instead of replacing them with "/". Without that, the server change would never receive them, so this is noted as part of the fix. Server red before:
```
CustomerLoginControllerTest.login_basePathPrefixedRequestStartUrl_passesTheListedPage  Fail  System.AssertException: Assertion Failed: The prefixed form maps to the listed page: Expected: /request-shipment, Actual: /
CustomerLoginControllerTest.login_basePathPrefixedShipmentsStartUrl_passesTheListedPage  Fail  System.AssertException: Assertion Failed: The prefixed form maps to the listed page: Expected: /my-shipments, Actual: /
```
New negative cases `/rutacargox/my-shipments` and `/rutacargo/secur/frontdoor.jsp` both give "/" (server and client). Client red before: `Expected: "/rutacargo/my-shipments" Received: "/"` (3 tests). Client mutation removing the prefixed forms: `Tests: 3 failed, 32 passed, 35 total`.

### Finding 12 - sf-security-auditor, Low SEC-002 (X11): direct messages on - FIXED

`RutaCargo.network-meta.xml`: `<enableDirectMessages>false</enableDirectMessages>`, deployed and published. customer-access-check.sh section 4 now queries `Network.OptionsDirectMessagesEnabled`. Before (org at HEAD): `FAIL: Network RutaCargo has direct messages on (OptionsDirectMessagesEnabled true), expected false`. After the deploy: `ok:   Network RutaCargo has direct messages off`.

### Finding 13 - brand-reviewer, Low: label weight, link underline, indented link - FIXED

- `.rc-auth__label { font-weight: 500 }` in rcSignUp.css, rcLogin.css and rcForgotPassword.css. Before: `font-weight: 700` at rcSignUp.css:76, rcLogin.css:61, rcForgotPassword.css:61. The customer-type legend uses the same class.
- Underline: the published site stylesheet (`/rutacargo/assets/styles/dxp-slds-extensions.min.css`) has `a,a:link:not(.slds-button, .slds-dropdown__item > a),a:visited:not(...){color:var(--dxp-c-link-text-color, ...);...;text-decoration:var(--dxp-c-link-text-decoration, var(--dxp-s-link-text-decoration, underline))...}`. On hover it reads `text-decoration:var(--dxp-s-link-text-decoration-hover)`. `.rc-auth` in all three files now sets `--dxp-c-link-text-decoration: underline;` and `--dxp-s-link-text-decoration-hover: underline;`.
- Indent: rcLogin's "Forgot your password?" paragraph has the new `rc-auth__footer--link-only` class, and `.rc-auth__footer--link-only .rc-auth__link { margin-inline-start: 0; }` overrides the 0.25rem spacing that exists only for "text + link".
- Published check: after the LOOP deploy and `sf community publish`, the anonymous login_view module contains `dxp-c-link-text-decoration`, `rc-auth__footer--link-only` and `font-weight: 500`. No rendered browser check was made. Noticed, not changed (outside what the finding named): rcForgotPassword's footer "Back to log in" is also a link-only footer with the same 0.25rem indent.

### Deploy, publish and checks

- First LOOP deploy: `13 conflicts detected` (rcSignUp, rcLogin and rcForgotPassword files, Network RutaCargo). A retrieve to a temporary metadata dir (`sf project retrieve start --metadata LightningComponentBundle:rcSignUp ... --metadata Network:RutaCargo --target-metadata-dir <tmp> --unzip`) showed:
  - every LWC file in the org equals HEAD except for the final newline the platform strips;
  - the network equals HEAD except `emailSenderAddress`, where the platform keeps the admin's own address instead of the repo's `noreply@example.com` (a platform-set value, not an edit).

  The conflicts were stale, so the LOOP was re-run with `--ignore-conflicts`: success, deploy 0AfEk00000h5gU5KAI. A final LOOP deploy without the flag after the analyzer fix: success, 0AfEk00000h5fEgKAI.
- `sf community publish --name RutaCargo`: status Live, jobs 08PEk00000qSieqMAC and 08PEk00000qTH2oMAG.
- Apex (synchronous, one class per run): CustomerSignUpControllerTest `Outcome Passed, Tests Ran 46, Pass Rate 100%`; CustomerLoginControllerTest `Outcome Passed, Tests Ran 24, Pass Rate 100%`.
- Jest `npx jest force-app/main/default/lwc/rcSignUp force-app/main/default/lwc/rcLogin force-app/main/default/lwc/rcForgotPassword`: `Test Suites: 6 passed, 6 total`, `Tests: 130 passed, 130 total`.
- `scripts/checks/customer-access-check.sh cargo-opus-t1`: exit 0, `customer-access-check: passed in cargo-opus-t1`.
- `scripts/checks/guest-access-check.sh cargo-opus-t1`: exit 0, `guest-access-check: passed in cargo-opus-t1`. One intermediate run failed. The repo secret scan flagged the object key `password` set to the autocomplete value new-password in the new rcSignUp test (`FAIL: password literal in the repository at: ...rcSignUp.test.js:200 ...:201`). The test was rewritten as `[field, autocomplete]` pairs, and its mutation was re-run red.
- `scripts/checks/customer-pages-check.sh cargo-opus-t1` (default mode): exit 0, section 4 skipped, 0 calls to `apex/execute`.

### Code analyzer

`sf code-analyzer run --rule-selector Recommended` over the five changed Apex classes and the three LWC bundles:
- First run: one sev 2, `no-unused-vars` at rcLogin.js:42 (the `catch (invalidUrl)` binding). Fixed with an optional catch binding, redeployed and republished.
- Final run: `{"1":0,"2":0,"3":108,"4":186,"5":5}`.
- Baseline of the same files at HEAD: `{"1":0,"2":0,"3":85,"4":168,"5":5}`. The increase comes from the 15 new test methods and two private test helpers: MethodNamingConventions 55→70, ApexUnitTestClassShouldHaveRunAs 55→70, ApexUnitTestClassShouldHaveAsserts 23→31 (assertions live in shared helpers), and ApexDoc 13→16 (one-line `@description` on private test helpers, as in the existing helpers). `no-hardcoded-values-slds2` stays at 98 and CyclomaticComplexity at 1.

LWS (experience-lwc-security-validate, review mode): the catalog sinks (lws-001..lws-023b: document.write/open/execCommand, eval/Function, global assignment, nonce, context manipulation `.call/.apply/.bind/Reflect`, innerHTML/outerHTML/insertAdjacentHTML/lwc:inner-html/lwc:dom, createObjectURL, srcdoc/iframe/object, disallowed URL schemes, storage, console) were swept over the code lines of the three bundles: no match. rcLogin reads `window.location` and never writes it; `new URL(url)` only computes the origin.

Governor limits: no new SOQL or DML. START_URLS is a constant map, and the nickname uses one `Crypto.generateAesKey` call as before.

### Commands

- `sf org list --skip-connection-status --json`, `sf org display --target-org cargo-opus-t1 --json`
- `sf data query --target-org cargo-opus-t1 --json --query "SELECT Name, OptionsDirectMessagesEnabled, OptionsNicknameDisplayEnabled FROM Network WHERE Name = 'RutaCargo'"`
- `sf project deploy start --source-dir force-app/main/default/classes [--source-dir <one class for mutations>] --target-org cargo-opus-t1`
- `sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/lwc/rcSignUp --source-dir force-app/main/default/lwc/rcLogin --source-dir force-app/main/default/lwc/rcForgotPassword --source-dir force-app/main/default/networks/RutaCargo.network-meta.xml --target-org cargo-opus-t1 [--ignore-conflicts after the retrieve]`
- `sf project retrieve start --metadata ... --target-metadata-dir <tmp> --unzip --target-org cargo-opus-t1 --json`
- `sf community publish --name RutaCargo --target-org cargo-opus-t1`
- `sf apex run test --class-names CustomerSignUpControllerTest --synchronous --result-format human --target-org cargo-opus-t1` (and CustomerLoginControllerTest)
- `npx jest force-app/main/default/lwc/rcSignUp force-app/main/default/lwc/rcLogin force-app/main/default/lwc/rcForgotPassword`
- `scripts/checks/customer-access-check.sh cargo-opus-t1`, `scripts/checks/guest-access-check.sh cargo-opus-t1`, `scripts/checks/customer-pages-check.sh cargo-opus-t1` (default mode only)
- `sf code-analyzer run --rule-selector Recommended --target <changed files> --output-file <tmp>.json --include-fixes`
- `curl` (anonymous GET) of the published login page, its view module and `/rutacargo/assets/styles/dxp-slds-extensions.min.css`
