// The private case record (Decision 175), run against real SQLite and the real
// schema. What matters most: the form works with no credential, and nothing
// personal leaves without one, or in the list the public workflow reads.
// Run: node tools/test_takedown_worker.mjs
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { handleTakedown, missing, sweepTakedowns } from "../worker/src/takedown.js";

let failures = 0;
function check(label, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures++;
}

const sql = new DatabaseSync(":memory:");
sql.exec(readFileSync(new URL("../worker/schema-takedowns.sql", import.meta.url), "utf8"));
const DB = {
  prepare(q) {
    const stmt = sql.prepare(q);
    let args = [];
    const self = {
      bind(...a) { args = a; return self; },
      async run() {
        if (/^\s*SELECT/i.test(q)) return { results: stmt.all(...args), meta: {} };
        const r = stmt.run(...args);
        return { meta: { changes: Number(r.changes) } };
      },
      async first() { return stmt.get(...args) ?? null; },
    };
    return self;
  },
};
const { publicKey, privateKey } = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const jwk = { ...(await crypto.subtle.exportKey("jwk", publicKey)), kid: "test" };
const env = { DB, LOCAL_TEST_JWKS: JSON.stringify({ keys: [jwk] }) };
const b64u = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
const GOOD = { iss: "https://token.actions.githubusercontent.com", aud: "http://localhost:8787", sub: "repo:bhwilkoff/Archive-Watch:ref:refs/heads/main",
  repository: "bhwilkoff/Archive-Watch", repository_id: "1213936872", ref: "refs/heads/main", event_name: "schedule",
  job_workflow_ref: "bhwilkoff/Archive-Watch/.github/workflows/takedown-check.yml@refs/heads/main" };
async function mint(over = {}, alg = "RS256", key = privateKey) {
  const now = Math.floor(Date.now() / 1000);
  const body = { ...GOOD, iat: now, exp: now + 300, ...over };
  const signed = `${b64u({ alg, kid: "test" })}.${b64u(body)}`;
  const sig = Buffer.from(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signed))).toString("base64url");
  return `${signed}.${sig}`;
}
const goodToken = await mint();
const cors = {};
async function hit(path, { method = "GET", body, token } = {}) {
  const url = new URL("http://localhost:8787" + path);
  const headers = {};
  if (token) headers.Authorization = "Bearer " + token;
  const req = new Request(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const res = await handleTakedown(url, req, env, cors);
  return { status: res.status, json: await res.json() };
}

const notice = {
  kind: "copyright", links: "https://archivewatch.org/item/X/", work: "My Film",
  name: "Jane Requester", email: "jane@example.com", phone: "555-0100",
  address: "12 Private Lane", goodFaith: true, accurate: true, signature: "Jane Requester",
};

let r = await hit("/takedown", { method: "POST", body: notice });
check("the form needs no credential", r.status === 200 && /^TD-[0-9A-Z]{8}$/.test(r.json.ref), JSON.stringify(r.json));
const ref = r.json.ref;

for (const k of ["links", "name", "email", "work", "address", "phone", "goodFaith", "accurate", "signature"]) {
  const short = { ...notice };
  delete short[k];
  r = await hit("/takedown", { method: "POST", body: short });
  check(`a notice without ${k} is refused and says so`, r.status === 400 && r.json.field === k);
}
r = await hit("/takedown", { method: "POST", body: { kind: "other", links: "x", name: "A", email: "a@b.co" } });
check("a privacy request needs its reason", r.json.field === "reason");
r = await hit("/takedown", { method: "POST", body: { kind: "other", links: "x", name: "A", email: "a@b.co", reason: "That is me" } });
check("and needs no sworn statement", r.status === 200);
const before = sql.prepare("SELECT COUNT(*) n FROM takedown_cases").get().n;
r = await hit("/takedown", { method: "POST", body: { ...notice, website: "http://spam" } });
const after = sql.prepare("SELECT COUNT(*) n FROM takedown_cases").get().n;
check("a filled trap field looks accepted and stores nothing", r.status === 200 && before === after);

check("a form copyright notice is complete", sql.prepare("SELECT complete c FROM takedown_cases WHERE ref = ?").get(ref).c === 1);
const other = sql.prepare("SELECT complete c FROM takedown_cases WHERE kind = 'other'").get();
check("a privacy request is not a notice", other.c === 0);

for (const [path, opts] of [["/takedown/cases", {}], [`/takedown/cases/${ref}`, {}],
                            [`/takedown/cases/${ref}`, { method: "POST", body: { status: "closed" } }],
                            ["/takedown/cases", { token: "not-a-jwt" }]]) {
  r = await hit(path, opts);
  check(`no valid token, no answer: ${opts.method || "GET"} ${path.slice(0, 18)}`, r.status === 403);
}

// Every claim the Worker pins, each broken on its own (a check is not a check until seen to fail).
const stranger = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
const now0 = Math.floor(Date.now() / 1000);
for (const [name, tok] of [
  ["another repository", await mint({ repository: "someone/else" })],
  ["another repository id", await mint({ repository_id: "1" })],
  ["a branch", await mint({ ref: "refs/heads/branch" })],
  ["another workflow", await mint({ job_workflow_ref: "bhwilkoff/Archive-Watch/.github/workflows/other.yml@refs/heads/main" })],
  ["a pull request event", await mint({ event_name: "pull_request" })],
  ["another audience", await mint({ aud: "https://evil.example" })],
  ["another issuer", await mint({ iss: "https://evil.example" })],
  ["an expired token", await mint({ iat: now0 - 900, exp: now0 - 600 })],
  ["a stranger's signature", await mint({}, "RS256", stranger.privateKey)],
  ["alg none", `${b64u({ alg: "none", kid: "test" })}.${b64u({ ...GOOD, exp: now0 + 300 })}.`],
]) {
  r = await hit("/takedown/cases", { token: tok });
  check(`CONTROL: ${name} is refused`, r.status === 403);
}
{
  const url = new URL("https://archivewatch-pulse.benwilkoff.workers.dev/takedown/cases");
  const req = new Request(url, { headers: { Authorization: "Bearer " + goodToken } });
  const res = await handleTakedown(url, req, env, cors);
  check("CONTROL: the test keys are refused on a public host", res.status === 403);
}
r = await hit("/takedown/cases", { token: goodToken });
const listed = JSON.stringify(r.json);
check("the check sees the case", r.json.cases.some((c) => c.ref === ref));
check("the list carries nobody's details",
  !/Jane|jane@|555-0100|Private Lane/.test(listed));
r = await hit(`/takedown/cases/${ref}`, { token: goodToken });
check("the owner's read has the whole record", r.json.email === "jane@example.com");

r = await hit("/takedown/cases", { method: "POST", token: goodToken, body: {
  links: "https://archivewatch.org/item/Y/", work: "W", source: "google", complete: true, external_ref: "9-09" } });
const g = await hit(`/takedown/cases/${r.json.ref}`, { token: goodToken });
check("a notice from Google is opened with no person", g.json.source === "google" && g.json.complete === 1 && !g.json.email);

r = await hit(`/takedown/cases/${ref}`, { method: "POST", token: goodToken, body: { status: "removed", verdict: [{ id: "X" }] } });
const closed = sql.prepare("SELECT status, closed_ms, verdict FROM takedown_cases WHERE ref = ?").get(ref);
check("an outcome is recorded", closed.status === "removed" && closed.closed_ms > 0 && closed.verdict.includes("X"));
r = await hit(`/takedown/cases/${ref}`, { method: "POST", token: goodToken, body: { status: "nonsense" } });
check("an unknown status is refused", r.status === 400);

const YEAR = 365 * 24 * 3600 * 1000;
await sweepTakedowns(env, closed.closed_ms + 2 * YEAR);
check("details are kept for three years", sql.prepare("SELECT email e FROM takedown_cases WHERE ref = ?").get(ref).e === notice.email);
await sweepTakedowns(env, closed.closed_ms + 3 * YEAR + 1000);
const swept = sql.prepare("SELECT * FROM takedown_cases WHERE ref = ?").get(ref);
check("then erased", !swept.email && !swept.name && !swept.phone && !swept.address && !swept.signature && !swept.work);
check("and the outcome stays", swept.status === "removed" && swept.links);
const open = sql.prepare("SELECT email e FROM takedown_cases WHERE kind = 'other'").get();
check("CONTROL: an open case is never swept", open.e === "a@b.co");
check("missing() is exported for the form's copy", typeof missing === "function");

console.log(failures ? `${failures} FAILED` : "all passed");
process.exit(failures ? 1 : 0);
