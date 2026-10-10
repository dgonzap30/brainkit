// policy — loads a repo's .github/merge-policy.json over the defaults.

import { readFileSync, existsSync } from "node:fs";
import { DEFAULTS } from "./classify.mjs";
import { matchesAny } from "./glob.mjs";
import { DELTA_DEFAULTS } from "./delta.mjs";

// The merge-bot GitHub App (dgz-merge-bot). Its check runs are the only
// evidence the gate accepts: merge-gate, and the merge-review/* verdicts.
export const DEFAULT_BOT_APP_ID = 5124966;

/** The App id whose check runs count: the policy's, else the default. */
export const botAppId = (p) => Number(p?.bot_app_id) || DEFAULT_BOT_APP_ID;

export const POLICY_DEFAULTS = {
  version: 1,
  mode: "native", // native: ruleset + GitHub auto-merge; direct: the gate merges when CI is green (Free-plan private repos)
  merge_method: "squash",
  owner_login: "dgonzap30",
  bot_slug: "", // the merge-bot GitHub App slug; its "<slug>[bot]" reverts are green
  bot_app_id: null, // the merge-bot App's id (null: DEFAULT_BOT_APP_ID): the only source of merge-gate and verdicts
  freeze_after_reverts: 2, // this many bot reverts in 24h opens a merge:freeze issue
  required_checks: [], // CI check-run names that must be green (also written into the ruleset by `merge-policy settings`)
  // `cross` (OpenAI) runs only when cross_review is on: a repo without the
  // OPENAI_API_KEY secret would otherwise hold every reviewed PR.
  reviewers: {
    reviewed: ["standard", "cross"],
    critical: ["standard", "adversarial", "cross"],
  },
  cross_review: false, // set by `merge-policy install` when the merge-bot environment holds OPENAI_API_KEY
  // A pass on an earlier head carries to a head that only merged the base in
  // (src/carry.mjs); false re-reviews every head. Owner approval never carries.
  carry_forward: true,
  // A reviewer whose last verdict on this PR was a reviewed pass or failure
  // reads only the change since then, with its findings, within these limits
  // (src/delta.mjs); false reads the whole PR on every head.
  delta_review: DELTA_DEFAULTS,
  // Path-scoped review rubrics: [{paths: [glob...], file: "docs/review/x.md"}].
  // A guide whose paths match a changed file is read from the BASE commit and
  // given to the reviewers as trusted instructions (src/review.mjs). Each
  // guide file is an owner path, so changing one needs the owner's approval.
  review_guides: [],
  // "latest:<family>" resolves at review time to the provider's newest GA model
  // of the family, never older than the pinned floor (src/models.mjs). The
  // adversarial pass runs Opus too (owner, 2026-10-08); its separate prompt is
  // what makes it adversarial. `latest:fable` remains a valid selector.
  models: {
    standard: "latest:opus",
    adversarial: "latest:opus",
    cross: "latest:sol",
  },
  effort: {
    standard: "high",
    adversarial: "high",
    cross: "high",
  },
  watch: {
    ci_workflows: [], // workflow names whose default-branch runs are watched
    deploy_environments: [], // GitHub deployment environments whose statuses are watched
    health_urls: [], // GET must return 2xx, without a redirect to another host, after a successful deploy
    watch_minutes: 10,
    auto_revert: true,
    sentry: null, // { org, project, max_new_issues: 0, min_events: 5 } — needs SENTRY_AUTH_TOKEN
  },
};

/**
 * The reviewers each tier requires. `cross` counts only when the repo turned
 * cross_review on; once on, a missing cross verdict fails the gate like any other.
 * @param {Record<string, string[]>} byTier
 * @param {boolean} crossReview
 */
export function activeReviewers(byTier, crossReview) {
  const out = {};
  for (const [tier, names] of Object.entries(byTier || {})) {
    out[tier] = [...new Set(names || [])].filter((n) => crossReview || n !== "cross");
  }
  return out;
}

export function mergePolicy(raw = {}) {
  const p = { ...DEFAULTS, ...POLICY_DEFAULTS, ...raw };
  p.reviewers = activeReviewers({ ...POLICY_DEFAULTS.reviewers, ...(raw.reviewers || {}) }, p.cross_review === true);
  p.models = { ...POLICY_DEFAULTS.models, ...(raw.models || {}) };
  p.effort = { ...POLICY_DEFAULTS.effort, ...(raw.effort || {}) };
  p.watch = { ...POLICY_DEFAULTS.watch, ...(raw.watch || {}) };
  p.delta_review = deltaReview(raw.delta_review);
  // Additive path lists: a repo extends the defaults, and removes entries only
  // through an explicit `*_paths_remove` list (visible in review).
  for (const key of ["owner_paths", "critical_paths", "critical_overrides_green", "green_paths", "size_exempt_paths"]) {
    const extra = raw[`${key}_add`] || [];
    const drop = new Set(raw[`${key}_remove`] || []);
    const base = raw[key] || DEFAULTS[key];
    p[key] = [...base, ...extra].filter((x) => !drop.has(x));
  }
  // The gate's own files can never leave the owner tier.
  for (const locked of DEFAULTS.owner_paths) {
    if (!p.owner_paths.includes(locked)) p.owner_paths.push(locked);
  }
  // Nor can a review guide: it steers the reviewers on every matching PR.
  p.review_guides = validateReviewGuides(raw.review_guides ?? []);
  for (const pattern of guideOwnerPatterns(p.review_guides)) {
    if (!p.owner_paths.includes(pattern)) p.owner_paths.push(pattern);
  }
  return p;
}

/**
 * `delta_review` as the gate uses it: false, or limits each a valid number.
 * A malformed limit falls back to its default rather than to "no limit".
 */
function deltaReview(raw) {
  if (raw === false) return false;
  const o = raw && typeof raw === "object" ? raw : {};
  const pick = (k, ok) => (ok(o[k]) ? o[k] : DELTA_DEFAULTS[k]);
  return {
    max_lines: pick("max_lines", (v) => Number.isInteger(v) && v > 0),
    max_fraction: pick("max_fraction", (v) => typeof v === "number" && v > 0 && v <= 1),
    max_depth: pick("max_depth", (v) => Number.isInteger(v) && v >= 1),
  };
}

/** At most this many review guides per repo. */
export const REVIEW_GUIDES_MAX = 8;

/**
 * A plain repo-relative file path: no leading `/`, no `.`/`..`/empty segment,
 * no backslash, no control character, no glob metacharacter (the file is also
 * an owner path, matched literally), at most 256 characters.
 */
export function isGuideFile(file) {
  return (
    typeof file === "string" &&
    file.length > 0 &&
    file.length <= 256 &&
    !file.startsWith("/") &&
    !/[\x00-\x1f\x7f\\*?{}[\]]/.test(file) &&
    file.split("/").every((seg) => seg !== "" && seg !== "." && seg !== "..")
  );
}

/**
 * `review_guides` checked for shape: an array of at most REVIEW_GUIDES_MAX
 * `{paths: string[] (non-empty), file: string (isGuideFile)}` with no other
 * key. A malformed list throws: `install` refuses it, and in a repo the gate
 * fails closed rather than review without the rubric the owner configured.
 * @returns {Array<{paths: string[], file: string}>}
 */
export function validateReviewGuides(guides) {
  const bad = (why) => {
    throw new Error(`policy review_guides: ${why}`);
  };
  if (!Array.isArray(guides)) bad("must be an array");
  if (guides.length > REVIEW_GUIDES_MAX) bad(`at most ${REVIEW_GUIDES_MAX} guides (got ${guides.length})`);
  return guides.map((g, i) => {
    if (!g || typeof g !== "object" || Array.isArray(g)) bad(`entry ${i} is not an object`);
    const extra = Object.keys(g).filter((k) => k !== "paths" && k !== "file");
    if (extra.length) bad(`entry ${i} has unknown key(s) ${extra.join(", ")}`);
    if (!Array.isArray(g.paths) || !g.paths.length || !g.paths.every((x) => typeof x === "string" && x.length > 0 && x.length <= 256)) {
      bad(`entry ${i} needs paths: a non-empty array of glob strings`);
    }
    if (!isGuideFile(g.file)) bad(`entry ${i} file ${JSON.stringify(g.file)} is not a plain repo-relative path`);
    return { paths: [...g.paths], file: g.file };
  });
}

/** The owner-path pattern for each guide file, anchored at the repo root (a bare name would match at any depth). */
export function guideOwnerPatterns(guides = []) {
  return [...new Set(guides.map((g) => (g.file.includes("/") ? g.file : `/${g.file}`)))];
}

/** A guide for every path: its `paths` are all `**`. */
export const isCatchAllGuide = (g) => g.paths.every((p) => p === "**");

/**
 * The guide files whose `paths` match any changed path (renames on both
 * sides), each once: the specific guides first, then the catch-all ones, each
 * group in policy order. The review step reads them in this order under one
 * byte budget, so a long catch-all guide cannot push a specific one out.
 * @param {Array<{paths: string[], file: string}>} guides  merged policy's review_guides
 * @param {string[]} changed  changed paths
 * @returns {string[]}
 */
export function matchGuides(guides = [], changed = []) {
  const out = [];
  const ordered = [...guides.filter((g) => !isCatchAllGuide(g)), ...guides.filter(isCatchAllGuide)];
  for (const g of ordered) {
    if (!out.includes(g.file) && changed.some((f) => matchesAny(f, g.paths))) out.push(g.file);
  }
  return out;
}

export function loadPolicy(path = ".github/merge-policy.json") {
  if (!existsSync(path)) return mergePolicy({});
  return mergePolicy(JSON.parse(readFileSync(path, "utf8")));
}
