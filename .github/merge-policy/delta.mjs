// delta — a follow-up review reads the change since the reviewer's last verdict.
//
// A PR is usually pushed to several times while it is reviewed, and every push
// re-ran each reviewer over the whole PR: on wearelojik/cinema-engine#277
// (26,914 changed lines) each ~300-line fix round re-read everything, nine
// reviews for $170 in three hours on 2026-10-09. A reviewer whose last verdict
// on this PR was a reviewed pass or failure on an earlier head H0 instead reads
// `git diff H0 H`, with its findings on H0, when all of these hold:
//
//   1. the nearest verdict of that reviewer on H's first-parent history
//      (within the PR's commits) that is not an `error` is a reviewed pass or
//      failure: an error read nothing, so the search goes past it; a carried
//      pass (src/carry.mjs) is not a review of H0, so it never seeds a delta;
//   2. that verdict names the base R_B it was reviewed against;
//   3. H0 is an ancestor of H, and merge-base(H, B) for the base tip B is
//      merge-base(H0, R_B), where the reviewer's diff started: H merged
//      nothing from the base since, and the base was not rewritten under it;
//   4. the change since H0 is not empty, touches no merge-policy file or
//      review guide, and is at most `max_lines` changed lines and at most
//      `max_fraction` of the PR's own change;
//   5. H0's verdict ends fewer than `max_depth` follow-ups in a row: after
//      that the next review reads the whole PR again.
//
// Any doubt (a git or API failure, a malformed binding) means a full review.
// The follow-up still has the whole PR diff and the head checked out; it is
// told to read the change since H0 first and the rest only as it needs.

import { isPolicyPath, isSha, mergeBase, ok } from "./carry.mjs";

export const DELTA_DEFAULTS = { max_lines: 1500, max_fraction: 0.5, max_depth: 2 };

/**
 * The verdict a reviewer's follow-up would start from.
 * @param {{chain: string[], reviewer: string, verdictsAt: (sha: string) => Promise<Record<string, object>>}} a
 * @returns {Promise<{from: string, base: string, depth: number, state: string, findings: string, model?: string} | {reason: string}>}
 */
export async function findPrior({ chain, reviewer, verdictsAt }) {
  for (const sha of chain || []) {
    const v = (await verdictsAt(sha))[reviewer];
    if (!v || v.state === "error") continue;
    const short = sha.slice(0, 7);
    if (v.carried_from !== undefined) return { reason: `the nearest ${reviewer} verdict (${short}) was carried, not reviewed` };
    if (!isSha(v.base)) return { reason: `the ${reviewer} verdict on ${short} names no reviewed base` };
    const depth = v.delta_depth ?? 0;
    return { from: sha, base: v.base, depth, state: v.state, findings: String(v.findings || ""), ...(v.model ? { model: v.model } : {}) };
  }
  return { reason: `no earlier reviewed ${reviewer} verdict on this PR` };
}

/** Changed lines per path between two commits (binary files count 0), renames as delete + add. */
function numstat(run, a, b) {
  return ok(run, ["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--numstat", "-z", a, b], "numstat")
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .map((row) => {
      const [add, del, ...rest] = row.split("\t");
      return { path: rest.join("\t"), lines: (Number(add) || 0) + (Number(del) || 0) };
    });
}

/**
 * Checks 3 and 4 for a follow-up from `from` to `head`, against base tip `base`.
 * @param {(args: string[], o?: object) => {status: number, stdout: Buffer, stderr: string}} run  gitRunner()
 * @param {{from: string, head: string, base: string, reviewedBase: string, cfg?: object, policyPaths?: string[], prLines?: number}} a
 *   prLines: the PR's changed lines when the API already says (saves fetching every blob)
 * @returns {{ok: true, lines: number, files: number, prLines: number} | {ok: false, reason: string}}
 */
export function checkDelta(run, { from, head, base, reviewedBase, cfg = DELTA_DEFAULTS, policyPaths = [], prLines: given }) {
  try {
    if (![from, head, base, reviewedBase].every(isSha)) return { ok: false, reason: "a commit id is malformed" };
    if (from === head) return { ok: false, reason: "the source is the head itself" };
    if (run(["merge-base", "--is-ancestor", from, head]).status !== 0) return { ok: false, reason: `${from.slice(0, 7)} is not an ancestor of the head (rewritten history)` };
    const then = mergeBase(run, from, reviewedBase);
    const now = mergeBase(run, head, base);
    if (then !== now) return { ok: false, reason: `the PR's merge-base moved since ${from.slice(0, 7)} (${then.slice(0, 7)} then, ${now.slice(0, 7)} now)` };
    const since = numstat(run, from, head);
    if (!since.length) return { ok: false, reason: `nothing changed since ${from.slice(0, 7)}` };
    const policy = since.map((f) => f.path).filter((p) => isPolicyPath(p) || policyPaths.includes(p));
    if (policy.length) return { ok: false, reason: `the change since ${from.slice(0, 7)} touches the merge policy (${policy.slice(0, 3).join(", ")})` };
    const lines = since.reduce((s, f) => s + f.lines, 0);
    if (lines > cfg.max_lines) return { ok: false, reason: `${lines} lines changed since ${from.slice(0, 7)}, over ${cfg.max_lines}` };
    const prLines = Number.isInteger(given) && given > 0 ? given : numstat(run, now, head).reduce((s, f) => s + f.lines, 0);
    if (lines > cfg.max_fraction * prLines) return { ok: false, reason: `the change since ${from.slice(0, 7)} is ${lines} of the PR's ${prLines} lines, over ${Math.round(cfg.max_fraction * 100)}%` };
    return { ok: true, lines, files: since.length, prLines };
  } catch (e) {
    return { ok: false, reason: e.message.slice(0, 300) };
  }
}

/**
 * Which reviewers the head still needs review only the change since their last verdict.
 * @param {object} a
 * @param {object} a.policy  merged policy (delta_review: false or {max_lines, max_fraction, max_depth})
 * @param {string[]} a.reviewers  reviewers that run on this head (not carried, no verdict yet)
 * @param {string[]} a.chain  firstParentChain()
 * @param {(sha: string) => Promise<Record<string, object>>} a.verdictsAt
 * @param {(from: string, reviewedBase: string) => Promise<object>} a.check  checkDelta for one source
 * @returns {Promise<{delta: Record<string, {from: string, depth: number, state: string, lines: number, files: number, findings: string}>, notes: string[]}>}
 */
export async function planDelta({ policy, reviewers, chain, verdictsAt, check }) {
  const delta = {};
  const notes = [];
  const cfg = policy?.delta_review;
  if (!cfg) return { delta, notes: reviewers.length ? ["delta_review is off"] : [] };
  const checked = new Map();
  for (const name of reviewers) {
    const prior = await findPrior({ chain, reviewer: name, verdictsAt });
    if (prior.reason) {
      notes.push(`${name}: full review: ${prior.reason}`);
      continue;
    }
    if (!(prior.depth < cfg.max_depth)) {
      notes.push(`${name}: full review after ${prior.depth} follow-ups in a row`);
      continue;
    }
    const key = `${prior.from}:${prior.base}`;
    if (!checked.has(key)) checked.set(key, await check(prior.from, prior.base));
    const res = checked.get(key);
    if (!res.ok) {
      notes.push(`${name}: full review: ${res.reason}`);
      continue;
    }
    delta[name] = { from: prior.from, depth: prior.depth + 1, state: prior.state, lines: res.lines, files: res.files, findings: prior.findings };
    notes.push(`${name}: follow-up of ${prior.from.slice(0, 7)} (${res.lines} of ${res.prLines} lines, ${prior.depth + 1}/${cfg.max_depth})`);
  }
  return { delta, notes };
}
