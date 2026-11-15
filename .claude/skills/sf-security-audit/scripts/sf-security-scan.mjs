#!/usr/bin/env node
// Heuristic Salesforce security scanner (no dependencies).
// Produces CANDIDATE findings for the sf-security-* reviewers to triage.
// It favors recall over precision: every finding must be confirmed by reading the code/metadata.
//
// Usage: node sf-security-scan.mjs [--format md|json] [--out <file>] [--fail-on <severity>] [path...]
// Rule catalog: ../references/scanner-rules.md

import fs from 'node:fs';
import path from 'node:path';

const SEVERITIES = ['Critical', 'High', 'Medium', 'Low', 'Info'];
const SKIP_DIRS = new Set([
  'node_modules',
  '.git',
  '.sf',
  '.sfdx',
  '.claude',
  'coverage',
  '.localdevserver',
  '.husky',
  '.vscode',
  '.security-reports'
]);
const SKIP_FILES = new Set(['package-lock.json', 'yarn.lock', 'pnpm-lock.yaml']);
const TEXT_EXT = new Set([
  '.cls', '.trigger', '.apex', '.soql', '.js', '.mjs', '.cjs', '.ts', '.html', '.css', '.xml',
  '.page', '.component', '.cmp', '.app', '.evt', '.design', '.auradoc', '.json', '.yml', '.yaml',
  '.properties', '.txt', '.md', '.sh', '.env', '.cfg', '.ini', '.resource'
]);
const KEY_FILE_RE = /\.(pem|key|p12|pfx|jks|keystore)$/i;
const MAX_BYTES = 2 * 1024 * 1024;

// Field / key names that suggest a stored credential.
const SECRET_NAME_RE =
  /(pass(word|wd)|pwd|secret|token|api_?key|apikey|private_?key|credential|authorization|bearer|access_?key|signing_?key)/i;
const PLACEHOLDER_RE =
  /^(x+|\*+|<[^>]*>|\$\{[^}]*\}|\{![^}]*\}|\{\{[^}]*\}\}|changeme|change_me|password|secret|token|your[_-]?\w*|example\w*|dummy\w*|sample\w*|placeholder\w*|null|undefined|none|todo)$/i;

// ---------------------------------------------------------------- args
const args = process.argv.slice(2);
let format = 'md';
let outFile = null;
let failOn = null;
const targets = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--format') format = args[++i];
  else if (a === '--out') outFile = args[++i];
  else if (a === '--fail-on') failOn = normalizeSeverity(args[++i]);
  else if (a === '-h' || a === '--help') {
    process.stdout.write(
      'Usage: node sf-security-scan.mjs [--format md|json] [--out <file>] [--fail-on <severity>] [path...]\n'
    );
    process.exit(0);
  } else targets.push(a);
}
if (!targets.length) targets.push('.');
if (!['md', 'json'].includes(format)) {
  process.stderr.write(`Unknown --format "${format}" (use md or json)\n`);
  process.exit(2);
}

function normalizeSeverity(s) {
  const found = SEVERITIES.find((x) => x.toLowerCase() === String(s).toLowerCase());
  if (!found) {
    process.stderr.write(`Unknown severity "${s}"\n`);
    process.exit(2);
  }
  return found;
}

// ---------------------------------------------------------------- findings
const findings = [];
let filesScanned = 0;

function add(rule, severity, ctx, line, message) {
  findings.push({
    rule,
    severity,
    file: ctx.rel,
    line,
    message,
    snippet: line ? ctx.lineText(line).trim().slice(0, 200) : ''
  });
}

function raise(severity) {
  const i = SEVERITIES.indexOf(severity);
  return SEVERITIES[Math.max(0, i - 1)];
}

// ---------------------------------------------------------------- file context
function makeCtx(file, text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) starts.push(i + 1);
  let lines = null;
  return {
    file,
    rel: path.relative(process.cwd(), file) || file,
    text,
    lineOf(idx) {
      let lo = 0;
      let hi = starts.length - 1;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (starts[mid] <= idx) lo = mid;
        else hi = mid - 1;
      }
      return lo + 1;
    },
    lineText(n) {
      if (!lines) lines = text.split('\n');
      return lines[n - 1] ?? '';
    }
  };
}

// Replace comments with spaces (newlines preserved) so line numbers stay valid.
function stripComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') {
        out += ' ';
        i++;
      }
      continue;
    }
    if (c === '/' && d === '*') {
      out += '  ';
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      if (i < n) {
        out += '  ';
        i += 2;
      }
      continue;
    }
    if (c === "'" || c === '"' || c === '`') {
      const q = c;
      out += c;
      i++;
      while (i < n && src[i] !== q) {
        if (src[i] === '\\' && i + 1 < n) {
          out += src[i] + src[i + 1];
          i += 2;
          continue;
        }
        if (src[i] === '\n' && q !== '`') break;
        out += src[i];
        i++;
      }
      if (i < n && src[i] === q) {
        out += q;
        i++;
      }
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

// Returns the raw text between the parenthesis at openIdx and its match.
function extractParens(code, openIdx) {
  let depth = 0;
  let q = null;
  for (let i = openIdx; i < code.length; i++) {
    const c = code[i];
    if (q) {
      if (c === '\\') i++;
      else if (c === q) q = null;
      continue;
    }
    if (c === "'" || c === '"') q = c;
    else if (c === '(') depth++;
    else if (c === ')') {
      depth--;
      if (depth === 0) return code.slice(openIdx + 1, i);
    }
  }
  return code.slice(openIdx + 1);
}

function firstArg(argText) {
  let depth = 0;
  let q = null;
  for (let i = 0; i < argText.length; i++) {
    const c = argText[i];
    if (q) {
      if (c === '\\') i++;
      else if (c === q) q = null;
      continue;
    }
    if (c === "'" || c === '"') q = c;
    else if ('([{<'.includes(c)) depth++;
    else if (')]}>'.includes(c)) depth--;
    else if (c === ',' && depth === 0) return argText.slice(0, i).trim();
  }
  return argText.trim();
}

const isStringLiteral = (s) => /^'(?:[^'\\]|\\.)*'$/.test(s) || /^"(?:[^"\\]|\\.)*"$/.test(s);

function braceDepthAt(code, idx) {
  let depth = 0;
  let q = null;
  for (let i = 0; i < idx; i++) {
    const c = code[i];
    if (q) {
      if (c === '\\') i++;
      else if (c === q) q = null;
      continue;
    }
    if (c === "'") q = c;
    else if (c === '{') depth++;
    else if (c === '}') depth--;
  }
  return depth;
}

function lineList(nums, max = 12) {
  const shown = nums.slice(0, max).join(', ');
  return nums.length > max ? `${shown}, … (+${nums.length - max})` : shown;
}

// ---------------------------------------------------------------- XML helpers
function blocks(text, tag) {
  const re = new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, 'g');
  return [...text.matchAll(re)].map((m) => ({ body: m[1], index: m.index }));
}
function tagVal(body, tag) {
  const m = body.match(new RegExp(`<${tag}(?:\\s[^>]*)?>\\s*([\\s\\S]*?)\\s*</${tag}>`));
  return m ? m[1] : null;
}
const isTrue = (v) => v === 'true';

function apiVersionFor(file) {
  try {
    const m = fs.readFileSync(`${file}-meta.xml`, 'utf8').match(/<apiVersion>\s*([\d.]+)\s*<\/apiVersion>/);
    return m ? parseFloat(m[1]) : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------- secrets (all text files)
const SECRET_PATTERNS = [
  ['SEC-PRIVATE-KEY', 'Critical', /-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----/g, 'Private key material in source'],
  ['SEC-SFDX-AUTH-URL', 'Critical', /force:\/\/[A-Za-z0-9._~-]+:[^@\s'"]{10,}@[A-Za-z0-9.-]+/g, 'SFDX auth URL (refresh token) in source'],
  ['SEC-AWS-KEY', 'Critical', /\bAKIA[0-9A-Z]{16}\b/g, 'AWS access key id in source'],
  ['SEC-TOKEN', 'High', /\b(?:ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk_live_[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{35})\b/g, 'Third-party API token in source'],
  ['SEC-JWT', 'High', /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g, 'Hardcoded JWT in source'],
  ['SEC-BEARER', 'High', /['"]Bearer\s+[A-Za-z0-9._~+/=-]{16,}['"]/g, 'Hardcoded bearer token'],
  ['SEC-SESSION-ID', 'High', /\b00D[A-Za-z0-9]{12,15}![A-Za-z0-9._]{40,}/g, 'Salesforce session id / access token in source']
];
const SECRET_ASSIGN_RE =
  /(?<key>[A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)[A-Za-z0-9_.-]*)["']?\s*[:=]\s*["'](?<val>[^"'\s]{8,})["']/gi;
const SECRET_XML_RE = /<(?<key>\w*(?:password|secret|token|apikey|api_key|privatekey)\w*)>(?<val>[^<\s]{8,})<\/\k<key>>/gi;
// Metadata types whose credential elements get type-specific rules (avoid duplicates).
const SECRET_XML_SKIP_RE = /\.(namedCredential|connectedApp|eca\w*|md)-meta\.xml$/;

function scanSecrets(ctx) {
  for (const [rule, sev, re, msg] of SECRET_PATTERNS) {
    for (const m of ctx.text.matchAll(re)) add(rule, sev, ctx, ctx.lineOf(m.index), msg);
  }
  for (const m of ctx.text.matchAll(SECRET_ASSIGN_RE)) {
    if (PLACEHOLDER_RE.test(m.groups.val) || /^\{!\$Credential/i.test(m.groups.val)) continue;
    add('SEC-HARDCODED-SECRET', 'High', ctx, ctx.lineOf(m.index), `Possible hardcoded secret assigned to "${m.groups.key}"`);
  }
  if (ctx.file.endsWith('.xml') && !SECRET_XML_SKIP_RE.test(ctx.file)) {
    for (const m of ctx.text.matchAll(SECRET_XML_RE)) {
      if (PLACEHOLDER_RE.test(m.groups.val)) continue;
      add('SEC-HARDCODED-SECRET', 'High', ctx, ctx.lineOf(m.index), `Possible secret value in XML element <${m.groups.key}>`);
    }
  }
}

// ---------------------------------------------------------------- Apex
const HIGH_ENTRY_KINDS = new Set(['@RestResource', 'webservice', '@HttpGet', '@HttpPost', '@HttpPut', '@HttpPatch', '@HttpDelete']);

function scanApex(ctx, isTrigger) {
  const code = stripComments(ctx.text);
  const api = apiVersionFor(ctx.file);
  const modern = api !== null && api >= 67;
  const apiLabel = api === null ? 'unknown API version (treated as < 67)' : `API ${api}`;
  const isTest = /@isTest\b/i.test(code);

  if (isTest) {
    for (const m of code.matchAll(/@isTest\s*\(\s*SeeAllData\s*=\s*true\s*\)/gi))
      add('APEX-SEEALLDATA', 'Low', ctx, ctx.lineOf(m.index), 'Test uses SeeAllData=true (depends on and can expose org data)');
    return;
  }

  // Entry points (public attack surface)
  const entries = new Map();
  const entryRe =
    /(@AuraEnabled|@RestResource|@Http(?:Get|Post|Put|Patch|Delete)|@RemoteAction|@InvocableMethod|@InvocableVariable|\bwebservice(?=\s+static)|\bglobal(?=\s+(?:static\s+)?[\w<>,.\s]+\s+\w+\s*\()|Messaging\.InboundEmailHandler)/gi;
  for (const m of code.matchAll(entryRe)) {
    const kind = m[1].startsWith('@') ? m[1] : m[1].toLowerCase();
    if (kind.toLowerCase() === '@invocablevariable') continue;
    if (!entries.has(kind)) entries.set(kind, []);
    entries.get(kind).push(ctx.lineOf(m.index));
  }
  for (const [kind, lines] of entries) {
    const high = HIGH_ENTRY_KINDS.has(kind) || kind === 'Messaging.InboundEmailHandler';
    add(
      'APEX-ENTRY-POINT',
      high ? 'Medium' : 'Info',
      ctx,
      lines[0],
      `${lines.length} ${kind} entry point(s) at lines ${lineList(lines)} — callable by any user with class access (guest too if granted). Verify authN context, sharing and CRUD/FLS on each.`
    );
  }
  const hasEntry = entries.size > 0;

  // Sharing declarations
  if (!isTrigger) {
    const classRe =
      /^[ \t]*((?:(?:public|private|protected|global|virtual|abstract|with\s+sharing|without\s+sharing|inherited\s+sharing)\s+)*)class\s+(\w+)([^{]*)\{/gim;
    for (const m of code.matchAll(classRe)) {
      const mods = m[1].toLowerCase();
      const name = m[2];
      if (/extends\s+Exception\b/i.test(m[3])) continue;
      const line = ctx.lineOf(m.index);
      if (/without\s+sharing/.test(mods)) {
        add(
          'APEX-WITHOUT-SHARING',
          'High',
          ctx,
          line,
          `Class ${name} is "without sharing" — record sharing is bypassed${hasEntry ? ' and the file exposes entry points' : ''}. Requires documented justification and minimal scope.`
        );
      } else if (!/(with|inherited)\s+sharing/.test(mods) && braceDepthAt(code, m.index) === 0) {
        if (modern) {
          add('APEX-NO-SHARING-KEYWORD', 'Low', ctx, line, `Class ${name} has no sharing keyword (${apiLabel} defaults to with sharing). Declare it explicitly.`);
        } else {
          add(
            'APEX-NO-SHARING-KEYWORD',
            hasEntry ? 'High' : 'Medium',
            ctx,
            line,
            `Class ${name} has no sharing keyword on ${apiLabel} — may run without sharing depending on caller${hasEntry ? '; file has entry points' : ''}.`
          );
        }
      }
    }
  } else {
    add('TRIGGER-SYSTEM-CONTEXT', 'Info', ctx, 1, 'Trigger logic runs in system context; delegate to a handler class with an explicit sharing keyword and user-mode data access.');
  }

  // Dynamic SOQL / SOSL
  const hasEscape = /escapeSingleQuotes/.test(code);
  for (const m of code.matchAll(/\b(Database\.(?:query|countQuery|getQueryLocator|queryWithBinds|countQueryWithBinds|getQueryLocatorWithBinds)|Search\.query)\s*\(/gi)) {
    const open = m.index + m[0].length - 1;
    const arg = firstArg(extractParens(code, open));
    const line = ctx.lineOf(m.index);
    if (!arg || arg.startsWith('[')) continue;
    const parts = arg.split(/\s*\+\s*/);
    if (parts.every(isStringLiteral)) continue;
    let severity = 'Medium';
    let detail = 'Dynamic query — verify every input is a bind variable or allowlisted.';
    if (arg.includes('+')) {
      severity = 'High';
      detail = 'Query string concatenated inline with variables.';
    } else if (/^\w+$/.test(arg)) {
      const assignRe = new RegExp(`\\b${arg}\\s*(\\+=|=)\\s*([^;]*);`, 'g');
      const concatLines = [];
      for (const a of code.matchAll(assignRe)) {
        if (a[1] === '+=' || /\+|String\.format|\.replace|\.join/.test(a[2])) concatLines.push(ctx.lineOf(a.index));
      }
      if (concatLines.length) {
        severity = 'High';
        detail = `Query string "${arg}" built by concatenation/formatting (lines ${lineList(concatLines)}).`;
      } else if (/WithBinds/i.test(m[1])) {
        continue;
      }
    }
    if (hasEscape && severity === 'High') {
      severity = 'Medium';
      detail += ' escapeSingleQuotes present — insufficient for unquoted contexts (field/object names, ORDER BY, LIMIT, IN lists).';
    }
    add('APEX-SOQL-INJECTION', severity, ctx, line, `${m[1]}: ${detail} Prefer static SOQL or Database.queryWithBinds with an allowlist for identifiers.`);
  }

  for (const m of code.matchAll(/\bType\.forName\s*\(/g)) {
    const arg = firstArg(extractParens(code, m.index + m[0].length - 1));
    if (!isStringLiteral(arg)) add('APEX-TYPE-FORNAME', 'Medium', ctx, ctx.lineOf(m.index), 'Type.forName with a non-literal argument — arbitrary class instantiation if input is user-controlled.');
  }
  for (const m of code.matchAll(/Schema\.getGlobalDescribe\(\)\s*\.get\s*\(/g)) {
    const arg = firstArg(extractParens(code, m.index + m[0].length - 1));
    if (!isStringLiteral(arg)) add('APEX-DESCRIBE-INPUT', 'Low', ctx, ctx.lineOf(m.index), 'Object resolved from a variable — validate against an allowlist if user-supplied.');
  }

  // Access mode (CRUD/FLS)
  for (const m of code.matchAll(/\bWITH\s+SYSTEM_MODE\b|AccessLevel\.SYSTEM_MODE|\b(?:insert|update|upsert|delete|undelete|merge)\s+as\s+system\b/gi))
    add('APEX-EXPLICIT-SYSTEM-MODE', 'Medium', ctx, ctx.lineOf(m.index), 'Explicit system mode — bypasses CRUD/FLS. Must be justified, documented and isolated.');
  if (modern) {
    for (const m of code.matchAll(/\bWITH\s+SECURITY_ENFORCED\b/gi))
      add('APEX-SECURITY-ENFORCED', 'Info', ctx, ctx.lineOf(m.index), 'WITH SECURITY_ENFORCED is not allowed in API 67+; use WITH USER_MODE.');
  } else {
    const manualChecks = /Security\.stripInaccessible|\.is(Accessible|Createable|Updateable|Deletable)\s*\(/.test(code);
    const soqlLines = [];
    for (const m of code.matchAll(/\[\s*(SELECT|FIND)\b[\s\S]*?\]/gi)) {
      if (!/WITH\s+(USER_MODE|SECURITY_ENFORCED)/i.test(m[0])) soqlLines.push(ctx.lineOf(m.index));
    }
    for (const m of code.matchAll(/\b(Database\.(?:query|getQueryLocator|countQuery))\s*\(/gi)) {
      if (!/AccessLevel\.USER_MODE|WITH\s+USER_MODE/i.test(extractParens(code, m.index + m[0].length - 1))) soqlLines.push(ctx.lineOf(m.index));
    }
    const dmlLines = [];
    for (const m of code.matchAll(/^[ \t]*(?:insert|update|upsert|delete|undelete|merge)\s+(?!as\s+user\b)[\w(]/gim)) dmlLines.push(ctx.lineOf(m.index));
    for (const m of code.matchAll(/\bDatabase\.(?:insert|update|upsert|delete|undelete|merge)(?:Async|Immediate)?\s*\(/gi)) {
      if (!/AccessLevel\.USER_MODE/.test(extractParens(code, m.index + m[0].length - 1))) dmlLines.push(ctx.lineOf(m.index));
    }
    const sev = manualChecks ? 'Low' : 'Medium';
    const note = manualChecks ? ' Manual CRUD/FLS checks detected — verify they cover every path.' : '';
    if (soqlLines.length)
      add('APEX-SOQL-SYSTEM-MODE', sev, ctx, soqlLines[0], `${soqlLines.length} quer(ies) run in system mode on ${apiLabel} (lines ${lineList(soqlLines)}). Use WITH USER_MODE / AccessLevel.USER_MODE.${note}`);
    if (dmlLines.length)
      add('APEX-DML-SYSTEM-MODE', sev, ctx, dmlLines[0], `${dmlLines.length} DML operation(s) run in system mode on ${apiLabel} (lines ${lineList(dmlLines)}). Use "as user" / AccessLevel.USER_MODE.${note}`);
  }

  // Sensitive data handling
  for (const m of code.matchAll(/UserInfo\.getSessionId\s*\(/g))
    add('APEX-SESSION-ID', 'Medium', ctx, ctx.lineOf(m.index), 'Session id retrieved in Apex — never send it to the client or third parties; use Named Credentials for callouts.');
  for (const m of code.matchAll(/System\.debug\s*\(/gi)) {
    const arg = extractParens(code, m.index + m[0].length - 1);
    if (/(password|passwd|secret|token|session|authorization|ssn|credit.?card|api_?key|private_?key)/i.test(arg))
      add('APEX-DEBUG-SENSITIVE', 'Medium', ctx, ctx.lineOf(m.index), 'Debug statement may log secrets or PII.');
  }
  for (const m of code.matchAll(/\.\w*(?:Password|Passwd|Secret|Token|ApiKey|Api_Key|Private_Key|PrivateKey|Credential)\w*__c\b/gi))
    add('APEX-CREDENTIAL-FIELD-READ', 'High', ctx, ctx.lineOf(m.index), 'Reads a credential-like custom field (custom setting/metadata/object) — credentials must live in Named/External Credentials.');

  // Crypto
  for (const m of code.matchAll(/Crypto\.generate(?:Digest|Mac)\s*\(\s*'(MD5|SHA1|hmacMD5|hmacSHA1)'/gi))
    add('APEX-WEAK-CRYPTO', 'Medium', ctx, ctx.lineOf(m.index), `Weak algorithm ${m[1]} — use SHA-256/SHA-512 (hmacSHA256+).`);
  for (const m of code.matchAll(/Math\.random\s*\(/g))
    add('APEX-INSECURE-RANDOM', 'Low', ctx, ctx.lineOf(m.index), 'Math.random is not cryptographically secure — use Crypto.getRandomLong/getRandomInteger for tokens.');
  for (const m of code.matchAll(/Crypto\.(?:encrypt|decrypt)\s*\(/g))
    add('APEX-STATIC-IV', 'Low', ctx, ctx.lineOf(m.index), 'Explicit IV — ensure a random IV per message; prefer encryptWithManagedIV.');

  // Redirects, deserialization, callouts
  for (const m of code.matchAll(/new\s+PageReference\s*\(/g)) {
    const arg = firstArg(extractParens(code, m.index + m[0].length - 1));
    if (!isStringLiteral(arg) && !/^Page\./.test(arg))
      add('APEX-OPEN-REDIRECT', 'Medium', ctx, ctx.lineOf(m.index), 'PageReference built from a variable — validate the target (relative paths / allowlist) to prevent open redirect.');
  }
  for (const m of code.matchAll(/JSON\.deserialize(?:Strict)?\s*\([^;]*?,\s*(?:List<\s*)?(SObject|\w+__c|Account|Contact|Lead|Opportunity|Case|User)\b/gi))
    add('APEX-MASS-ASSIGNMENT', 'Medium', ctx, ctx.lineOf(m.index), `Client JSON deserialized straight into ${m[1]} — attacker can set any field (OwnerId, flags). Map allowed fields explicitly and enforce FLS.`);
  for (const m of code.matchAll(/'http:\/\/(?!localhost|127\.0\.0\.1)[^']+'/gi))
    add('APEX-INSECURE-HTTP', 'Medium', ctx, ctx.lineOf(m.index), 'Plain-HTTP URL — use HTTPS.');
  for (const m of code.matchAll(/\.setEndpoint\s*\(/g)) {
    const arg = extractParens(code, m.index + m[0].length - 1);
    if (/callout:/i.test(arg)) continue;
    add('APEX-ENDPOINT-NO-NC', /'https?:/i.test(arg) ? 'Medium' : 'Low', ctx, ctx.lineOf(m.index), 'Callout endpoint not using a Named Credential (callout:...) — credentials/endpoint handled in code.');
  }
  for (const m of code.matchAll(/\.setHeader\s*\(\s*'(Authorization|X-API-Key|Api-Key|x-api-key)'/gi)) {
    const arg = extractParens(code, m.index + m[0].length - 1);
    const merge = /\{!\$Credential/i.test(arg);
    add('APEX-AUTH-HEADER', merge ? 'Low' : 'High', ctx, ctx.lineOf(m.index), merge ? 'Auth header via $Credential merge field — confirm it cannot be influenced by user input.' : 'Auth header built in Apex — let the Named/External Credential generate it.');
  }
}

// ---------------------------------------------------------------- JS / LWC / Aura / VF
function scanJs(ctx) {
  if (/(__tests__|\.test\.js$|\.spec\.js$)/.test(ctx.file)) return;
  const code = stripComments(ctx.text);
  const sinks = /\.(innerHTML|outerHTML)\s*=(?!=)|\binsertAdjacentHTML\s*\(|\bdocument\.write(?:ln)?\s*\(|\beval\s*\(|\bnew\s+Function\s*\(|\bsetTimeout\s*\(\s*['"`]/g;
  for (const m of code.matchAll(sinks))
    add('JS-XSS-SINK', 'High', ctx, ctx.lineOf(m.index), `Dangerous DOM/code sink "${m[0].trim()}" — XSS if data is attacker-controlled. Validate with experience-lwc-security-validate.`);
  for (const m of code.matchAll(/\b(?:window\.)?location(?:\.href)?\s*=(?!=)\s*(?!['"`])/g))
    add('JS-OPEN-REDIRECT', 'Medium', ctx, ctx.lineOf(m.index), 'Navigation to a computed URL — validate scheme/host (javascript: URLs, open redirect).');
  for (const m of code.matchAll(/sessionStorage|localStorage/g)) {
    const line = ctx.lineText(ctx.lineOf(m.index));
    if (/(token|session|password|secret)/i.test(line))
      add('JS-STORAGE-SECRET', 'Medium', ctx, ctx.lineOf(m.index), 'Secret/token stored in browser storage.');
  }
}

function scanLwcHtml(ctx) {
  for (const m of ctx.text.matchAll(/lwc:dom\s*=\s*"manual"/g))
    add('LWC-DOM-MANUAL', 'Medium', ctx, ctx.lineOf(m.index), 'lwc:dom="manual" — check how the JS populates this node (innerHTML = XSS).');
  for (const m of ctx.text.matchAll(/lwc:inner-html/g))
    add('LWC-INNER-HTML', 'High', ctx, ctx.lineOf(m.index), 'lwc:inner-html renders raw HTML — only with trusted/sanitized content.');
}

function scanAura(ctx) {
  for (const m of ctx.text.matchAll(/<aura:unescapedHtml/g))
    add('AURA-UNESCAPED-HTML', 'High', ctx, ctx.lineOf(m.index), 'aura:unescapedHtml renders raw HTML — XSS if value is user-controlled.');
  for (const m of ctx.text.matchAll(/ltng:allowGuestAccess/g))
    add('AURA-GUEST-ACCESS', 'Medium', ctx, ctx.lineOf(m.index), 'App/component allows guest (unauthenticated) access — every server action it calls must be safe for anonymous users.');
  for (const m of ctx.text.matchAll(/<aura:(?:component|application|event)[^>]*\baccess\s*=\s*"global"/g))
    add('AURA-GLOBAL-ACCESS', 'Low', ctx, ctx.lineOf(m.index), 'access="global" widens who can use this bundle.');
}

function scanVf(ctx) {
  for (const m of ctx.text.matchAll(/escape\s*=\s*"false"/gi))
    add('VF-ESCAPE-FALSE', 'High', ctx, ctx.lineOf(m.index), 'escape="false" disables output encoding — XSS if value is user-controlled.');
  for (const m of ctx.text.matchAll(/\{!\s*\$CurrentPage\.parameters\.[^}]*\}/gi))
    add('VF-UNENCODED-PARAM', 'High', ctx, ctx.lineOf(m.index), 'URL parameter rendered without JSENCODE/HTMLENCODE/URLENCODE — reflected XSS.');
  for (const m of ctx.text.matchAll(/<apex:page\b[^>]*\baction\s*=\s*"\{!/gi))
    add('VF-CSRF-ACTION', 'Medium', ctx, ctx.lineOf(m.index), 'apex:page action runs on GET before CSRF protection — must not perform DML/state changes.');
  for (const m of ctx.text.matchAll(/<(?:script|apex:includeScript)\b[^>]*(?:src|value)\s*=\s*"http:\/\//gi))
    add('VF-INSECURE-SCRIPT', 'Medium', ctx, ctx.lineOf(m.index), 'Script loaded over HTTP.');
}

function scanLwcMeta(ctx) {
  if (!isTrue(tagVal(ctx.text, 'isExposed'))) return;
  const m = ctx.text.match(/<target>\s*(lightningCommunity__\w+)\s*<\/target>/);
  if (m)
    add('LWC-COMMUNITY-TARGET', 'Info', ctx, ctx.lineOf(m.index), `Component exposed to Experience Cloud (${m[1]}) — reachable by guest users on public pages; review the Apex it calls.`);
}

// ---------------------------------------------------------------- permissions
const MAD_VAD = new Set(['ModifyAllData', 'ViewAllData']);
const HIGH_RISK_PERMS = {
  ModifyMetadata: 'High', CustomizeApplication: 'High', AuthorApex: 'High', ManageUsers: 'High', ManageInternalUsers: 'High',
  AssignPermissionSets: 'High', ManageProfilesPermissionsets: 'High', ManageSharing: 'High', ManageRoles: 'High',
  ResetPasswords: 'High', ManageCustomPermissions: 'High', ManageAuthProviders: 'High', ManageEncryptionKeys: 'High',
  ViewEncryptedData: 'High', ManageIpAddresses: 'High', ManageRemoteAccess: 'High', BypassMFAForUiLogins: 'High',
  ManageLoginAccessPolicies: 'High', QueryAllFiles: 'High', ModifyAllPolicyCenterPolicies: 'High', ViewAllUsers: 'Medium',
  PasswordNeverExpires: 'Medium', ViewSetup: 'Medium', ExportReport: 'Medium', DataExport: 'Medium',
  ManageDataIntegrations: 'Medium', EditReadonlyFields: 'Medium', TransferAnyEntity: 'Medium', BulkApiHardDelete: 'Medium',
  InstallPackaging: 'Medium', ManageNamedCredentials: 'High', ViewAllProfiles: 'Low', ApiEnabled: 'Low'
};
const SENSITIVE_FIELD_RE = /(ssn|social_?security|tax_?id|national_?id|passport|salary|compensation|birth|dob|credit|card_?number|iban|bank|account_?number|routing|medical|health|diagnosis|password|secret|token)/i;

function scanPermissions(ctx, isProfile) {
  const base = decodeURIComponent(path.basename(ctx.file).replace(/\.(profile|permissionset)-meta\.xml$/, ''));
  const label = tagVal(ctx.text, 'label') || base;
  const kind = isProfile ? 'Profile' : 'Permission set';
  const who = `${kind} "${label}"`;
  const isAdmin = isProfile && /\badmin|system administrator/i.test(base);
  const isGuest = /Guest User License/.test(ctx.text) || (isProfile && /guest/i.test(base));

  for (const b of blocks(ctx.text, 'userPermissions')) {
    if (!isTrue(tagVal(b.body, 'enabled'))) continue;
    const name = tagVal(b.body, 'name');
    const line = ctx.lineOf(b.index);
    if (isGuest) {
      const sev = MAD_VAD.has(name) ? 'Critical' : ['ApiEnabled', 'ViewAllUsers'].includes(name) ? 'High' : 'Medium';
      add('GUEST-USER-PERMISSION', sev, ctx, line, `Guest ${who} has ${name} — unauthenticated users inherit it.`);
    } else if (MAD_VAD.has(name)) {
      if (isAdmin) add('PERM-MAD-VAD', 'Info', ctx, line, `${who} grants ${name} (expected for admin) — keep active assignees to a minimum.`);
      else add('PERM-MAD-VAD', 'Critical', ctx, line, `${who} grants ${name} — bypasses all sharing/CRUD/FLS. Only System Administrators may hold it.`);
    } else if (HIGH_RISK_PERMS[name] && !isAdmin) {
      add('PERM-HIGH-RISK', HIGH_RISK_PERMS[name], ctx, line, `${who} grants high-risk system permission ${name} — confirm least privilege.`);
    }
  }

  for (const b of blocks(ctx.text, 'objectPermissions')) {
    const obj = tagVal(b.body, 'object');
    const p = {
      read: isTrue(tagVal(b.body, 'allowRead')),
      create: isTrue(tagVal(b.body, 'allowCreate')),
      edit: isTrue(tagVal(b.body, 'allowEdit')),
      del: isTrue(tagVal(b.body, 'allowDelete')),
      va: isTrue(tagVal(b.body, 'viewAllRecords')),
      ma: isTrue(tagVal(b.body, 'modifyAllRecords')),
      vaf: isTrue(tagVal(b.body, 'viewAllFields'))
    };
    const line = ctx.lineOf(b.index);
    const granted = Object.entries(p).filter(([, v]) => v).map(([k]) => k).join(', ');
    if (isGuest) {
      if (p.va || p.ma) add('GUEST-OBJECT-ACCESS', 'Critical', ctx, line, `Guest ${who} has View/Modify All on ${obj}.`);
      else if (p.edit || p.del) add('GUEST-OBJECT-ACCESS', 'High', ctx, line, `Guest ${who} can edit/delete ${obj} (${granted}).`);
      else if (p.read || p.create) add('GUEST-OBJECT-ACCESS', 'Medium', ctx, line, `Guest ${who} has ${granted} on ${obj} — readable via /s/sfsites/aura without login; confirm required and no private data.`);
    } else if (!isAdmin) {
      if (p.va || p.ma)
        add('PERM-VIEW-MODIFY-ALL', 'High', ctx, line, `${who} has ${[p.va && 'View All', p.ma && 'Modify All'].filter(Boolean).join(' + ')} on ${obj} — bypasses sharing. Use sharing rules/teams instead.`);
      if (p.vaf) add('PERM-VIEW-ALL-FIELDS', 'Medium', ctx, line, `${who} has View All Fields on ${obj} — bypasses FLS for reads.`);
    }
  }

  const profileFls = [];
  for (const b of blocks(ctx.text, 'fieldPermissions')) {
    const field = tagVal(b.body, 'field');
    const r = isTrue(tagVal(b.body, 'readable'));
    const e = isTrue(tagVal(b.body, 'editable'));
    if (!r && !e) continue;
    const line = ctx.lineOf(b.index);
    if (isGuest) {
      add('GUEST-FIELD-ACCESS', e ? 'High' : 'Medium', ctx, line, `Guest ${who} can ${e ? 'edit' : 'read'} ${field}.`);
      continue;
    }
    if (isAdmin) continue;
    if (SENSITIVE_FIELD_RE.test(field || '')) add('PERM-SENSITIVE-FLS', 'Low', ctx, line, `${who} grants ${e ? 'edit' : 'read'} on sensitive-looking field ${field} — confirm only required users get it.`);
    if (isProfile) profileFls.push(line);
  }
  if (profileFls.length)
    add('PERM-PROFILE-FLS', 'Low', ctx, profileFls[0], `${who} grants FLS on ${profileFls.length} field(s) — manage FLS in permission sets (least privilege, auditable).`);

  if (isGuest) {
    for (const [tag, nameTag, rule, sev, what] of [
      ['classAccesses', 'apexClass', 'GUEST-APEX-CLASS', 'High', 'Apex class'],
      ['pageAccesses', 'apexPage', 'GUEST-VF-PAGE', 'Medium', 'Visualforce page'],
      ['flowAccesses', 'flow', 'GUEST-FLOW', 'Medium', 'Flow']
    ]) {
      for (const b of blocks(ctx.text, tag)) {
        if (!isTrue(tagVal(b.body, 'enabled'))) continue;
        add(rule, sev, ctx, ctx.lineOf(b.index), `${what} ${tagVal(b.body, nameTag)} is accessible to guest ${who} — every @AuraEnabled/@RemoteAction method or flow element is invocable unauthenticated.`);
      }
    }
  }
}

// ---------------------------------------------------------------- objects, fields, records
const PUBLIC_MODELS = new Set(['Read', 'ReadWrite', 'ReadWriteTransfer', 'FullAccess', 'ReadSelect']);

function scanObject(ctx) {
  const name = path.basename(ctx.file).replace(/\.object-meta\.xml$/, '');
  if (/__(mdt|e|b|x)$/.test(name) || /<customSettingsType>/.test(ctx.text)) return;
  const internal = tagVal(ctx.text, 'sharingModel');
  const external = tagVal(ctx.text, 'externalSharingModel');
  if (internal && PUBLIC_MODELS.has(internal)) {
    const m = ctx.text.match(/<sharingModel>/);
    add('OWD-INTERNAL-PUBLIC', 'Medium', ctx, ctx.lineOf(m.index), `${name} internal OWD is ${internal} — must be Private unless every internal user needs it and it holds no private data.`);
  }
  if (external && PUBLIC_MODELS.has(external)) {
    const m = ctx.text.match(/<externalSharingModel>/);
    add('OWD-EXTERNAL-PUBLIC', 'High', ctx, ctx.lineOf(m.index), `${name} external OWD is ${external} — exposed to all portal/community users. Salesforce guidance: Private.`);
  }
}

function scanField(ctx) {
  const parts = ctx.file.split(path.sep);
  const fi = parts.lastIndexOf('fields');
  if (fi < 1) return;
  const obj = parts[fi - 1];
  const field = path.basename(ctx.file).replace(/\.field-meta\.xml$/, '');
  if (!SECRET_NAME_RE.test(field.replace(/__c$/, ''))) return;
  if (/^(Last|Created)/.test(field)) return;
  let container = 'object';
  if (obj.endsWith('__mdt')) container = 'custom metadata type';
  else {
    try {
      const objXml = fs.readFileSync(path.join(parts.slice(0, fi).join(path.sep), `${obj}.object-meta.xml`), 'utf8');
      if (/<customSettingsType>/.test(objXml)) container = 'custom setting';
    } catch {
      /* object file not in source */
    }
  }
  const encrypted = tagVal(ctx.text, 'type') === 'EncryptedText' ? ' (EncryptedText does not make this acceptable)' : '';
  add('CRED-STORAGE-FIELD', 'High', ctx, 1, `${obj}.${field} looks like a credential stored in a ${container}${encrypted} — use Named Credentials / External Credentials / External Client Apps.`);
}

function scanCmdtRecord(ctx) {
  for (const b of blocks(ctx.text, 'values')) {
    const field = tagVal(b.body, 'field') || '';
    const value = tagVal(b.body, 'value');
    if (!SECRET_NAME_RE.test(field) || !value || /xsi:nil/.test(b.body) || PLACEHOLDER_RE.test(value)) continue;
    add('CRED-CMDT-VALUE', 'Critical', ctx, ctx.lineOf(b.index), `Custom metadata record stores a value in credential-like field ${field} — secret committed to source and readable by Apex.`);
  }
}

function scanSharingRules(ctx) {
  for (const b of blocks(ctx.text, 'sharingGuestRules'))
    add('SHR-GUEST-RULE', 'High', ctx, ctx.lineOf(b.index), `Guest sharing rule "${tagVal(b.body, 'fullName')}" (${tagVal(b.body, 'accessLevel')}) exposes records to unauthenticated users.`);
  for (const tag of ['sharingCriteriaRules', 'sharingOwnerRules']) {
    for (const b of blocks(ctx.text, tag)) {
      const access = tagVal(b.body, 'accessLevel');
      let sev = null;
      let target = '';
      if (/<allPartnerUsers|<allCustomerPortalUsers/.test(b.body)) {
        sev = 'Medium';
        target = 'all external users';
      } else if (/<allInternalUsers/.test(b.body)) {
        sev = 'Low';
        target = 'all internal users';
      }
      if (!sev) continue;
      if (access === 'Edit') sev = raise(sev);
      add('SHR-BROAD-RULE', sev, ctx, ctx.lineOf(b.index), `Sharing rule "${tagVal(b.body, 'fullName')}" grants ${access} to ${target} — effectively makes the OWD public.`);
    }
  }
}

// ---------------------------------------------------------------- integrations
function httpUrls(text) {
  return [...text.matchAll(/http:\/\/(?!localhost|127\.0\.0\.1|soap\.sforce\.com|www\.w3\.org)[^\s<"']+/g)];
}

function scanNamedCredential(ctx) {
  const pw = tagVal(ctx.text, 'password');
  if (pw) add('NC-PASSWORD', 'Critical', ctx, ctx.lineOf(ctx.text.indexOf('<password>')), 'Password committed in Named Credential metadata.');
  for (const tag of ['allowMergeFieldsInBody', 'allowMergeFieldsInHeader']) {
    if (isTrue(tagVal(ctx.text, tag)))
      add('NC-MERGE-FIELDS', 'Medium', ctx, ctx.lineOf(ctx.text.indexOf(`<${tag}>`)), `${tag}=true — ensure merge fields cannot be combined with user input to exfiltrate credentials.`);
  }
  for (const m of httpUrls(ctx.text)) add('NC-HTTP', 'High', ctx, ctx.lineOf(m.index), 'Named Credential endpoint uses plain HTTP.');
  if (/<principalType>/.test(ctx.text) && !/<namedCredentialType>/.test(ctx.text))
    add('NC-LEGACY', 'Low', ctx, 1, 'Legacy Named Credential — migrate to the External Credential model.');
}

function scanRemoteSite(ctx) {
  if (isTrue(tagVal(ctx.text, 'disableProtocolSecurity')))
    add('RSS-NO-TLS', 'High', ctx, ctx.lineOf(ctx.text.indexOf('<disableProtocolSecurity>')), 'Remote Site Setting disables protocol security (allows HTTP).');
  for (const m of httpUrls(ctx.text)) add('RSS-HTTP', 'Medium', ctx, ctx.lineOf(m.index), 'Remote Site uses plain HTTP.');
  add('RSS-PRESENT', 'Info', ctx, 1, 'Remote Site Setting implies callouts outside Named Credentials — confirm credentials are not handled in code.');
}

function scanCspCors(ctx, isCors) {
  const val = tagVal(ctx.text, isCors ? 'urlPattern' : 'endpointUrl') || '';
  const rule = isCors ? 'CORS-ALLOWLIST' : 'CSP-TRUSTED-SITE';
  if (val.includes('*')) add(rule, isCors ? 'High' : 'Medium', ctx, 1, `Wildcard origin "${val}".`);
  if (/^http:\/\//.test(val)) add(rule, 'Medium', ctx, 1, `Plain-HTTP origin "${val}".`);
}

function scanOAuthApp(ctx, isConnectedApp) {
  if (isConnectedApp)
    add('APP-CONNECTED-APP', 'Info', ctx, 1, 'Connected App — new integrations should use External Client Apps (ECA).');
  const secret = tagVal(ctx.text, 'consumerSecret');
  if (secret) add('APP-CONSUMER-SECRET', 'Critical', ctx, ctx.lineOf(ctx.text.indexOf('<consumerSecret>')), 'Consumer secret committed in source.');
  for (const b of blocks(ctx.text, 'callbackUrl')) {
    if (/http:\/\/(?!localhost|127\.0\.0\.1)/.test(b.body)) add('APP-CALLBACK', 'High', ctx, ctx.lineOf(b.index), 'OAuth callback URL uses plain HTTP.');
    if (b.body.includes('*')) add('APP-CALLBACK', 'High', ctx, ctx.lineOf(b.index), 'Wildcard OAuth callback URL — token hijacking risk.');
  }
  for (const tag of ['scopes', 'commaSeparatedOauthScopes']) {
    for (const b of blocks(ctx.text, tag))
      if (/\bFull\b/.test(b.body)) add('APP-FULL-SCOPE', 'High', ctx, ctx.lineOf(b.index), 'OAuth "Full" scope — request minimal scopes.');
  }
  const refresh = ctx.text.match(/<refreshTokenPolicy>\s*infinite\s*<\/refreshTokenPolicy>/i);
  if (refresh) add('APP-REFRESH-INFINITE', 'Medium', ctx, ctx.lineOf(refresh.index), 'Refresh tokens valid until revoked — set an expiry unless this is a vetted server integration.');
  const ip = ctx.text.match(/<ipRelaxation>\s*BYPASS\s*<\/ipRelaxation>/i);
  if (ip) add('APP-IP-BYPASS', 'Medium', ctx, ctx.lineOf(ip.index), 'IP restrictions relaxed (BYPASS).');
  const self = ctx.text.match(/AllSelfAuthorized|<isAdminApproved>\s*false/i);
  if (self) add('APP-SELF-AUTHORIZE', 'Medium', ctx, ctx.lineOf(self.index), 'Any user may self-authorize — require admin pre-approval via permission set.');
}

function scanFlow(ctx) {
  const m = ctx.text.match(/<runInMode>\s*(SystemModeWithoutSharing|SystemModeWithSharing)\s*<\/runInMode>/);
  if (!m) return;
  const noSharing = m[1] === 'SystemModeWithoutSharing';
  add(
    noSharing ? 'FLOW-SYSTEM-NO-SHARING' : 'FLOW-SYSTEM-MODE',
    noSharing ? 'High' : 'Medium',
    ctx,
    ctx.lineOf(m.index),
    `Flow runs in ${m[1]} — bypasses ${noSharing ? 'sharing, CRUD and FLS' : 'CRUD/FLS'}. Critical if launched from a guest-accessible site.`
  );
}

function scanSiteNetwork(ctx) {
  for (const m of ctx.text.matchAll(/<(\w*[Gg]uest\w*)>\s*true\s*<\/\1>/g))
    add('SITE-GUEST-SETTING', 'Medium', ctx, ctx.lineOf(m.index), `Guest-related site setting enabled: ${m[1]}.`);
  const reg = ctx.text.match(/<selfRegistration>\s*true/);
  if (reg) add('SITE-SELF-REGISTRATION', 'Low', ctx, ctx.lineOf(reg.index), 'Self-registration enabled — review the default profile/permission sets new users receive.');
  const gp = ctx.text.match(/<guestProfile>\s*([^<]+)</);
  if (gp) add('SITE-GUEST-PROFILE', 'Info', ctx, ctx.lineOf(gp.index), `Site guest profile: ${gp[1].trim()} — audit it with the guest rules.`);
}

// ---------------------------------------------------------------- dispatch
function scanFile(file) {
  const base = path.basename(file);
  if (KEY_FILE_RE.test(base) || /^\.env(\.|$)/.test(base)) {
    if (!/\.(example|sample|template)$/.test(base)) {
      const ctx = makeCtx(file, '');
      add('SEC-KEY-FILE', 'High', ctx, 0, `Key/credential file "${base}" in workspace — ensure it is not committed (git ls-files) and is ignored.`);
    }
  }
  const ext = path.extname(base).toLowerCase();
  if (!TEXT_EXT.has(ext) && !/^\.env/.test(base)) return;
  if (SKIP_FILES.has(base)) return;
  let stat;
  try {
    stat = fs.statSync(file);
  } catch {
    return;
  }
  if (stat.size > MAX_BYTES) return;
  const text = fs.readFileSync(file, 'utf8');
  const ctx = makeCtx(file, text);
  filesScanned++;
  scanSecrets(ctx);

  const parts = file.split(path.sep);
  if (base.endsWith('.cls')) return scanApex(ctx, false);
  if (base.endsWith('.trigger')) return scanApex(ctx, true);
  if (base.endsWith('.page') || base.endsWith('.component')) return scanVf(ctx);
  if (/\.(cmp|app)$/.test(base)) return scanAura(ctx);
  if (parts.includes('lwc') && base.endsWith('.html')) return scanLwcHtml(ctx);
  if ((parts.includes('lwc') || parts.includes('aura')) && /\.(js|ts)$/.test(base)) return scanJs(ctx);
  if (parts.includes('lwc') && base.endsWith('.js-meta.xml')) return scanLwcMeta(ctx);
  if (base.endsWith('.profile-meta.xml')) return scanPermissions(ctx, true);
  if (base.endsWith('.permissionset-meta.xml')) return scanPermissions(ctx, false);
  if (base.endsWith('.object-meta.xml')) return scanObject(ctx);
  if (base.endsWith('.field-meta.xml')) return scanField(ctx);
  if (base.endsWith('.md-meta.xml')) return scanCmdtRecord(ctx);
  if (base.endsWith('.sharingRules-meta.xml')) return scanSharingRules(ctx);
  if (base.endsWith('.namedCredential-meta.xml')) return scanNamedCredential(ctx);
  if (base.endsWith('.remoteSite-meta.xml')) return scanRemoteSite(ctx);
  if (base.endsWith('.cspTrustedSite-meta.xml')) return scanCspCors(ctx, false);
  if (base.endsWith('.corsWhitelistOrigin-meta.xml')) return scanCspCors(ctx, true);
  if (base.endsWith('.connectedApp-meta.xml')) return scanOAuthApp(ctx, true);
  if (/\.eca\w*-meta\.xml$/.test(base)) return scanOAuthApp(ctx, false);
  if (base.endsWith('.flow-meta.xml')) return scanFlow(ctx);
  if (/\.(site|network)-meta\.xml$/.test(base)) return scanSiteNetwork(ctx);
}

function walk(p) {
  let st;
  try {
    st = fs.lstatSync(p);
  } catch {
    process.stderr.write(`Skipping missing path ${p}\n`);
    return;
  }
  if (st.isSymbolicLink()) return;
  if (st.isDirectory()) {
    for (const entry of fs.readdirSync(p)) {
      if (SKIP_DIRS.has(entry)) continue;
      walk(path.join(p, entry));
    }
  } else if (st.isFile()) {
    scanFile(p);
  }
}

for (const t of targets) walk(path.resolve(t));

// ---------------------------------------------------------------- output
findings.sort(
  (a, b) =>
    SEVERITIES.indexOf(a.severity) - SEVERITIES.indexOf(b.severity) ||
    a.file.localeCompare(b.file) ||
    a.line - b.line
);
const summary = Object.fromEntries(SEVERITIES.map((s) => [s, findings.filter((f) => f.severity === s).length]));

let output;
if (format === 'json') {
  output = JSON.stringify({ targets, filesScanned, summary, findings }, null, 2);
} else {
  const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
  const lines = [
    '# Salesforce security scan (heuristic candidates — triage required)',
    '',
    `Scanned ${filesScanned} files under: ${targets.join(', ')}`,
    '',
    '| Severity | Count |',
    '|---|---|',
    ...SEVERITIES.map((s) => `| ${s} | ${summary[s]} |`)
  ];
  for (const s of SEVERITIES) {
    const group = findings.filter((f) => f.severity === s);
    if (!group.length) continue;
    lines.push('', `## ${s}`, '', '| Rule | Location | Finding |', '|---|---|---|');
    for (const f of group) lines.push(`| ${f.rule} | ${esc(f.file)}${f.line ? `:${f.line}` : ''} | ${esc(f.message)} |`);
  }
  output = lines.join('\n') + '\n';
}

if (outFile) {
  fs.mkdirSync(path.dirname(path.resolve(outFile)), { recursive: true });
  fs.writeFileSync(outFile, output);
  process.stdout.write(`Wrote ${findings.length} findings to ${outFile} (${SEVERITIES.map((s) => `${s}: ${summary[s]}`).join(', ')})\n`);
} else {
  process.stdout.write(output);
}

if (failOn) {
  const threshold = SEVERITIES.indexOf(failOn);
  if (findings.some((f) => SEVERITIES.indexOf(f.severity) <= threshold)) process.exit(1);
}
