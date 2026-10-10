// carry — a passing verdict carried across a catch-up merge from the base.
//
// Verdicts are bound to the head SHA, and a strict up-to-date branch means
// every merge into main makes every queued PR merge main in, so each of them
// is reviewed again although its own change did not move. A pass bound to an
// earlier head H0 of the PR carries to the new head H only when H brings in
// nothing but the base:
//
//   1. the nearest earlier verdict of that reviewer (first-parent history of
//      H, within the PR's commits) is a bound `success`; a failure, an error
//      or nothing at all never carries, and an older pass behind a newer
//      failure is never reached;
//   2. a verdict that was itself carried is followed through `carried_from` to
//      the head that was actually reviewed (the root), and everything below is
//      checked against the root, never against the intermediate head;
//   3. the root is an ancestor of H (a force-push rewrite never carries);
//   4. the root's verdict names the base R_B it was reviewed against (the
//      reviewer read `git diff R_B...root`, which starts at merge-base(root,
//      R_B)), and with B the base tip now, M0 = merge-base(root, B) is that
//      same commit: when the base moved under the root since (one of the PR's
//      own commits merged into the base, or the base force-pushed), the diff
//      below would not be the one the reviewer read; a verdict that names no
//      R_B never carries;
//   5. with M = merge-base(H, B), `git diff M0 root` and `git diff M H` have
//      the same `patch-id --stable` and are byte for byte equal (patch-id
//      ignores whitespace, which is not always cosmetic), lockfiles and
//      binaries included;
//   6. no file the PR changes (at the root or at H) changed between M0 and M;
//   7. the base changed no merge-policy file, and no review guide the policy
//      names, between M0 and M.
//
// Any doubt (a git or API failure, criss-cross merge bases, a malformed
// binding) means no carry: the reviewer runs as before. This module decides;
// run-gate.mjs reads the evidence and posts the carried verdict as the
// merge-bot App from a step where no model or PR code runs.

import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const SHA_RE = /^[0-9a-f]{40}$/;
export const isSha = (s) => typeof s === "string" && SHA_RE.test(s);

/** How far back along the PR's first-parent history a source verdict is looked for. */
export const CARRY_CHAIN_MAX = 20;

/** The gate's own files on the base: a change to any of them between M0 and M re-reviews. */
export function isPolicyPath(path) {
  return (
    typeof path === "string" &&
    (path.startsWith(".github/merge-policy") || path === ".github/workflows/merge-gate.yml" || path === ".github/workflows/merge-watch.yml")
  );
}

/**
 * The PR's earlier commits along H's first-parent line, nearest first, from
 * GET /pulls/{n}/commits (each with `sha` and `parents`). The walk stops at
 * the first parent that is not one of the PR's commits (the base).
 * @returns {string[]}  never includes `head`
 */
export function firstParentChain(commits, head, max = CARRY_CHAIN_MAX) {
  const bySha = new Map((commits || []).filter((c) => isSha(c?.sha)).map((c) => [c.sha, c]));
  const out = [];
  let cur = bySha.get(head);
  while (cur && out.length < max) {
    const parent = cur.parents?.[0]?.sha;
    if (!isSha(parent) || !bySha.has(parent) || out.includes(parent) || parent === head) break;
    out.push(parent);
    cur = bySha.get(parent);
  }
  return out;
}

/**
 * The verdict a reviewer's carry would rest on: the nearest bound verdict on
 * `chain`, followed to its root when it was itself carried.
 * @param {{chain: string[], reviewer: string, verdictsAt: (sha: string) => Promise<Record<string, {state: string, model?: string, base?: string, carried_from?: string}>>}} a
 *   verdictsAt returns boundVerdicts() for one commit (bound to this PR and that commit)
 * @returns {Promise<{root: string, base?: string, via?: string, model?: string} | {reason: string}>}
 *   `base` is the base the root was reviewed against; absent when its verdict names none
 */
export async function findSource({ chain, reviewer, verdictsAt }) {
  for (const sha of chain || []) {
    const v = (await verdictsAt(sha))[reviewer];
    if (!v) continue;
    const short = sha.slice(0, 7);
    if (v.state !== "success") return { reason: `the nearest earlier ${reviewer} verdict (${short}) is ${v.state}` };
    if (v.carried_from === undefined) return { root: sha, ...(v.base ? { base: v.base } : {}), ...(v.model ? { model: v.model } : {}) };
    // Carried itself: the reviewed head is what every check runs against.
    const root = v.carried_from;
    if (!isSha(root) || root === sha) return { reason: `the ${reviewer} verdict on ${short} names no valid reviewed head` };
    const r = (await verdictsAt(root))[reviewer];
    if (!r || r.state !== "success" || r.carried_from !== undefined) {
      return { reason: `the ${reviewer} verdict on ${short} was carried from ${root.slice(0, 7)}, which holds no reviewed pass` };
    }
    return { root, ...(r.base ? { base: r.base } : {}), via: sha, ...(r.model ? { model: r.model } : {}) };
  }
  return { reason: `no earlier ${reviewer} verdict on this PR` };
}

/**
 * Every git command of the carry check (the fetches included) shares one
 * deadline this far out; past it, nothing carries and the reviewers run. The
 * API reads (the PR's commits, the verdicts) are not under it: a slow API is
 * bounded only by the classify job's timeout, which fails the gate closed.
 */
export const CARRY_BUDGET_MS = 4 * 60 * 1000;

/**
 * A git runner over one repository directory. `run(args, {input})` returns
 * {status, stdout (Buffer), stderr}; it never throws on a non-zero exit.
 * Every command shares one deadline, so a slow fetch costs the carry, never
 * the classify job (whose timeout would fail the gate).
 */
export function gitRunner(cwd, extraEnv = {}, deadline = Date.now() + CARRY_BUDGET_MS) {
  return (args, { input } = {}) => {
    const timeout = deadline - Date.now();
    if (timeout <= 0) return { status: -1, stdout: Buffer.alloc(0), stderr: "carry-forward time budget spent" };
    const r = spawnSync("git", args, {
      cwd,
      input,
      maxBuffer: 256 * 1024 * 1024,
      timeout,
      killSignal: "SIGKILL",
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0", GIT_LFS_SKIP_SMUDGE: "1", ...extraEnv },
    });
    if (r.error) return { status: -1, stdout: Buffer.alloc(0), stderr: r.error.message };
    return { status: r.status, stdout: r.stdout, stderr: String(r.stderr || "") };
  };
}

export const ok = (run, args, what) => {
  const r = run(args);
  if (r.status !== 0) throw new Error(`${what}: git ${args[0]} exited ${r.status}: ${r.stderr.slice(0, 300)}`);
  return r.stdout;
};

// The PR's own change, the same bytes on any machine: no external diff or
// textconv, no rename detection, binary content in full, fixed prefixes.
const DIFF = ["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--binary", "--full-index", "--no-color", "--src-prefix=a/", "--dst-prefix=b/"];

function names(run, a, b) {
  return ok(run, ["diff", "--no-ext-diff", "--no-renames", "--name-only", "-z", a, b], "changed paths")
    .toString("utf8")
    .split("\0")
    .filter(Boolean);
}

export function mergeBase(run, a, b) {
  const out = ok(run, ["merge-base", "--all", a, b], "merge-base").toString("utf8").split("\n").filter(Boolean);
  if (out.length !== 1 || !isSha(out[0])) throw new Error(`merge-base of ${a.slice(0, 7)} and ${b.slice(0, 7)} is not one commit (${out.length})`);
  return out[0];
}

/**
 * Checks 3-7 for carrying the root's verdict to `head`, against base tip
 * `base`. `reviewedBase` is the base the root was reviewed against (its
 * verdict's `base`); without it nothing carries. `policyPaths` are more
 * files that count as the merge policy (the policy's review guides).
 * @param {(args: string[], o?: object) => {status: number, stdout: Buffer, stderr: string}} run  gitRunner()
 * @param {{root: string, head: string, base: string, reviewedBase?: string, policyPaths?: string[]}} a
 * @returns {{ok: true, detail: string} | {ok: false, reason: string}}
 */
export function checkCarry(run, { root, head, base, reviewedBase, policyPaths = [] }) {
  try {
    // Verdicts posted before the base was bound (or by an older install) name none.
    if (reviewedBase === undefined) return { ok: false, reason: `the verdict on ${String(root).slice(0, 7)} names no reviewed base` };
    if (![root, head, base, reviewedBase].every(isSha)) return { ok: false, reason: "a commit id is malformed" };
    if (root === head) return { ok: false, reason: "the source is the head itself" };
    const anc = run(["merge-base", "--is-ancestor", root, head]);
    if (anc.status !== 0) return { ok: false, reason: `${root.slice(0, 7)} is not an ancestor of the head (rewritten history)` };
    const m0 = mergeBase(run, root, base);
    // The reviewer read `reviewedBase...root`, which starts at this commit. If
    // the base moved under the root since (one of the PR's own commits merged
    // into it, or a force-push of the base), the diff from M0 is not the one
    // the reviewer read, and the comparison below would vouch for it anyway.
    const reviewedM0 = mergeBase(run, root, reviewedBase);
    if (reviewedM0 !== m0) {
      return { ok: false, reason: `the base moved under ${root.slice(0, 7)} since its review (merge-base ${reviewedM0.slice(0, 7)} then, ${m0.slice(0, 7)} now)` };
    }
    const m = mergeBase(run, head, base);
    const baseChanged = m0 === m ? [] : names(run, m0, m);
    const policy = baseChanged.filter((p) => isPolicyPath(p) || policyPaths.includes(p));
    if (policy.length) return { ok: false, reason: `the base changed the merge policy since ${root.slice(0, 7)} (${policy.slice(0, 3).join(", ")})` };
    const prFiles = new Set([...names(run, m0, root), ...names(run, m, head)]);
    const overlap = baseChanged.filter((p) => prFiles.has(p));
    if (overlap.length) return { ok: false, reason: `the base changed files this PR changes (${overlap.slice(0, 3).join(", ")}${overlap.length > 3 ? ", …" : ""})` };
    const before = ok(run, [...DIFF, m0, root], "diff");
    const after = ok(run, [...DIFF, m, head], "diff");
    if (!before.length) return { ok: false, reason: "the reviewed change is empty" };
    const idBefore = patchIdOf(run, before);
    const idAfter = patchIdOf(run, after);
    if (!idBefore || idBefore !== idAfter) return { ok: false, reason: "the PR's own change differs from the reviewed one (patch-id)" };
    // patch-id ignores whitespace; Python, YAML and Makefiles do not.
    if (!before.equals(after)) return { ok: false, reason: "the PR's own change differs from the reviewed one (whitespace or mode)" };
    return {
      ok: true,
      detail: `the PR's own change is identical to ${root.slice(0, 7)}'s (patch-id ${idBefore.slice(0, 12)}), and the base brought in no change to its files or to the merge policy`,
    };
  } catch (e) {
    return { ok: false, reason: e.message.slice(0, 300) };
  }
}

function patchIdOf(run, diff) {
  const r = run(["patch-id", "--stable"], { input: diff });
  if (r.status !== 0) throw new Error(`patch-id exited ${r.status}: ${r.stderr.slice(0, 200)}`);
  return r.stdout.toString("utf8").trim().split(/\s+/)[0] || "";
}

/**
 * A throwaway bare repository holding the head's history and the base tip,
 * blobs fetched lazily (only the diffs read them). Nothing is checked out.
 * @param {{url: string, head: string, baseRef: string, token?: string, server?: string}} a
 * @returns {{run: Function, base: string, fetchCommit: (sha: string) => boolean, cleanup: () => void}}
 *   fetchCommit brings in one more commit's history (no blobs): the base a
 *   verdict was reviewed against, which the base tip may no longer reach.
 */
export function prepareCarryRepo({ url, head, baseRef, token, server = "https://github.com", deadline = Date.now() + CARRY_BUDGET_MS }) {
  if (!isSha(head)) throw new Error("head is not a commit id");
  const dir = mkdtempSync(join(tmpdir(), "merge-carry-"));
  const auth = token
    ? {
        GIT_CONFIG_COUNT: "1",
        GIT_CONFIG_KEY_0: `http.${server}/.extraheader`,
        GIT_CONFIG_VALUE_0: `AUTHORIZATION: basic ${Buffer.from(`x-access-token:${token}`).toString("base64")}`,
      }
    : { GIT_CONFIG_COUNT: "0" };
  const run = gitRunner(dir, auth, deadline);
  const cleanup = () => rmSync(dir, { recursive: true, force: true });
  try {
    const ref = `refs/heads/${baseRef}`;
    if (typeof baseRef !== "string" || !baseRef || run(["check-ref-format", ref]).status !== 0) throw new Error(`base ref ${JSON.stringify(baseRef)} is not a valid branch`);
    ok(run, ["init", "-q", "--bare"], "init");
    ok(run, ["remote", "add", "origin", url], "remote");
    ok(run, ["config", "remote.origin.promisor", "true"], "config");
    ok(run, ["config", "remote.origin.partialclonefilter", "blob:none"], "config");
    ok(run, ["fetch", "-q", "--no-tags", "--filter=blob:none", "origin", `${head}:refs/carry/head`, `+${ref}:refs/carry/base`], "fetch");
    const base = ok(run, ["rev-parse", "--verify", "refs/carry/base^{commit}"], "rev-parse").toString("utf8").trim();
    if (!isSha(base)) throw new Error("base tip unreadable");
    const fetchCommit = (sha) => isSha(sha) && run(["fetch", "-q", "--no-tags", "--filter=blob:none", "origin", sha]).status === 0;
    return { run, base, fetchCommit, cleanup };
  } catch (e) {
    cleanup();
    throw e;
  }
}

/**
 * Which of the reviewers still needed on the head carry a verdict forward.
 * A reviewer with any bound verdict on the head itself (an error included)
 * is reviewed again: carry only fills a head nothing has judged.
 * @param {object} a
 * @param {object} a.policy  merged policy (carry_forward)
 * @param {string[]} a.reviewers  reviewers the head still needs
 * @param {Record<string, object>} a.onHead  bound verdicts on the head
 * @param {string[]} a.chain  firstParentChain()
 * @param {(sha: string) => Promise<Record<string, object>>} a.verdictsAt
 * @param {(root: string, base?: string) => Promise<{ok: boolean, detail?: string, reason?: string}>} a.check  checkCarry for a root reviewed against `base`
 * @returns {Promise<{carried: Array<{name: string, from: string, via?: string, model?: string, detail: string}>, notes: string[]}>}
 */
export async function planCarry({ policy, reviewers, onHead = {}, chain, verdictsAt, check }) {
  const carried = [];
  const notes = [];
  if (policy?.carry_forward !== true) return { carried, notes: reviewers.length ? ["carry_forward is off"] : [] };
  const checked = new Map();
  for (const name of reviewers) {
    if (onHead[name]) {
      notes.push(`${name}: the head already has a ${onHead[name].state} verdict`);
      continue;
    }
    const src = await findSource({ chain, reviewer: name, verdictsAt });
    if (src.reason) {
      notes.push(`${name}: ${src.reason}`);
      continue;
    }
    const key = `${src.root}:${src.base || ""}`;
    if (!checked.has(key)) checked.set(key, await check(src.root, src.base));
    const res = checked.get(key);
    if (!res.ok) {
      notes.push(`${name}: not carried from ${src.root.slice(0, 7)}: ${res.reason}`);
      continue;
    }
    carried.push({ name, from: src.root, ...(src.via ? { via: src.via } : {}), ...(src.model ? { model: src.model } : {}), detail: res.detail });
  }
  return { carried, notes };
}
