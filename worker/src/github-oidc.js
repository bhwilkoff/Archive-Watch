/**
 * The removal check's route, by GitHub Actions OIDC instead of a stored token (docs/SECRETS-PLAN.md; owner
 * 2026-11-22: "I do not want to set or keep track of keys and passwords for this repo.").
 *
 * takedown-check.yml (id-token: write) asks GitHub for a short-lived JWT whose `aud` is this Worker's origin. It is
 * checked against GitHub's published keys, and its claims must name this repository (by name and by id, so a
 * deleted-and-recreated namesake cannot pass), the main branch, that one workflow file, and the events it runs on.
 * Fork pull requests are never given an id token. Every pin is a constant, so no environment can loosen it. The
 * one test seam, LOCAL_TEST_JWKS, is refused on any host but this machine's own.
 */
import { TokenError, verifyIdentityToken } from "./jwt.js";

export const GITHUB_ISSUER = "https://token.actions.githubusercontent.com";
const GITHUB_JWKS = `${GITHUB_ISSUER}/.well-known/jwks`;
export const REPOSITORY = "bhwilkoff/Archive-Watch";
export const REPOSITORY_ID = "1213936872";
export const MAIN = "refs/heads/main";

/** Which workflow may call which route, and on which events. */
export const OWNER_WORKFLOWS = {
  takedown: { workflow: ".github/workflows/takedown-check.yml", events: ["schedule", "workflow_dispatch"] },
};

const LOCAL_HOST = /^(localhost|127\.0\.0\.1|\[::1\])$/;

/** Test keys from LOCAL_TEST_JWKS, and only when the request reached this machine itself. */
function testKeys(env, url) {
  if (!env.LOCAL_TEST_JWKS || !LOCAL_HOST.test(url.hostname)) return undefined;
  try {
    const set = JSON.parse(env.LOCAL_TEST_JWKS);
    return Array.isArray(set.keys) ? set.keys : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The verified claims of the bearer's GitHub token for `route`, or null. Never throws.
 * @param {"takedown"} route
 */
export async function githubCaller(request, env, url, route, nowMs = Date.now()) {
  const rule = OWNER_WORKFLOWS[route];
  if (env.LOCAL_TEST_JWKS && !LOCAL_HOST.test(url.hostname)) return null;
  const header = request.headers.get("authorization") || "";
  if (!rule || !header.startsWith("Bearer ")) return null;
  try {
    const c = await verifyIdentityToken(
      header.slice("Bearer ".length),
      { jwksUrl: GITHUB_JWKS, issuers: [GITHUB_ISSUER], audiences: [url.origin], keys: testKeys(env, url) },
      nowMs,
    );
    if (c.repository !== REPOSITORY) throw new TokenError("bad_repository");
    if (String(c.repository_id) !== REPOSITORY_ID) throw new TokenError("bad_repository_id");
    if (c.ref !== MAIN) throw new TokenError("bad_ref");
    if (c.job_workflow_ref !== `${REPOSITORY}/${rule.workflow}@${MAIN}`) throw new TokenError("bad_workflow");
    if (!rule.events.includes(c.event_name)) throw new TokenError("bad_event");
    return c;
  } catch {
    return null;
  }
}
