/**
 * JSON Web Tokens with Web Crypto only: an RS256 identity token checked against a
 * provider's published keys (here GitHub Actions').
 *
 * Every check fails closed. The algorithm is fixed by the caller, never read
 * from the token's header, so `alg: none` or an HS256 token signed with a
 * public key cannot pass as RS256.
 */

const enc = new TextEncoder();
const dec = new TextDecoder();

export function b64urlEncode(bytes) {
  if (typeof bytes === "string") bytes = enc.encode(bytes);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(str) {
  if (typeof str !== "string" || !/^[A-Za-z0-9_-]*$/.test(str)) throw new Error("bad base64url");
  const pad = str.length % 4 === 0 ? "" : "=".repeat(4 - (str.length % 4));
  const bin = atob(str.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export class TokenError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

function split(token) {
  if (typeof token !== "string" || token.length > 8192) throw new TokenError("malformed");
  const parts = token.split(".");
  if (parts.length !== 3) throw new TokenError("malformed");
  let header, payload, sig;
  try {
    header = JSON.parse(dec.decode(b64urlDecode(parts[0])));
    payload = JSON.parse(dec.decode(b64urlDecode(parts[1])));
    sig = b64urlDecode(parts[2]);
  } catch {
    throw new TokenError("malformed");
  }
  if (!header || typeof header !== "object" || !payload || typeof payload !== "object") {
    throw new TokenError("malformed");
  }
  return { header, payload, signed: enc.encode(`${parts[0]}.${parts[1]}`), sig };
}

/** Clock leeway for exp / iat / nbf, in seconds. */
const LEEWAY = 60;

function checkTimes(payload, nowSec) {
  if (typeof payload.exp !== "number") throw new TokenError("no_exp");
  if (payload.exp + LEEWAY < nowSec) throw new TokenError("expired");
  if (typeof payload.nbf === "number" && payload.nbf - LEEWAY > nowSec) throw new TokenError("not_yet_valid");
  if (typeof payload.iat === "number" && payload.iat - LEEWAY > nowSec) throw new TokenError("issued_in_future");
}

function audienceMatches(aud, allowed) {
  const list = Array.isArray(aud) ? aud : [aud];
  return list.some((a) => typeof a === "string" && allowed.includes(a));
}

/* ---------- provider keys (JWKS) ---------- */

const JWKS_TTL_MS = 60 * 60 * 1000;
const JWKS_REFETCH_FLOOR_MS = 60 * 1000;
const jwksCache = new Map(); // url -> { keys, fetchedAt }

async function fetchJwks(url) {
  const r = await fetch(url, { headers: { accept: "application/json" } });
  if (!r.ok) throw new TokenError("jwks_unavailable");
  const body = await r.json();
  if (!body || !Array.isArray(body.keys)) throw new TokenError("jwks_unavailable");
  const entry = { keys: body.keys, fetchedAt: Date.now() };
  jwksCache.set(url, entry);
  return entry;
}

/** For tests: forget every cached key set. */
export function clearJwksCache() {
  jwksCache.clear();
}

async function keyFor(url, kid, given) {
  if (given) return importRsa(given.find((k) => k.kid === kid));
  let entry = jwksCache.get(url);
  if (!entry || Date.now() - entry.fetchedAt > JWKS_TTL_MS) entry = await fetchJwks(url);
  let jwk = entry.keys.find((k) => k.kid === kid);
  // A provider rotates keys; an unknown kid earns one refetch, at most once a
  // minute, so a stream of junk kids cannot make us hammer the provider.
  if (!jwk && Date.now() - entry.fetchedAt > JWKS_REFETCH_FLOOR_MS) {
    entry = await fetchJwks(url);
    jwk = entry.keys.find((k) => k.kid === kid);
  }
  return importRsa(jwk);
}

function importRsa(jwk) {
  if (!jwk || jwk.kty !== "RSA") throw new TokenError("unknown_key");
  return crypto.subtle.importKey(
    "jwk",
    { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

/**
 * Verify a provider's RS256 identity token.
 * @param {string} token
 * @param {{ jwksUrl: string, issuers: string[], audiences: string[], keys?: object[] }} rules  `keys` in place of the
 *   provider's published set: only the local test keys (github-oidc.js), never in production
 * @returns the payload, or throws TokenError
 */
export async function verifyIdentityToken(token, rules, nowMs = Date.now()) {
  const { header, payload, signed, sig } = split(token);
  if (header.alg !== "RS256") throw new TokenError("bad_alg");
  if (typeof header.kid !== "string" || !header.kid) throw new TokenError("no_kid");
  const key = await keyFor(rules.jwksUrl, header.kid, rules.keys);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, sig, signed);
  if (!ok) throw new TokenError("bad_signature");
  if (!rules.issuers.includes(payload.iss)) throw new TokenError("bad_issuer");
  const audiences = rules.audiences.filter((a) => a && !a.startsWith("REPLACE_WITH"));
  if (audiences.length === 0) throw new TokenError("audience_not_configured");
  if (!audienceMatches(payload.aud, audiences)) throw new TokenError("bad_audience");
  checkTimes(payload, Math.floor(nowMs / 1000));
  if (typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 255) {
    throw new TokenError("no_subject");
  }
  return payload;
}
