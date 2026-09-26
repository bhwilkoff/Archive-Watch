// The /mcp endpoint (worker/src/mcp.js, ORPHANED-FILMS #4) against shards
// built by tools/build_mcp_data.py. fetch is served from a local site root
// (MCP_SITE, default a fresh build) and, for details/, from archivewatch.org.
//   node tools/test_mcp_endpoint.mjs [siteRoot]
import { execFileSync } from "node:child_process";
import { readFileSync, existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repo = new URL("..", import.meta.url).pathname;
let root = process.argv[2];
if (!root) {
  root = mkdtempSync(join(tmpdir(), "aw-mcp-"));
  execFileSync("python3", [join(repo, "tools/build_mcp_data.py"), "--out", root, "--details", join(repo, "details")], { stdio: "inherit" });
}
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, opts) => {
  const path = String(url).replace("https://archivewatch.org/", "");
  if (path.startsWith("mcp/")) {
    const f = join(root, path);
    return existsSync(f) ? new Response(readFileSync(f)) : new Response("{}", { status: 404 });
  }
  return realFetch(url, opts);
};
const { handleMCP, words, fnvShard } = await import(join(repo, "worker/src/mcp.js"));

let failures = 0;
const check = (label, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${ok ? "" : ` — ${detail}`}`);
  if (!ok) failures++;
};
const call = async (body) => {
  const r = await handleMCP(new Request("https://x/mcp", { method: "POST", body: JSON.stringify(body) }));
  return { status: r.status, json: r.status === 202 ? null : await r.json() };
};
const tool = async (name, args) =>
  (await call({ jsonrpc: "2.0", id: 9, method: "tools/call", params: { name, arguments: args } })).json.result;

// The Python builder and this file must hash and split identically.
const py = JSON.parse(execFileSync("python3", ["-c",
  "import sys,json;sys.path.insert(0,'tools');import build_mcp_data as M;" +
  "print(json.dumps([M.fnv_shard('TheScarecrow1920'),M.fnv_shard('Café_1922'),M.words('Le Voyage dans la Lune — Méliès')]))"],
  { cwd: repo }).toString());
check("FNV shard agrees with Python", py[0] === fnvShard("TheScarecrow1920") && py[1] === fnvShard("Café_1922"));
check("word split agrees with Python", JSON.stringify(py[2]) === JSON.stringify(words("Le Voyage dans la Lune — Méliès")),
  JSON.stringify([py[2], words("Le Voyage dans la Lune — Méliès")]));

let r = await call({ jsonrpc: "2.0", id: 1, method: "initialize", params: {} });
check("initialize names the server", r.json.result?.serverInfo?.name === "archive-watch");
r = await call({ jsonrpc: "2.0", method: "notifications/initialized" });
check("a notification gets 202 and no body", r.status === 202);
r = await call({ jsonrpc: "2.0", id: 2, method: "tools/list" });
check("three tools", r.json.result?.tools?.length === 3);

let s = await tool("search_films", { query: "nosferatu" });
check("search finds Nosferatu", s.structuredContent.films.some((f) => /nosferatu/i.test(f.title)), JSON.stringify(s.structuredContent).slice(0, 300));
check("results link to archivewatch.org", s.structuredContent.films.every((f) => f.link.startsWith("https://archivewatch.org/item/")));
s = await tool("search_films", { query: "keaton gene" });
check("two words, last as a prefix: Keaton's The General", s.structuredContent.films.some((f) => /general/i.test(f.title)), JSON.stringify(s.structuredContent).slice(0, 300));
s = await tool("search_films", { query: "metropolis", max_minutes: 60 });
check("max_minutes filters", s.structuredContent.films.every((f) => f.minutes && f.minutes <= 60));
s = await tool("search_films", { query: "zzqxv" });
check("control: nonsense finds nothing", s.structuredContent.films.length === 0);

const g = await tool("get_film", { id: "TheScarecrow1920" });
check("get_film returns the film with its link", g.structuredContent.title && g.structuredContent.link.endsWith("/item/TheScarecrow1920/"), JSON.stringify(g.structuredContent).slice(0, 300));
check("a synopsis always names its source", !g.structuredContent.synopsis || Boolean(g.structuredContent.synopsis_source));
const miss = await tool("get_film", { id: "aw-not-a-real-item" });
check("an unknown film says so", miss.isError && /Not in Archive Watch/.test(miss.structuredContent.error));
const m = await tool("more_like_this", { id: "TheScarecrow1920" });
check("more_like_this returns films", m.structuredContent.films?.length > 0, JSON.stringify(m.structuredContent).slice(0, 200));
r = await call({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "nope" } });
check("an unknown tool is an error", r.json.error?.code === -32602);

console.log(failures ? `FAILED (${failures})` : "PASS mcp endpoint");
process.exit(failures ? 1 : 0);
