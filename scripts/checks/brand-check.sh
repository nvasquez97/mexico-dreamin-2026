#!/usr/bin/env bash
# Check for AC-F.10 (odd/tasks/foundation.md): the RutaCargo LWR site applies
# the brand manual (docs/brand-manual.pdf pages 5-7, docs/brand/README.txt).
# Read-only: reads the source, runs constant SOQL queries and anonymous HTTP GETs.
#
# Exits non-zero unless:
#   1. the theme's active APP branding set gives the brand color roles: primary
#      PrimaryAccentColor #016BFA (electric blue) with a #FFFFFF foreground, text
#      TextColor #0D1F5F (night blue), background BackgroundColor #FFFFFF, neutral
#      _NeutralColor #D6E0EA (enamel gray); its BaseFont is Montserrat;
#   2. each main palette color (#0D1F5F #016BFA #07E9F6 #D6E0EA) appears in the
#      theme (branding set, site styles) or in the rcHeader / rcHome CSS;
#   3. every logo a component shows comes from the rcBrandLogos static resource,
#      exists there, sits on the background color it was cropped from
#      (docs/brand/README.txt) and every <img> has alt="RutaCargo"; rcHeader shows
#      logo-negative.png on night blue;
#   4. the Montserrat @font-face is a stylesheet of the rcMontserrat static
#      resource whose src is a font file of that same resource (relative URL),
#      and the header component loads that stylesheet from the static resource;
#      the font's OFL.txt license is in the resource;
#   5. nothing references an external font or style host: no fonts.googleapis.com
#      or fonts.gstatic.com in the site bundle, the two components, the static
#      resources or a CSP trusted site (source and org); no http(s) URL in any CSS
#      of the site bundle, the components or the static resources, nor in the
#      head markup, other than the site's own host; no reference to the Daily
#      Brew font (assumption A3);
#   6. both static resources are cacheControl Public (source and org);
#   7. the published site carries the brand: an anonymous GET of the home page
#      returns 200 with --dxp-g-brand #016BFA and loads no font or stylesheet
#      from an external font host;
#   8. anonymous GETs (no session, no redirects followed) through the site URL:
#      the logo returns 200 with an image content type, the font stylesheet 200
#      text/css with the Montserrat @font-face, and the font file 200 with a font
#      content type. The host comes from the site's own DomainSite row.
#
# Usage: scripts/checks/brand-check.sh <org-alias>
set -euo pipefail
export LC_ALL=C

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi
cd "$(dirname "$0")/../.."

BUNDLE='force-app/main/default/digitalExperiences/site/RutaCargo1'
LWC_DIRS='force-app/main/default/lwc/rcHeader force-app/main/default/lwc/rcHome'
HEADER_JS='force-app/main/default/lwc/rcHeader/rcHeader.js'
SR='force-app/main/default/staticresources'
FONT_CSS_NAME='montserrat.css'
FONT_CSS="$SR/rcMontserrat/$FONT_CSS_NAME"
CSP_DIR='force-app/main/default/cspTrustedSites'
PALETTE='#0D1F5F #016BFA #07E9F6 #D6E0EA'
FONT_HOSTS='fonts\.googleapis\.com|fonts\.gstatic\.com'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
finish() {
    if [[ "$violations" -gt 0 ]]; then
        echo "brand-check: $violations violation(s) in $ORG"
        exit 1
    fi
    echo "brand-check: passed in $ORG"
    exit 0
}
upper() { tr '[:lower:]' '[:upper:]'; }
# Note: with pipefail, a pipe into "grep -q" can fail on SIGPIPE; every test
# below greps a file or a variable, never a pipe.

# Runs a SOQL query and prints the records as JSON; stops the script on an error.
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "ERROR: query failed: $1" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 3
    fi
    jq -c '.result.records' <<<"$out"
}

# Background color each logo was cropped from (docs/brand/README.txt).
logo_background() {
    case "$1" in
        logo-negative.png | logo-one-color-negative.png) echo '#0D1F5F' ;;
        logo-color.png | logo-one-color.png) echo '#FFFFFF' ;;
        isotype-tinto.png) echo '#016BFA' ;;
        logotype.png) echo '#D6E0EA' ;;
        *) echo '' ;;
    esac
}

# ─── 0. The site's own URL, from its DomainSite row ─────────────────────────
rows="$(query "SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE Site.Name = 'RutaCargo1' AND Site.SiteType = 'ChatterNetworkPicasso'")"
if [[ "$(jq 'length' <<<"$rows")" -ne 1 ]]; then
    fail "site RutaCargo1 (ChatterNetworkPicasso) has $(jq 'length' <<<"$rows") DomainSite rows, expected exactly 1"
    finish
fi
SITE_HOST="$(jq -r '.[0].Domain.Domain // empty' <<<"$rows")"
SITE_URL="https://$SITE_HOST$(jq -r '.[0].PathPrefix // ""' <<<"$rows")"
pass "site URL is $SITE_URL"

# ─── 1. Color roles and base font of the active branding set ───────────────
theme="$(ls "$BUNDLE"/sfdc_cms__theme/*/content.json 2>/dev/null | head -1 || true)"
branding_id="$(jq -r '.contentBody.activeBrandingSetId // empty' "$theme" 2>/dev/null || true)"
BRANDING="$BUNDLE/sfdc_cms__brandingSet/$branding_id/content.json"
if [[ -z "$branding_id" || ! -f "$BRANDING" ]]; then
    fail "the theme names no active branding set with a content.json"
    finish
fi
if [[ "$(jq -r '.contentBody.brandingSetType' "$BRANDING")" != "APP" ]]; then
    fail "branding set $branding_id is not of type APP"
fi
role() {  # role <token> <expected hex> <role description>
    local actual
    actual="$(jq -r --arg k "$1" '.contentBody.values[$k] // ""' "$BRANDING" | upper)"
    if [[ "$actual" == "$2" ]]; then
        pass "branding $1 is $2 ($3)"
    else
        fail "branding $1 is '$actual', expected $2 ($3)"
    fi
}
role PrimaryAccentColor '#016BFA' 'primary: electric blue'
role PrimaryAccentForegroundColor '#FFFFFF' 'text on primary'
role TextColor '#0D1F5F' 'text: night blue'
role BackgroundColor '#FFFFFF' 'background: white'
role _NeutralColor '#D6E0EA' 'neutral: enamel gray'
# The branding set accepts one family name only (no commas).
base_font="$(jq -r '.contentBody.values.BaseFont // ""' "$BRANDING")"
if [[ "$base_font" =~ ^[\'\"]?Montserrat[\'\"]?(,|$) ]]; then
    pass "branding BaseFont is Montserrat ($base_font)"
else
    fail "branding BaseFont is '$base_font', expected Montserrat"
fi

# ─── 2. Palette in the theme or the components ─────────────────────────────
# shellcheck disable=SC2086
css_files="$(find "$BUNDLE" $LWC_DIRS "$SR"/rcBrandLogos "$SR"/rcMontserrat -name '*.css' 2>/dev/null | sort || true)"
for hex in $PALETTE; do
    # shellcheck disable=SC2086
    if grep -qiF "$hex" "$BRANDING" $css_files 2>/dev/null; then
        pass "palette color $hex is in the theme or the components"
    else
        fail "palette color $hex is in neither the theme nor the components"
    fi
done

# ─── 3. Logos: from the static resource, on their own background, with alt ─
header_logos=''
for dir in $LWC_DIRS; do
    name="${dir##*/}"
    if [[ ! -d "$dir" ]]; then
        fail "component $name does not exist"
        continue
    fi
    logos="$(cat "$dir"/*.js "$dir"/*.html 2>/dev/null | grep -oE '[a-z-]+\.png' | sort -u || true)"
    if [[ -n "$logos" ]] && ! grep -qF "@salesforce/resourceUrl/rcBrandLogos" "$dir"/*.js; then
        fail "$name shows a logo without importing the rcBrandLogos static resource"
    fi
    for logo in $logos; do
        bg="$(logo_background "$logo")"
        if [[ -z "$bg" || ! -f "$SR/rcBrandLogos/$logo" ]]; then
            fail "$name shows $logo, which is not a logo of the rcBrandLogos static resource"
            continue
        fi
        if grep -qiE "background(-color)?: *$bg" "$dir"/*.css 2>/dev/null; then
            pass "$name shows $logo on its own background $bg"
        else
            fail "$name shows $logo without its own background $bg"
        fi
    done
    html="$(cat "$dir"/*.html 2>/dev/null | tr '\n' ' ' || true)"  # one line: tags span lines
    imgs="$(grep -o '<img' <<<"$html" | wc -l | tr -d ' ' || true)"
    alts="$(grep -o '<img[^>]*alt="RutaCargo"' <<<"$html" | wc -l | tr -d ' ' || true)"
    if [[ "$imgs" == "$alts" ]]; then
        pass "$name: every <img> ($imgs) has alt=\"RutaCargo\""
    else
        fail "$name: $imgs <img>, only $alts with alt=\"RutaCargo\""
    fi
    if [[ "$name" == "rcHeader" ]]; then
        header_logos="$logos"
    fi
done
if [[ "$header_logos" == "logo-negative.png" ]]; then
    pass "rcHeader shows logo-negative.png"
else
    fail "rcHeader shows '$header_logos', expected logo-negative.png only"
fi

# ─── 4. Montserrat @font-face from the static resource, loaded by the header ─
font_file=''
font_face="$(tr '\n' ' ' <"$FONT_CSS" 2>/dev/null | grep -oE '@font-face *\{[^}]*\}' | grep -E "font-family: *['\"]?Montserrat['\"]?;" | head -1 || true)"
if [[ -z "$font_face" ]]; then
    fail "$FONT_CSS declares no Montserrat @font-face"
else
    # A relative URL: the font file sits next to the stylesheet in the resource.
    font_file="$(grep -oE "url\(['\"]?[A-Za-z0-9._-]+['\"]?\)" <<<"$font_face" | head -1 | sed -E "s/^url\(['\"]?//; s/['\"]?\)$//" || true)"
    if [[ -z "$font_file" ]]; then
        fail "the Montserrat @font-face src is not a relative URL inside the rcMontserrat static resource"
    elif [[ ! -f "$SR/rcMontserrat/$font_file" ]]; then
        fail "the Montserrat @font-face src $font_file is not in $SR/rcMontserrat"
        font_file=''
    else
        pass "rcMontserrat/$FONT_CSS_NAME declares the Montserrat @font-face from the static resource ($font_file)"
    fi
fi
if grep -qF "@salesforce/resourceUrl/rcMontserrat" "$HEADER_JS" 2>/dev/null \
    && grep -qE "loadStyle" "$HEADER_JS" \
    && grep -qF "$FONT_CSS_NAME" "$HEADER_JS"; then
    pass "rcHeader loads $FONT_CSS_NAME from the rcMontserrat static resource"
else
    fail "rcHeader does not load $FONT_CSS_NAME from the rcMontserrat static resource with loadStyle"
fi
if grep -qF 'SIL Open Font License' "$SR/rcMontserrat/OFL.txt" 2>/dev/null; then
    pass "rcMontserrat carries the font's OFL.txt license"
else
    fail "rcMontserrat has no OFL.txt license"
fi

# ─── 5. No external font or style host ──────────────────────────────────────
# shellcheck disable=SC2086
hits="$(grep -rIilE "$FONT_HOSTS" "$BUNDLE" $LWC_DIRS "$SR"/rc* "$CSP_DIR" 2>/dev/null || true)"
if [[ -z "$hits" ]]; then
    pass "no source file references fonts.googleapis.com or fonts.gstatic.com"
else
    fail "external font host referenced in: $(paste -sd ',' - <<<"$hits")"
fi
# Absolute or protocol-relative URLs in CSS and head markup: only the site's own host.
head_markup="$(find "$BUNDLE" -name content.json -exec jq -r '.. | objects | (.headMarkup?, .customHeadTags?) | strings' {} + 2>/dev/null || true)"
# shellcheck disable=SC2086
urls="$( { cat $css_files 2>/dev/null; printf '%s\n' "$head_markup"; } \
    | grep -oiE '(https?:)?//[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | sed -E 's#^(https?:)?//##' | sort -u || true)"
external=''
for host in $urls; do
    if [[ "$(upper <<<"$host")" != "$(upper <<<"$SITE_HOST")" ]]; then
        external="${external:+$external,}$host"
    fi
done
if [[ -z "$external" ]]; then
    pass "CSS and head markup reference no host other than $SITE_HOST"
else
    fail "CSS or head markup reference external hosts: $external"
fi
# shellcheck disable=SC2086
if grep -rIiqE 'daily ?brew' "$BUNDLE" $LWC_DIRS "$SR"/rc* 2>/dev/null; then
    fail "a file references the Daily Brew font, which is not available (A3)"
else
    pass "no reference to the Daily Brew font (A3)"
fi
csp="$(query "SELECT DeveloperName, EndpointUrl FROM CspTrustedSite WHERE IsActive = true")"
csp_fonts="$(jq -r '.[] | select(.EndpointUrl | test("fonts\\.(googleapis|gstatic)\\.com"; "i")) | .DeveloperName' <<<"$csp")"
if [[ -z "$csp_fonts" ]]; then
    pass "no active CSP trusted site for an external font host in $ORG"
else
    fail "active CSP trusted sites for an external font host: $(paste -sd ',' - <<<"$csp_fonts")"
fi

# ─── 6. Static resources readable by the site: cacheControl Public ──────────
for res in rcBrandLogos rcMontserrat; do
    if grep -qF '<cacheControl>Public</cacheControl>' "$SR/$res.resource-meta.xml" 2>/dev/null; then
        pass "static resource $res is cacheControl Public in source"
    else
        fail "static resource $res is not cacheControl Public in source"
    fi
done
deployed="$(query "SELECT Name, CacheControl FROM StaticResource WHERE Name IN ('rcBrandLogos', 'rcMontserrat') AND NamespacePrefix = null")"
for res in rcBrandLogos rcMontserrat; do
    cc="$(jq -r --arg n "$res" '.[] | select(.Name == $n) | .CacheControl' <<<"$deployed")"
    if [[ "$cc" == "Public" ]]; then
        pass "static resource $res is Public in $ORG"
    else
        fail "static resource $res is '${cc:-missing}' in $ORG, expected Public"
    fi
done

# ─── 7. The published site carries the brand ────────────────────────────────
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
code="$(curl -s -o "$body_file" -w '%{http_code}' --max-time 60 "$SITE_URL/" || true)"
if [[ "$code" != "200" ]]; then
    fail "anonymous GET $SITE_URL/ returns $code, expected 200"
else
    if grep -qiE -- '--dxp-g-brand: *#016bfa' "$body_file"; then
        pass "the published home page carries --dxp-g-brand #016BFA"
    else
        fail "the published home page does not carry --dxp-g-brand #016BFA: publish the site"
    fi
    # A load of an external font or stylesheet: <link href>, src, url() or
    # @import. The platform's default CSP meta tag lists font hosts as allowed
    # sources; that allowance loads nothing, so it is not counted.
    if grep -qiE "(href|src)=[\"']?(https?:)?//($FONT_HOSTS)|url\([\"']?(https?:)?//($FONT_HOSTS)|@import[^;]*($FONT_HOSTS)" "$body_file"; then
        fail "the published home page loads a font or stylesheet from an external font host"
    else
        pass "the published home page loads nothing from an external font host"
    fi
fi

# ─── 8. Anonymous GETs of the logo, the font stylesheet and the font ────────
anonymous_get() {  # prints "<status> <content-type>" and keeps the body; no session
    curl -s -o "$body_file" -w '%{http_code} %{content_type}' --max-time 60 "$1" || true
}
url="$SITE_URL/sfsites/c/resource/rcBrandLogos/logo-negative.png"
read -r code ctype <<<"$(anonymous_get "$url")"
if [[ "$code" == "200" && "$ctype" == image/* ]]; then
    pass "anonymous GET $url returns 200 $ctype"
else
    fail "anonymous GET $url returns $code '${ctype:-}', expected 200 image/*"
fi
url="$SITE_URL/sfsites/c/resource/rcMontserrat/$FONT_CSS_NAME"
read -r code ctype <<<"$(anonymous_get "$url")"
served_css="$(tr '\n' ' ' <"$body_file")"
if [[ "$code" == "200" && "$ctype" == text/css* ]] && grep -qE "@font-face *\{[^}]*Montserrat" <<<"$served_css"; then
    pass "anonymous GET $url returns 200 $ctype with the Montserrat @font-face"
else
    fail "anonymous GET $url returns $code '${ctype:-}', expected 200 text/css with the Montserrat @font-face"
fi
if [[ -n "$font_file" ]]; then
    url="$SITE_URL/sfsites/c/resource/rcMontserrat/$font_file"
    read -r code ctype <<<"$(anonymous_get "$url")"
    if [[ "$code" == "200" && "$ctype" =~ ^(font/|application/(x-)?font|application/octet-stream) ]]; then
        pass "anonymous GET $url returns 200 $ctype"
    else
        fail "anonymous GET $url returns $code '${ctype:-}', expected 200 with a font content type"
    fi
fi

finish
