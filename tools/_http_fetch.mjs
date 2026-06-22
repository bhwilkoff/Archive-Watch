#!/usr/bin/env node
// Tiny HTTP helper for free_subtitles.py. Reads a JSON spec from stdin
// {method,url,headers,body} and writes {status, body_b64} (or {status:0,error}) to
// stdout. Uses Node's modern OpenSSL so it works where macOS system Python's old
// LibreSSL can't TLS-handshake with Cloudflare-fronted hosts (subdl/subsource).
let input = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) input += chunk;
let spec;
try { spec = JSON.parse(input); }
catch { process.stdout.write(JSON.stringify({ status: 0, error: "bad spec" })); process.exit(0); }
try {
  const res = await fetch(spec.url, {
    method: spec.method || "GET",
    headers: spec.headers || {},
    body: spec.body,
    redirect: "follow",
  });
  const buf = Buffer.from(await res.arrayBuffer());
  process.stdout.write(JSON.stringify({ status: res.status, body_b64: buf.toString("base64") }));
} catch (e) {
  const cause = e && e.cause ? (e.cause.code || e.cause.message || "") : "";
  process.stdout.write(JSON.stringify({ status: 0, error: String((e && e.message) || e), cause: String(cause) }));
}
