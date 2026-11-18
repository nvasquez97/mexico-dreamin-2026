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
#      theme (branding set, site styles) or in the CSS of a component of
#      LWC_DIRS (rcHeader, rcHome, rcTracking, rcDeliveryDetails and the
#      req-005 forms rcSignUp, rcLogin, rcForgotPassword);
#   3. every logo a component shows comes from the rcBrandLogos static resource,
#      exists there, sits on the background color it was cropped from
#      (docs/brand/README.txt) and every <img> has alt="Coffee Blazers Summit",
#      the name the logo shows (assumption A14); rcHeader shows exactly
#      isotype-tinto.png (on its electric-blue tile) and logo-negative.png (on
#      night blue);
#   4. the Montserrat @font-face is a stylesheet of the rcMontserrat static
#      resource whose src is a font file of that same resource (relative URL),
#      and the header component loads that stylesheet from the static resource;
#      the font's OFL.txt license is in the resource;
#   5. nothing references an external font or style host: no fonts.googleapis.com
#      or fonts.gstatic.com in the site bundle, the components, the static
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
#      content type. The host comes from the site's own DomainSite row;
#   9. the tricolor red #FF3636 and yellow #FFC91D is never a background or a
#      state color (manual p.6): no branding set value, no CSS background and
#      no theme layout or view attribute uses them;
#  10. every hex color of the branding set is a palette value (#0D1F5F #016BFA
#      #07E9F6 #D6E0EA #FFFFFF), so no derived shade off the palette; the
#      platform's success (_Success*) and offline (_Offline*) roles are not
#      checked (not reviewed; for the owner, A14);
#  11. no platform gray around the header and footer (AC-001.8): the
#      community_byo:scopedHeaderAndFooter layout paints its header and footer
#      content wrappers rgb(239, 240, 242) (#EFF0F2) in its own stylesheet, with
#      no styling hook, and a community_layout:section paints its
#      backgroundImageOverlay only when it also has a background image. So each
#      section of the header and footer regions must either have a background
#      image under a palette overlay (#0D1F5F or #FFFFFF), or expose none of the
#      wrapper: the branding set's row paddings (the section padding) are zero at
#      every breakpoint, the section has no min-height, and its content covers
#      it (the header region holds only components whose root box is night blue
#      or white, the footer region holds no component). The published home page
#      must carry the zero section paddings;
#  12. the full logo's visible artwork is never below 360 px wide (manual p.4,
#      AC-001.8): for every <img> of rcHeader, rcHome or rcTracking that shows a
#      full logo (not the isotype), in the component CSS at every breakpoint
#      where it is displayed, its width (or its height times the PNG's aspect
#      ratio, or its width attribute) is an absolute length, no max-width can
#      shrink it, and that width times the logo's visible-artwork ratio (the
#      columns of the PNG that differ from the background it was cropped from,
#      over its full width) is 360 px or more; at a 1366 px viewport the full
#      logo is displayed.
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
LWC_DIRS='force-app/main/default/lwc/rcHeader force-app/main/default/lwc/rcHome force-app/main/default/lwc/rcTracking force-app/main/default/lwc/rcDeliveryDetails force-app/main/default/lwc/rcSignUp force-app/main/default/lwc/rcLogin force-app/main/default/lwc/rcForgotPassword'
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
    alts="$(grep -o '<img[^>]*alt="Coffee Blazers Summit"' <<<"$html" | wc -l | tr -d ' ' || true)"
    if [[ "$imgs" == "$alts" ]]; then
        pass "$name: every <img> ($imgs) has alt=\"Coffee Blazers Summit\" (A14)"
    else
        fail "$name: $imgs <img>, only $alts with alt=\"Coffee Blazers Summit\" (A14)"
    fi
    if [[ "$name" == "rcHeader" ]]; then
        header_logos="$logos"
    fi
done
header_logos="$(tr '\n' ' ' <<<"$header_logos" | sed 's/ *$//')"
if [[ "$header_logos" == "isotype-tinto.png logo-negative.png" ]]; then
    pass "rcHeader shows isotype-tinto.png and logo-negative.png"
else
    fail "rcHeader shows '$header_logos', expected isotype-tinto.png and logo-negative.png"
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
# The section paddings the published page carries (used by check 11).
published_spacing=''
if [[ "$code" != "200" ]]; then
    fail "anonymous GET $SITE_URL/ returns $code, expected 200"
else
    published_spacing="$(grep -oE -- '--dxp-s-section-content-spacing-[a-z-]+: *[^;"}]+' "$body_file" | sort -u || true)"
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

# ─── 9. Tricolor red and yellow: never a background or state color ─────────
for hex in '#FF3636' '#FFC91D'; do
    keys="$(jq -r --arg h "$hex" '.contentBody.values | to_entries[] | select(.value | strings | ascii_upcase | contains($h)) | .key' "$BRANDING" | paste -sd ',' - || true)"
    if [[ -n "$keys" ]]; then
        fail "branding set uses tricolor $hex for $keys (manual p.6: never a background or state color)"
    else
        pass "branding set does not use tricolor $hex"
    fi
    # shellcheck disable=SC2086
    css_hits="$(grep -ilE "background(-color)?:[^;]*$hex" $css_files 2>/dev/null | paste -sd ',' - || true)"
    if [[ -n "$css_hits" ]]; then
        fail "CSS paints a background with tricolor $hex in: $css_hits"
    else
        pass "no CSS background uses tricolor $hex"
    fi
    layout_hits="$(grep -rilF "$hex" "$BUNDLE"/sfdc_cms__themeLayout "$BUNDLE"/sfdc_cms__view 2>/dev/null | paste -sd ',' - || true)"
    if [[ -n "$layout_hits" ]]; then
        fail "theme layouts or views use tricolor $hex in: $layout_hits"
    else
        pass "no theme layout or view uses tricolor $hex"
    fi
done

# ─── 10. Branding set hex colors are palette values ─────────────────────────
off_palette="$(jq -r '
  ["#0D1F5F", "#016BFA", "#07E9F6", "#D6E0EA", "#FFFFFF"] as $allowed
  | .contentBody.values | to_entries[]
  | select(.key | test("^_(Success|Offline)") | not)
  | select(.value | strings | test("^#[0-9A-Fa-f]{3,8}$"))
  | select(.value | ascii_upcase | IN($allowed[]) | not)
  | "\(.key)=\(.value)"' "$BRANDING" | paste -sd ',' - || true)"
if [[ -z "$off_palette" ]]; then
    pass "every branding set hex color is a palette value (success and offline roles not checked)"
else
    fail "branding set colors off the palette: $off_palette"
fi

# ─── 11. No platform gray around the header and footer ──────────────────────
# community_byo:scopedHeaderAndFooter paints its header and footer content
# wrappers rgb(239, 240, 242) in its own stylesheet (no styling hook), and a
# community_layout:section sets its overlay color only when it has a background
# image. A band is gray-free when each of its sections has an image under a
# palette overlay, or exposes none of the wrapper (zero padding from the
# branding set's row paddings, no min-height, one column, content that covers it).
band_report="$(python3 -I - "$BUNDLE" "$BRANDING" force-app/main/default/lwc <<'PY'
import json
import pathlib
import re
import sys

bundle, branding, lwc = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
PALETTE_BG = {"#0D1F5F", "#FFFFFF"}
PADDINGS = ["HorizontalRowPaddingDesktop", "HorizontalRowPaddingMobile",
            "VerticalRowPaddingDesktop", "VerticalRowPaddingMobile"]
# A zero has at least one digit: an empty or a missing padding is not zero.
ZERO = re.compile(r"(0+(\.0*)?|\.0+)(px|rem|em|%)?")
values = json.loads(branding.read_text())["contentBody"]["values"]
nonzero = [f"{k} missing" if k not in values else f"{k}={values[k]!r}" for k in PADDINGS
           if k not in values or not ZERO.fullmatch(str(values[k]).strip())]


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


def components(node):
    return [n for n in walk(node) if n.get("type") == "component" and n is not node]


def root_background(definition):
    """Palette background of the component's root element box, or None."""
    if not definition.startswith("c:"):
        return None
    name = definition[2:]
    folder = lwc / name
    html = (folder / f"{name}.html").read_text() if (folder / f"{name}.html").exists() else ""
    css = (folder / f"{name}.css").read_text() if (folder / f"{name}.css").exists() else ""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"@media[^{]+\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}", "", css)
    host = re.search(r":host\s*\{([^}]*)\}", css)
    if not host or not re.search(r"display:\s*block", host.group(1)):
        return None
    first = re.search(r"<template>\s*<\w+[^>]*\bclass=\"([\w-]+)", html)
    if not first:
        return None
    rule = re.search(r"(?:^|\})\s*\." + re.escape(first.group(1)) + r"\s*\{([^}]*)\}", css)
    if not rule:
        return None
    bg = re.search(r"background(?:-color)?:\s*(#[0-9a-fA-F]{6})\s*;", rule.group(1))
    return bg.group(1).upper() if bg and bg.group(1).upper() in PALETTE_BG else None


found = False
for layout in sorted(bundle.glob("sfdc_cms__themeLayout/*/content.json")):
    for shf in walk(json.loads(layout.read_text())):
        if shf.get("definition") != "community_byo:scopedHeaderAndFooter":
            continue
        for region in shf.get("children", []):
            if region.get("name") not in ("header", "footer"):
                continue
            found = True
            where = f"{layout.parent.name} {region['name']} band"
            sections = [c for c in region.get("children", []) if c.get("definition") == "community_layout:section"]
            others = [c.get("definition") for c in region.get("children", []) if c.get("definition") != "community_layout:section"]
            if others:
                print(f"FAIL {where}: holds {', '.join(others)} outside a section, over the platform gray")
            if not sections and not others:
                print(f"OK {where}: empty, nothing over the platform gray")
            for section in sections:
                attrs = section.get("attributes", {})
                overlay = str(attrs.get("backgroundImageOverlay", "")).upper()
                image = attrs.get("backgroundImageConfig")
                if image not in ("", None, {}) and overlay in PALETTE_BG:
                    print(f"OK {where}: section has a background image under the palette overlay {overlay}")
                    continue
                problems = []
                if nonzero:
                    problems.append("the branding set's row paddings are not zero (" + ", ".join(nonzero) + "): the platform gray shows in the section padding (an overlay without a background image is not painted)")
                if str(attrs.get("sectionMinHeight", "")).strip():
                    problems.append(f"sectionMinHeight is {attrs['sectionMinHeight']!r}")
                try:
                    columns = json.loads(attrs.get("sectionConfig") or "{}").get("columns", [])
                except ValueError:
                    columns = []
                if len(columns) != 1:
                    problems.append(f"{len(columns)} columns (gutters show the gray)")
                inner = components(section)
                if region["name"] == "footer" and inner:
                    problems.append("the footer holds " + ", ".join(c.get("definition", "?") for c in inner) + ", which do not cover the gray")
                if region["name"] == "header":
                    if len(inner) > 1:
                        problems.append(f"{len(inner)} components (the spacer between them shows the gray)")
                    for comp in inner:
                        if root_background(comp.get("definition", "")) is None:
                            problems.append(f"{comp.get('definition')} does not paint its whole box night blue or white")
                if problems:
                    for problem in problems:
                        print(f"FAIL {where}: {problem}")
                else:
                    covered = ", ".join(c["definition"] for c in inner) or "no component"
                    print(f"OK {where}: no padding, no min-height, one column, covered by {covered}")
                    print("ZERO_PADDING")
if not found:
    print("FAIL no scopedHeaderAndFooter theme layout with header and footer regions found")
PY
)"
needs_zero=0
while IFS= read -r line; do
    case "$line" in
        OK*) pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
        ZERO_PADDING) needs_zero=1 ;;
    esac
done <<<"$band_report"
if [[ "$needs_zero" -eq 1 ]]; then
    # All eight section padding hooks published, all zero.
    hooks="$(grep -c . <<<"$published_spacing" || true)"
    # A zero has at least one digit: an empty hook value is not zero.
    nonzero_hooks="$(grep -vE ': *(0+(\.0*)?|\.0+)(px|rem|em|%)? *$' <<<"$published_spacing" | paste -sd ',' - || true)"
    if [[ -n "$published_spacing" && "$hooks" -eq 8 && -z "$nonzero_hooks" ]]; then
        pass "the published home page carries zero section paddings (8 hooks)"
    else
        fail "the published home page section paddings are not all zero (${nonzero_hooks:-$hooks hooks found}): publish the site"
    fi
fi

# ─── 12. Full logo: visible artwork never below 360 px wide ─────────────────
# shellcheck disable=SC2086
size_report="$(python3 -I - "$SR/rcBrandLogos" $LWC_DIRS <<'PY'
import pathlib
import re
import struct
import sys
import zlib

logos, dirs = pathlib.Path(sys.argv[1]), [pathlib.Path(d) for d in sys.argv[2:]]
# Each full logo and the background it was cropped from (docs/brand/README.txt,
# the same table as logo_background above).
FULL = {"logo-color.png": "#FFFFFF", "logo-negative.png": "#0D1F5F",
        "logo-one-color.png": "#FFFFFF", "logo-one-color-negative.png": "#0D1F5F",
        "logotype.png": "#D6E0EA"}
MIN_PX = 360
DESKTOP_PX = 1366
# A pixel is artwork when a channel differs from the background by more than this.
TOLERANCE = 24


def absolute_px(value):
    match = re.fullmatch(r"([0-9]*\.?[0-9]+)(px|rem|em)", (value or "").strip())
    if not match:
        return None
    number = float(match.group(1))
    return number if match.group(2) == "px" else number * 16


def png_ratio(path):
    width, height = struct.unpack(">II", path.read_bytes()[16:24])
    return width / height


def visible_ratio(path, background):
    """Width of the columns that differ from the background, over the full width."""
    data = path.read_bytes()
    pos, idat = 8, b""
    width = height = depth = color = interlace = None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
    if depth != 8 or color not in (2, 6) or interlace:
        raise ValueError(f"unsupported PNG (bit depth {depth}, color type {color}, interlace {interlace})")
    bpp = 3 if color == 2 else 4
    stride = width * bpp
    raw = zlib.decompress(idat)
    bg = [int(background[i:i + 2], 16) for i in (1, 3, 5)]
    prev = bytearray(stride)
    left, right = width, -1
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            if kind == 1:
                line[x] = (line[x] + a) & 255
            elif kind == 2:
                line[x] = (line[x] + b) & 255
            elif kind == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif kind == 4:
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        for x in range(width):
            o = x * bpp
            if (abs(line[o] - bg[0]) > TOLERANCE or abs(line[o + 1] - bg[1]) > TOLERANCE
                    or abs(line[o + 2] - bg[2]) > TOLERANCE):
                left, right = min(left, x), max(right, x)
        prev = line
    return 0.0 if right < 0 else (right - left + 1) / width


def declarations(body):
    out = {}
    for item in body.split(";"):
        if ":" in item:
            key, value = item.split(":", 1)
            out[key.strip().lower()] = value.strip().lower()
    return out


def rules(css):
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    found = []
    media_re = re.compile(r"@media([^{]+)\{((?:[^{}]*\{[^{}]*\})*[^{}]*)\}")
    for media in media_re.finditer(css):
        condition = media.group(1)
        minimum = re.search(r"min-width:\s*([0-9.]+)(px|em|rem)", condition)
        if not minimum or re.search(r"max-width|orientation|print", condition):
            found.append((None, condition.strip(), {}))
            continue
        min_px = float(minimum.group(1)) * (1 if minimum.group(2) == "px" else 16)
        for rule in re.finditer(r"([^{}]+)\{([^{}]*)\}", media.group(2)):
            found.append((min_px, rule.group(1), declarations(rule.group(2))))
    base = media_re.sub("", css)
    for rule in re.finditer(r"([^{}]+)\{([^{}]*)\}", base):
        found.append((0.0, rule.group(1), declarations(rule.group(2))))
    return found


def targets(selector, classes):
    for part in selector.split(","):
        last = part.strip().split()[-1] if part.strip() else ""
        last = re.sub(r":[a-z-]+(\([^)]*\))?$", "", last)
        if any(re.search(r"\." + re.escape(c) + r"(?![\w-])", last) for c in classes):
            return True
    return False


for folder in dirs:
    name = folder.name
    js = "".join(p.read_text() for p in folder.glob("*.js"))
    html = " ".join(p.read_text() for p in folder.glob("*.html")).replace("\n", " ")
    css = "".join(p.read_text() for p in folder.glob("*.css"))
    consts = dict(re.findall(r'const\s+(\w+)\s*=\s*"([A-Za-z0-9-]+\.png)"', js))
    fields = {}
    for field, template in re.findall(r"(\w+)\s*=\s*\x60([^\x60]*)\x60", js):
        pngs = re.findall(r"[A-Za-z0-9-]+\.png", template)
        pngs += [consts[c] for c in re.findall(r"\$\{(\w+)\}", template) if c in consts]
        if pngs:
            fields[field] = pngs[0]
    parsed = rules(css)
    for tag in re.findall(r"<img\b[^>]*>", html):
        src = re.search(r"src=\{(\w+)\}", tag)
        logo = fields.get(src.group(1)) if src else None
        if logo is None:
            literal = re.search(r'src="[^"]*?([A-Za-z0-9-]+\.png)"', tag)
            logo = literal.group(1) if literal else None
        if logo not in FULL:
            continue
        cls = re.search(r'class="([^"]*)"', tag)
        classes = cls.group(1).split() if cls else []
        attr_width = re.search(r'\bwidth="([0-9]+)"', tag)
        ratio = png_ratio(logos / logo)
        try:
            artwork = visible_ratio(logos / logo, FULL[logo])
        except (ValueError, zlib.error) as error:
            print(f"FAIL {name}: cannot measure the visible artwork of {logo}: {error}")
            continue
        mine = [r for r in parsed if r[0] is not None and targets(r[1], classes)]
        unsupported = [r for r in parsed if r[0] is None]
        if unsupported:
            print(f"FAIL {name}: media query '{unsupported[0][1]}' cannot be checked for the logo size")
        problems, shown = [], []
        contexts = sorted({0.0} | {r[0] for r in mine})
        desktop = max(c for c in contexts if c <= DESKTOP_PX)
        for context in contexts:
            style = {}
            for min_px, _, decls in sorted(mine, key=lambda r: r[0]):
                if min_px <= context:
                    style.update(decls)
            if style.get("display") == "none":
                if context == desktop:
                    problems.append(f"{logo} is not displayed at a {DESKTOP_PX} px viewport")
                continue
            where = "every width" if context == 0 else f"min-width {context:g}px"
            width, height = style.get("width"), style.get("height")
            if width and width != "auto":
                rendered = absolute_px(width)
                if rendered is None:
                    problems.append(f"{logo} at {where}: width '{width}' is not an absolute length")
                    continue
            elif height and height != "auto":
                h = absolute_px(height)
                if h is None:
                    problems.append(f"{logo} at {where}: height '{height}' is not an absolute length")
                    continue
                rendered = h * ratio
            elif attr_width:
                rendered = float(attr_width.group(1))
            else:
                problems.append(f"{logo} at {where}: no width")
                continue
            max_width = style.get("max-width")
            if max_width and max_width != "none":
                cap = absolute_px(max_width)
                if cap is None:
                    problems.append(f"{logo} at {where}: max-width '{max_width}' is not an absolute length")
                    continue
                rendered = min(rendered, cap)
            visible = rendered * artwork
            at_desktop = f", the box at a {DESKTOP_PX} px viewport" if context == desktop else ""
            if visible < MIN_PX:
                problems.append(f"{logo} at {where}: {rendered:.0f} px box x {artwork:.3f} visible artwork = "
                                f"{visible:.0f} px of logo, below {MIN_PX} px{at_desktop}")
            else:
                shown.append(f"{where}: {rendered:.0f} px box, {visible:.0f} px visible{at_desktop}")
        if problems:
            for problem in problems:
                print(f"FAIL {name}: {problem}")
        else:
            print(f"OK {name}: {logo} visible artwork ({artwork:.3f} of its width) is never below "
                  f"{MIN_PX} px ({'; '.join(shown) or 'not displayed'})")
PY
)"
if [[ -z "$size_report" ]]; then
    fail "no full logo found in rcHeader, rcHome or rcTracking to check its minimum size"
fi
while IFS= read -r line; do
    case "$line" in
        OK*) pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
    esac
done <<<"$size_report"

finish
