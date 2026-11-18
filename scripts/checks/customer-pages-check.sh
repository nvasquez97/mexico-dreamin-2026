#!/usr/bin/env bash
# Live check of the customer pages of the RutaCargo LWR site
# (odd/tasks/req-005-customer-signup.md S3, S4; AC-005.5 live logout,
# AC-005.7 T3 part, AC-005.9 published views, assumption F9).
# Reads the source, runs constant SOQL queries and anonymous HTTP requests.
# It never submits the rcSignUp form. Section 4 is OPT-IN
# (--probe-standard-selfreg): it sends the STANDARD self-registration action
# twice, live, with a fake example.com email and a random password that is
# never printed nor put on a command line (the request body goes to curl on
# stdin); every call emails the site admin a platform alert, so the default
# run skips it.
#
# Exits non-zero unless:
#   1. in source, the register, login and forgotPassword views each place
#      their component (c:rcSignUp, c:rcLogin, c:rcForgotPassword) once and no
#      community_login:selfRegister, community_login:loginForm or
#      community_login:forgotPassword;
#   2. published: the anonymous page SelfRegister, login and ForgotPassword
#      each load a view module that names their component (c/rcSignUp,
#      c/rcLogin, c/rcForgotPassword) and none of the three standard ones;
#   3. logout: the URL rcHeader links to (site base path + LOGOUT_PATH of
#      rcHeader.js), requested with no session, never answers 404 or 5xx,
#      redirects only within the site host and ends in the platform's logout
#      page that sends the visitor back to the LWR site (base path);
#   4. (only with --probe-standard-selfreg) F9: the standard self-registration action
#      (applauncher.SelfRegisterController.selfRegisterGetRedirectUrl, called
#      directly as the guest, with no account and with the account of a
#      RutaCargo customer) creates no User, Contact or Account for its email,
#      the org's User, Contact and Account counts and the Customer Community
#      licenses used are unchanged, and it answers no redirect URL.
#
# A failed query stops the check with exit code 3; violations exit 1.
#
# Usage: scripts/checks/customer-pages-check.sh <org-alias> [--probe-standard-selfreg]
set -uo pipefail
export LC_ALL=C

usage() {
    echo "Usage: $0 <org-alias> [--probe-standard-selfreg]" >&2
    exit 2
}
ORG=''
PROBE_STANDARD_SELFREG=0
for arg in "$@"; do
    case "$arg" in
        --probe-standard-selfreg) PROBE_STANDARD_SELFREG=1 ;;
        -*) echo "Unknown option: $arg" >&2; usage ;;
        *) [[ -z "$ORG" ]] || usage; ORG="$arg" ;;
    esac
done
[[ -n "$ORG" ]] || usage

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VIEWS="$REPO_ROOT/force-app/main/default/digitalExperiences/site/RutaCargo1/sfdc_cms__view"
HEADER_JS="$REPO_ROOT/force-app/main/default/lwc/rcHeader/rcHeader.js"
LWR_SITE='RutaCargo1'
STANDARD_COMPONENTS='selfRegister loginForm forgotPassword'
# view folder : page path : component
PAGES='register:SelfRegister:rcSignUp login:login:rcLogin forgotPassword:ForgotPassword:rcForgotPassword'
CUSTOMER_PROFILE='RutaCargo Customer'
CUSTOMER_LICENSE='Customer Community'
TIMEOUT="${PAGES_TIMEOUT:-60}"

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
finish() {
    if [[ "$violations" -gt 0 ]]; then
        echo "customer-pages-check: $violations violation(s) in $ORG"
        exit 1
    fi
    echo "customer-pages-check: passed in $ORG"
    exit 0
}

# Runs a SOQL query and stores the records as JSON in ROWS and the total size
# in TOTAL; stops the script (exit 3) on an error. Called directly, never in a
# $(...) subshell, so that the exit ends the script.
ROWS='[]'
TOTAL=0
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "ERROR: query failed: $1" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 3
    fi
    ROWS="$(jq -c '.result.records' <<<"$out")"
    TOTAL="$(jq -r '.result.totalSize' <<<"$out")"
}

# ─── 1. The views in source ─────────────────────────────────────────────────
for entry in $PAGES; do
    IFS=: read -r view page component <<<"$entry"
    file="$VIEWS/$view/content.json"
    if [[ ! -f "$file" ]]; then
        fail "view $view: $file is missing"
        continue
    fi
    n="$(grep -c "\"definition\" : \"c:$component\"" "$file" || true)"
    if [[ "$n" -eq 1 ]]; then
        pass "view $view places c:$component once"
    else
        fail "view $view places c:$component $n times, expected 1"
    fi
    for standard in $STANDARD_COMPONENTS; do
        if grep -q "community_login:$standard" "$file"; then
            fail "view $view still contains community_login:$standard"
        fi
    done
done

# ─── Site URL ───────────────────────────────────────────────────────────────
query "SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE Site.Name = '$LWR_SITE' AND Site.SiteType = 'ChatterNetworkPicasso'"
if [[ "$(jq 'length' <<<"$ROWS")" -ne 1 ]]; then
    fail "site $LWR_SITE has $(jq 'length' <<<"$ROWS") DomainSite rows, expected exactly 1"
    finish
fi
HOST="$(jq -r '.[0].Domain.Domain' <<<"$ROWS")"
PREFIX="$(jq -r '.[0].PathPrefix // ""' <<<"$ROWS")"
SITE_URL="https://$HOST$PREFIX"

# ─── 2. The published views ─────────────────────────────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for entry in $PAGES; do
    IFS=: read -r view page component <<<"$entry"
    url="$SITE_URL/$page"
    code="$(curl -s -o "$tmp/page.html" -w '%{http_code}' --max-time "$TIMEOUT" "$url" || true)"
    if [[ "$code" != "200" ]]; then
        fail "anonymous GET $url returns ${code:-000}, expected 200"
        continue
    fi
    module="$(grep -oE "$PREFIX/webruntime/view/[^\"]+/${view}_view" "$tmp/page.html" | head -1 || true)"
    if [[ -z "$module" ]]; then
        fail "the published page $url loads no ${view}_view module"
        continue
    fi
    code="$(curl -s -o "$tmp/view.js" -w '%{http_code}' --max-time "$TIMEOUT" "https://$HOST$module" || true)"
    if [[ "$code" != "200" ]]; then
        fail "anonymous GET of the ${view}_view module returns ${code:-000}, expected 200"
        continue
    fi
    if grep -q "c/$component" "$tmp/view.js"; then
        pass "the published $page page renders c/$component"
    else
        fail "the published $page page does not render c/$component"
    fi
    for standard in $STANDARD_COMPONENTS; do
        if grep -q "community_login/$standard" "$tmp/view.js"; then
            fail "the published $page page still renders community_login/$standard"
        fi
    done
done

# ─── 3. Logout ──────────────────────────────────────────────────────────────
logout_path="$(grep -oE '^const LOGOUT_PATH = "[^"]+";' "$HEADER_JS" | sed -E 's/^const LOGOUT_PATH = "([^"]+)";$/\1/' || true)"
if [[ -z "$logout_path" ]]; then
    fail "rcHeader.js declares no LOGOUT_PATH"
else
    url="$SITE_URL$logout_path"
    hops=0
    ok=''
    while [[ "$hops" -lt 6 ]]; do
        read -r code location <<<"$(curl -s -o "$tmp/logout.html" -w '%{http_code} %{redirect_url}' --max-time "$TIMEOUT" "$url" || true)"
        code="${code:-000}"
        echo "      logout hop $hops: GET $url -> $code ${location:-}"
        if [[ "$code" =~ ^3[0-9][0-9]$ ]]; then
            if [[ "$location" != "https://$HOST/"* ]]; then
                fail "logout redirects off the site host to '${location:-no Location}'"
                break
            fi
            url="$location"
            hops=$((hops + 1))
            continue
        fi
        if [[ "$code" != "200" ]]; then
            fail "logout URL $url answers $code, expected a redirect or the logout page (never 404)"
            break
        fi
        target="$(grep -oE "redirectUrl = '[^']+'" "$tmp/logout.html" | head -1 | sed -E "s/^redirectUrl = '([^']+)'$/\1/" || true)"
        if [[ "$target" == "$SITE_URL" || "$target" == "$SITE_URL/"* ]]; then
            ok="$target"
        else
            fail "the logout page sends the visitor to '${target:-nowhere}', expected the site $SITE_URL"
        fi
        break
    done
    if [[ -n "$ok" ]]; then
        pass "logout $SITE_URL$logout_path ends the session on the platform page and returns to $ok"
    elif [[ "$hops" -ge 6 ]]; then
        fail "logout redirects more than 5 times"
    fi
fi

# ─── 4. F9: the standard self-registration action creates nothing (opt-in) ─
if [[ "$PROBE_STANDARD_SELFREG" -ne 1 ]]; then
    echo "skip: section 4 (F9, the standard self-registration action called live) is opt-in: run with --probe-standard-selfreg"
    finish
fi

counts() {
    local email="$1"
    query "SELECT COUNT() FROM User"; local users="$TOTAL"
    query "SELECT COUNT() FROM Contact"; local contacts="$TOTAL"
    query "SELECT COUNT() FROM Account"; local accounts="$TOTAL"
    query "SELECT UsedLicenses FROM UserLicense WHERE Name = '$CUSTOMER_LICENSE'"
    local used
    used="$(jq -r '.[0].UsedLicenses // "none"' <<<"$ROWS")"
    query "SELECT COUNT() FROM User WHERE Email = '$email' OR Username LIKE '$email%'"; local email_users="$TOTAL"
    query "SELECT COUNT() FROM Contact WHERE Email = '$email'"; local email_contacts="$TOTAL"
    echo "users=$users contacts=$contacts accounts=$accounts licensesUsed=$used emailUsers=$email_users emailContacts=$email_contacts"
}

query "SELECT Contact.AccountId FROM User WHERE Profile.Name = '$CUSTOMER_PROFILE' AND ContactId != null ORDER BY CreatedDate LIMIT 1"
customer_account="$(jq -r '.[0].Contact.AccountId // ""' <<<"$ROWS")"

for account in "" "$customer_account"; do
    label="no account"
    [[ -n "$account" ]] && label="the account of a RutaCargo customer"
    email="f9-check-$(date +%s)-$(openssl rand -hex 3)@example.com"
    password="F9$(openssl rand -hex 12)x7"
    # counts() calls query(), which may exit: run it without a subshell.
    counts "$email" >"$tmp/before"; before="$(cat "$tmp/before")"
    # The password reaches jq on stdin (printf is a shell builtin) and the body
    # reaches curl on stdin (--data @-): neither is ever a process argument.
    answer="$(printf '%s' "$password" \
        | jq -Rc --arg e "$email" --arg a "$account" '{namespace:"applauncher",classname:"SelfRegisterController",method:"selfRegisterGetRedirectUrl",isContinuation:false,params:{firstname:"Fnine",lastname:"Check",email:$e,password:.,confirmPassword:.,accountId:$a,regConfirmUrl:"./CheckPasswordResetEmail",extraFields:"[]",startUrl:"",includePassword:true,redirect:false},cacheable:false}' \
        | curl -s --max-time "$TIMEOUT" -X POST -H 'Content-Type: application/json' -H "Origin: https://$HOST" \
            --data @- "$SITE_URL/webruntime/api/apex/execute?language=en-US&asGuest=true&htmlEncode=false" || true)"
    unset password
    returned="$(jq -r '.returnValue // empty' <<<"$answer" 2>/dev/null || true)"
    echo "      standard selfRegister ($label, $email) answered: ${returned:-<no returnValue>}"
    counts "$email" >"$tmp/after"; after="$(cat "$tmp/after")"
    echo "      before: $before"
    echo "      after:  $after"
    if [[ "$returned" =~ ^(https?:|/) ]]; then
        fail "the standard self-registration action ($label) answered a redirect URL: a user may have been created"
    fi
    if [[ "$before" != "$after" ]]; then
        fail "the standard self-registration action ($label) changed the org: $before -> $after"
    elif [[ "$after" != *"emailUsers=0 emailContacts=0" ]]; then
        fail "a User or Contact exists for $email"
    else
        pass "the standard self-registration action ($label) created no User, Contact or Account and used no license"
    fi
done

finish
