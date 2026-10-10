#!/usr/bin/env node
// run-gate — the merge-gate workflow's entry point.
//
//   node run-gate.mjs classify   -> outputs: pr, head_sha, tier, reviewers_needed, ...
//   node run-gate.mjs decide     -> arms / disarms / merges, labels, sticky comment, the App's merge-gate check
//   node run-gate.mjs fail-check -> classification did not complete: a failing merge-gate check
//   node run-gate.mjs carry-post -> posts the passes classify carried forward (src/carry.mjs) as the App
//
// Runs from the BASE branch checkout (pull_request_target / workflow_run /
// workflow_dispatch). PR content is read through the API as data and never
// executed.

import { randomUUID } from "node:crypto";
import { appendFileSync, existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { checkCarry, firstParentChain, isSha, planCarry, prepareCarryRepo } from "./carry.mjs";
import { checkDelta, planDelta } from "./delta.mjs";
import { classify, needsHeadCommit, renameBlobNeeds, SQL_CONTENT_MAX, sqlContentNeeds, sqlModeNeeds } from "./classify.mjs";
import {
  APPROVAL_CHECK,
  approvalCheck,
  approvalRecord,
  approvalRunAllows,
  approvalToRecord,
  decide,
  keepOwnerArming,
  LABELS,
  ownerApproved,
  ownerNotice,
  ownerNotified,
  ownerReviewNeeded,
} from "./gate.mjs";
import { GitHub } from "./github.mjs";
import { botAppId, loadPolicy, matchGuides } from "./policy.mjs";
import { boundVerdicts, redact, verdictCheck } from "./verdict.mjs";

const env = process.env;
const repo = env.GITHUB_REPOSITORY;
const ACTIONS_BOT = "github-actions[bot]";
const GATE_CHECK = "merge-gate";
const STICKY = "<!-- merge-policy:gate -->";

/**
 * One GITHUB_OUTPUT entry in the heredoc form. A random delimiter per entry
 * means no value (a filename, a reason) can close the entry early and inject
 * another key: `key=value` lines let a newline in a filename set `tier=green`.
 */
export function outputEntry(key, value) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  let delim = `EOF_${randomUUID()}`;
  while (text.includes(delim)) delim = `EOF_${randomUUID()}`;
  return `${key}<<${delim}\n${text}\n${delim}\n`;
}

function output(key, value) {
  const entry = outputEntry(key, value);
  if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, entry);
  else process.stdout.write(entry);
}

function summary(md) {
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, `${md}\n`);
  else process.stdout.write(`${md}\n`);
}

function event() {
  return env.GITHUB_EVENT_PATH && existsSync(env.GITHUB_EVENT_PATH)
    ? JSON.parse(readFileSync(env.GITHUB_EVENT_PATH, "utf8"))
    : {};
}

async function resolvePrNumber(gh, ev) {
  if (env.PR_NUMBER) return Number(env.PR_NUMBER);
  if (ev.pull_request?.number) return ev.pull_request.number;
  if (ev.inputs?.pr) return Number(ev.inputs.pr);
  if (ev.workflow_run) {
    const direct = ev.workflow_run.pull_requests?.[0]?.number;
    if (direct) return direct;
    const pulls = await gh.get(`/repos/{repo}/commits/${ev.workflow_run.head_sha}/pulls`);
    return pulls.find((p) => p.state === "open")?.number ?? null;
  }
  return null;
}

async function isFrozen(gh) {
  const issues = await gh.get(`/repos/{repo}/issues?state=open&labels=${encodeURIComponent(LABELS.freeze)}&per_page=1`);
  return issues.length > 0;
}

/**
 * Newest bound verdict per reviewer: the merge-bot App's own merge-review/*
 * check runs on this head for this PR (see boundVerdicts). Statuses and
 * artifacts are not read: any workflow run can produce those.
 * @param {number} appId  botAppId(policy)
 */
export async function reviewVerdicts(gh, sha, pr, appId) {
  const runs = await gh.paginate(`/repos/{repo}/commits/${sha}/check-runs?filter=all&app_id=${appId}`, "check_runs");
  return boundVerdicts(runs, {
    sha,
    prNumber: pr.number,
    appId,
    onIgnore: (r, why) => console.log(`ignoring ${r.name} (${r.conclusion}) check run ${r.id}: ${why}`),
  });
}

/**
 * Classify's carry-forward (src/carry.mjs): which of the reviewers the head
 * still needs take a pass from an earlier head of this PR. The PR's commits
 * and the App's verdicts are read through the API; the change is compared
 * with git in a throwaway bare repository, fetched (blobs lazily) only once a
 * source pass exists. Nothing is posted here, and nothing from the PR runs.
 * Any failure carries nothing, so the reviewers run as before.
 *
 * The reviewers it does not carry may instead review only the change since
 * their last verdict (src/delta.mjs), checked in the same repository. Any
 * failure there means a full review; it never drops a carry.
 * @param {object} a
 * @param {string[]} a.reviewers  reviewers the head still needs
 * @param {Record<string, object>} a.onHead  bound verdicts already on the head
 * @param {Function} [a.prepare]  prepareCarryRepo (tests pass a local repository)
 * @returns {Promise<{carried: object[], notes: string[], delta: Record<string, object>}>}
 */
export async function carryForward({ gh, pr, policy, reviewers, onHead, vars = env, prepare = prepareCarryRepo, log = console.log }) {
  const carryOn = policy.carry_forward === true;
  if ((!carryOn && !policy.delta_review) || !reviewers.length) return { carried: [], notes: [], delta: {} };
  const appId = botAppId(policy);
  const server = vars.GITHUB_SERVER_URL || "https://github.com";
  // A review guide the base changed since the review re-reviews, like the gate's own files.
  const policyPaths = (policy.review_guides || []).map((g) => g.file);
  let local;
  const repoFor = () => (local ??= prepare({ url: `${server}/${vars.GITHUB_REPOSITORY || repo}.git`, head: pr.head.sha, baseRef: pr.base.ref, token: vars.GH_TOKEN, server }));
  // The reviewed base may be gone from the base branch (a force-push).
  const lostBase = (reviewedBase, from) =>
    repoFor().fetchCommit && !local.fetchCommit(reviewedBase) ? { ok: false, reason: `the base ${reviewedBase.slice(0, 7)} the verdict on ${from.slice(0, 7)} was reviewed against cannot be fetched` } : undefined;
  let chain, verdictsAt;
  let result = { carried: [], notes: [], delta: {} };
  try {
    const commits = await gh.paginate(`/repos/{repo}/pulls/${pr.number}/commits`);
    chain = firstParentChain(commits, pr.head.sha);
    const seen = new Map();
    verdictsAt = (sha) => {
      if (!seen.has(sha)) seen.set(sha, reviewVerdicts(gh, sha, pr, appId));
      return seen.get(sha);
    };
    const check = async (root, reviewedBase) => {
      // No reviewed base: checkCarry refuses before any git command, so nothing is fetched.
      if (!isSha(reviewedBase)) return checkCarry(null, { root, reviewedBase });
      return lostBase(reviewedBase, root) || checkCarry(local.run, { root, head: pr.head.sha, base: local.base, reviewedBase, policyPaths });
    };
    if (carryOn) result = { ...(await planCarry({ policy, reviewers, onHead, chain, verdictsAt, check })), delta: {} };
  } catch (e) {
    log(`carry-forward: nothing carried (${e.message})`);
    result = { carried: [], notes: [`carry-forward failed: ${e.message}`.slice(0, 300)], delta: {} };
  }
  try {
    if (!policy.delta_review || !chain) return result;
    const carriedNames = new Set(result.carried.map((x) => x.name));
    const prLines = Number.isInteger(pr.additions) && Number.isInteger(pr.deletions) ? pr.additions + pr.deletions : undefined;
    const { delta, notes } = await planDelta({
      policy,
      reviewers: reviewers.filter((n) => !carriedNames.has(n)),
      chain,
      verdictsAt,
      check: async (from, reviewedBase) =>
        lostBase(reviewedBase, from) || checkDelta(local.run, { from, head: pr.head.sha, base: local.base, reviewedBase, cfg: policy.delta_review, policyPaths, prLines }),
    });
    return { ...result, notes: [...result.notes, ...notes], delta };
  } catch (e) {
    log(`delta review: every reviewer reads the whole PR (${e.message})`);
    return { ...result, notes: [...result.notes, `delta review failed: ${e.message}`.slice(0, 300)] };
  } finally {
    local?.cleanup();
  }
}

/**
 * Posts the passes classify carried as merge-review/<name> check runs on the
 * head, as the merge-bot App. Runs in the gate job after the App token is
 * minted, where no model and no PR code runs. Before posting it re-reads the
 * evidence it can read through the API: the head has not moved, the head has
 * no verdict of its own for that reviewer (a fresh one is never shadowed),
 * and the source is still a reviewed, bound pass on this PR.
 * @returns {Promise<{posted: string[], skipped: string[], failed: string[]}>}
 */
export async function postCarried({ gh, app, policy, pr, vars = env, log = console.log }) {
  const out = { posted: [], skipped: [], failed: [] };
  let list;
  try {
    list = JSON.parse(vars.CARRIED || "[]");
  } catch {
    list = [];
  }
  if (!Array.isArray(list) || !list.length) return out;
  const head = vars.HEAD_SHA;
  const reviewers = JSON.parse(vars.REVIEWERS || "[]");
  const named = list.map((x) => String(x?.name));
  if (policy.carry_forward !== true) {
    log("carry_forward is off: nothing posted");
    out.skipped.push(...named);
    return out;
  }
  if (!isSha(head) || pr.head.sha !== head) {
    log(`head moved from ${String(head).slice(0, 7)}: nothing carried; the newer run decides`);
    out.skipped.push(...named);
    return out;
  }
  const appId = botAppId(policy);
  const onHead = await reviewVerdicts(gh, head, pr, appId);
  const runUrl = runLink(vars);
  for (const item of list) {
    const name = item?.name;
    const from = item?.from;
    const skip = (why) => {
      log(`not carrying ${name}: ${why}`);
      out.skipped.push(String(name));
    };
    if (typeof name !== "string" || !reviewers.includes(name) || !isSha(from) || from === head) {
      skip("malformed entry");
      continue;
    }
    if (onHead[name]) {
      skip(`the head already has a ${onHead[name].state} verdict`);
      continue;
    }
    const src = (await reviewVerdicts(gh, from, pr, appId))[name];
    if (!src || src.state !== "success" || src.carried_from !== undefined) {
      skip(`${from.slice(0, 7)} holds no reviewed pass`);
      continue;
    }
    const detail = typeof item.detail === "string" ? item.detail.slice(0, 500) : "";
    const body = verdictCheck({
      reviewer: name,
      pr: pr.number,
      head,
      state: "success",
      model: src.model,
      // The base the reviewed head was reviewed against; a later carry goes back to the root anyway.
      base: src.base,
      carriedFrom: from,
      description: `pass, carried from ${from.slice(0, 7)}: ${detail || "the PR's own change is identical"}. The review of ${from.slice(0, 7)}: ${src.description}`,
      detailsUrl: runUrl,
    });
    try {
      await app.post(`/repos/{repo}/check-runs`, body);
      out.posted.push(name);
      log(`posted ${body.name}: success on ${head.slice(0, 7)}, carried from ${from.slice(0, 7)}`);
    } catch (e) {
      out.failed.push(name);
      log(`posting the carried ${name} verdict failed: ${e.message}`);
    }
  }
  return out;
}

const contentsPath = (path, sha) => `/repos/{repo}/contents/${path.split("/").map(encodeURIComponent).join("/")}?ref=${sha}`;

/**
 * Full head and base contents of the SQL files classify compares in full,
 * read as data through the contents API. A failed or oversized read is
 * recorded as an error, which classify turns into owner tier.
 */
export async function fetchSqlContents(gh, pr, files) {
  const out = {};
  for (const need of sqlContentNeeds(files)) {
    try {
      const head = await gh.raw(contentsPath(need.filename, pr.head.sha), SQL_CONTENT_MAX);
      const base = need.basePath ? await gh.raw(contentsPath(need.basePath, pr.base.sha), SQL_CONTENT_MAX) : "";
      out[need.filename] = { head, base };
    } catch (e) {
      out[need.filename] = { error: e.message };
    }
  }
  // The contents API follows symlinks (and lists them as files), so the git
  // mode comes from the head's trees.
  const trees = new Map();
  for (const path of sqlModeNeeds(files)) {
    const entry = (out[path] ??= {});
    if (entry.error) continue;
    try {
      entry.mode = await treeMode(gh, pr.head.sha, path, trees);
    } catch (e) {
      entry.error = e.message;
    }
  }
  return out;
}

/** The git mode ("100644", "120000", ...) of `path` in commit `sha`. */
async function treeMode(gh, sha, path, cache) {
  return (await treeEntry(gh, sha, path, cache, "head")).mode;
}

/** The tree entry {mode, type, sha} of `path` in commit `sha`, walking one tree per directory. */
async function treeEntry(gh, sha, path, cache, side) {
  const parts = path.split("/");
  let tree = sha;
  for (let i = 0; i < parts.length; i += 1) {
    if (!cache.has(tree)) cache.set(tree, gh.get(`/repos/{repo}/git/trees/${tree}`));
    const t = await cache.get(tree);
    const at = parts.slice(0, i + 1).join("/");
    if (t?.truncated) throw new Error(`tree listing truncated above ${at}`);
    const e = (t?.tree || []).find((x) => x.path === parts[i]);
    if (!e) throw new Error(`${at} not in the ${side} tree`);
    if (i === parts.length - 1) return e;
    if (e.type !== "tree") throw new Error(`${at} is not a directory (mode ${e.mode})`);
    tree = e.sha;
  }
  throw new Error("empty path");
}

/**
 * Base blob SHAs of the renamed files classify needs to tell a plain move
 * from a changed binary (renameBlobNeeds). A failed lookup is recorded as an
 * error, which ownerLineHits counts as a diff not shown.
 */
export async function fetchRenameBlobs(gh, pr, files, policy) {
  const out = {};
  const trees = new Map();
  for (const path of renameBlobNeeds(files, policy)) {
    try {
      const e = await treeEntry(gh, pr.base.sha, path, trees, "base");
      out[path] = e.type === "blob" ? e.sha : { error: `${path} is a ${e.type} in the base tree` };
    } catch (e) {
      out[path] = { error: e.message };
    }
  }
  return out;
}

/**
 * Is merge-gate a required check on `branch`, accepted only from the merge-bot
 * App? A pin to any other source (GitHub Actions, or none) would let any
 * workflow that can write checks shadow the gate, so it does not count.
 * @param {number|null} appId  policy.bot_app_id; without one, any merge-gate requirement counts
 */
export async function gateIsRequired(gh, branch, appId) {
  const pinned = (source) => !appId || Number(source) === Number(appId);
  const rules = await gh.get(`/repos/{repo}/rules/branches/${encodeURIComponent(branch)}`).catch(() => []);
  for (const r of rules || []) {
    if (r.type !== "required_status_checks") continue;
    for (const c of r.parameters?.required_status_checks || []) if (c.context === GATE_CHECK && pinned(c.integration_id)) return true;
  }
  const b = await gh.get(`/repos/{repo}/branches/${encodeURIComponent(branch)}`).catch(() => null);
  const classic = b?.protection?.required_status_checks;
  for (const c of classic?.checks || []) if (c.context === GATE_CHECK && pinned(c.app_id)) return true;
  if (!appId && (classic?.contexts || []).includes(GATE_CHECK)) return true;
  return false;
}

/**
 * The authoritative merge-gate check run, posted by the merge-bot App on the
 * head SHA. The ruleset accepts merge-gate from the App only, so no workflow
 * can shadow it; a run that never gets here leaves the check missing, which
 * keeps the required check pending (closed).
 */
export async function postGateCheck(app, { sha, conclusion, title, summary: text, detailsUrl }) {
  return app.post(`/repos/{repo}/check-runs`, {
    name: GATE_CHECK,
    head_sha: sha,
    status: "completed",
    conclusion,
    details_url: detailsUrl,
    output: { title: redact(title).slice(0, 250), summary: redact(text).slice(0, 60000) },
  });
}

/** A verdict as the sticky comment and the merge-gate summary show it: state, description, model. */
const reviewText = (v) => (v ? `${v.state} (${v.description})${v.model ? ` [${v.model}]` : ""}` : "missing");

const runLink = (vars) => `${vars.GITHUB_SERVER_URL || "https://github.com"}/${repo}/actions/runs/${vars.GITHUB_RUN_ID}`;

/** A failing merge-gate check for a run that could not decide (crash, classify
 * failure). Best effort: without an App token or a SHA, the check stays missing. */
export async function failGateCheck({ app, sha, reason, vars }) {
  if (!app || !sha) return false;
  await postGateCheck(app, {
    sha,
    conclusion: "failure",
    title: `merge-gate failed closed — ${reason}`.slice(0, 250),
    summary: `The gate run did not complete, so this head may not merge.\n\n- head: \`${sha}\`\n- reason: ${reason}\n- run: ${runLink(vars)}`,
    detailsUrl: runLink(vars),
  });
  return true;
}

/** Direct mode: true all required checks green, false any red, null pending. */
export async function ciState(gh, sha, required) {
  // No required CI: the review is the floor (classify never makes such a PR
  // green), so there is nothing left to wait for.
  if (!required.length) return true;
  const runs = await gh.paginate(`/repos/{repo}/commits/${sha}/check-runs`, "check_runs");
  let pending = false;
  for (const name of required) {
    const latest = runs.filter((r) => r.name === name).sort((a, b) => (b.started_at || "").localeCompare(a.started_at || ""))[0];
    if (!latest || latest.status !== "completed") pending = true;
    else if (!["success", "neutral", "skipped"].includes(latest.conclusion)) return false;
  }
  return pending ? null : true;
}

async function loadContext() {
  const policy = loadPolicy(env.MERGE_POLICY_PATH || ".github/merge-policy.json");
  const gh = new GitHub(env.GH_TOKEN, repo);
  const ev = event();
  const number = await resolvePrNumber(gh, ev);
  if (!number) return { policy, gh, ev, pr: null };
  const pr = await gh.get(`/repos/{repo}/pulls/${number}`);
  return { policy, gh, ev, pr };
}

async function cmdClassify() {
  const { policy, gh, ev, pr } = await loadContext();
  if (!pr) {
    output("skip", "true");
    summary("merge-gate: no open pull request for this event.");
    return;
  }
  // A push invalidates the owner's approval: it named the previous head. A
  // failure here fails classify, and with it the gate.
  if (ev.action === "synchronize" && pr.labels.some((l) => l.name === LABELS.approve)) {
    await gh.delete(`/repos/{repo}/issues/${pr.number}/labels/${encodeURIComponent(LABELS.approve)}`);
  }
  // A new head invalidates any earlier arming. Classify does not disarm:
  // GitHub refuses disablePullRequestAutoMerge from this job's Actions token
  // (contents: read), and classify holds no App token. The merge-gate-runner
  // disarms with the App when the head has not earned arming; until then the
  // ruleset's required merge-gate check, which only the App posts per head
  // SHA, keeps a new head from merging. A retarget keeps the SHA, so it relies
  // on the runner's decision alone.
  const files = await gh.paginate(`/repos/{repo}/pulls/${pr.number}/files`);
  // Review guides whose paths this PR touches (renames on both sides). Only
  // the names go to the review job, which reads each from the base commit.
  const guides = matchGuides(policy.review_guides, files.flatMap((f) => (f.previous_filename ? [f.filename, f.previous_filename] : [f.filename])));
  const repoInfo = await gh.get(`/repos/{repo}`);
  const botLogin = policy.bot_slug ? `${policy.bot_slug}[bot]` : undefined;
  // Dependabot's and the merge bot's tiers rest on the head commit, not on
  // an editable title or body.
  const headCommit = needsHeadCommit(pr, botLogin) ? await gh.get(`/repos/{repo}/commits/${pr.head.sha}`) : undefined;
  const c = classify(policy, {
    headCommit,
    sqlContents: await fetchSqlContents(gh, pr, files),
    renameBlobs: await fetchRenameBlobs(gh, pr, files, policy),
    pr,
    files,
    repo,
    defaultBranch: repoInfo.default_branch,
    frozen: await isFrozen(gh),
    botLogin,
  });
  const cached = c.reviewers.length ? await reviewVerdicts(gh, pr.head.sha, pr, botAppId(policy)) : {};
  const fresh = c.reviewers.filter((r) => !["success", "failure"].includes(cached[r]?.state));
  // A pass from an earlier head whose change this head repeats exactly: its
  // matrix leg does not run, and the gate job posts it as the App.
  // The others may review only the change since their last verdict.
  const { carried, notes, delta } = await carryForward({ gh, pr, policy, reviewers: fresh, onHead: cached });
  const carriedNames = new Set(carried.map((x) => x.name));
  const needed = fresh
    .filter((name) => !carriedNames.has(name))
    .map((name) => ({ name, model: policy.models[name], effort: policy.effort[name] || "high", ...(delta[name] ? { delta: delta[name] } : {}) }));

  output("skip", "false");
  output("pr", String(pr.number));
  output("head_sha", pr.head.sha);
  output("base_sha", pr.base.sha);
  output("tier", c.tier);
  output("reviewers", c.reviewers);
  output("reviewers_needed", needed);
  output("carried", carried);
  output("review_guides", guides);
  output("migration", String(c.migration));
  output("reasons", c.reasons.join("; ").slice(0, 900));
  const carriedLine = carried.map((x) => `${x.name} from ${x.from.slice(0, 7)}`).join(", ");
  summary(
    `### merge-gate classify — PR #${pr.number}\n\n- tier: **${c.tier}**\n- reasons: ${c.reasons.join("; ")}\n- reviewers: ${c.reviewers.join(", ") || "none"} (fresh: ${needed.map((n) => n.name).join(", ") || "none"}; carried: ${carriedLine || "none"})${guides.length ? `\n- review guides: ${guides.join(", ")}` : ""}${notes.length ? `\n- carry-forward and follow-ups: ${notes.join("; ")}` : ""}`,
  );
}

const DISABLE = `mutation($id: ID!) { disablePullRequestAutoMerge(input: {pullRequestId: $id}) { clientMutationId } }`;
const ENABLE = `mutation($id: ID!, $method: PullRequestMergeMethod!, $oid: GitObjectID) {
  enablePullRequestAutoMerge(input: {pullRequestId: $id, mergeMethod: $method, expectedHeadOid: $oid}) { clientMutationId }
}`;

async function disarm(client, pr) {
  if (!pr.auto_merge) return false;
  await client.graphql(DISABLE, { id: pr.node_id });
  return true;
}

async function ensureLabels(gh, names) {
  const colors = { [LABELS.armed]: "0e8a16", [LABELS.owner]: "5319e7", [LABELS.changes]: "d93f0b" };
  for (const name of names) {
    await gh.post(`/repos/{repo}/labels`, { name, color: colors[name] || "ededed", description: "merge-policy" }).catch(() => {});
  }
}

async function applyLabels(gh, pr, add, remove) {
  const have = new Set(pr.labels.map((l) => l.name));
  const toAdd = add.filter((l) => !have.has(l));
  if (toAdd.length) {
    await ensureLabels(gh, toAdd);
    await gh.post(`/repos/{repo}/issues/${pr.number}/labels`, { labels: toAdd });
  }
  for (const l of remove.filter((x) => have.has(x))) {
    await gh.delete(`/repos/{repo}/issues/${pr.number}/labels/${encodeURIComponent(l)}`);
  }
}

function readReviewArtifacts(dir) {
  const out = {};
  if (!dir || !existsSync(dir)) return out;
  const walk = (d) => {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, entry.name);
      if (entry.isDirectory()) walk(p);
      else if (/^review-.+\.json$/.test(entry.name)) {
        const r = JSON.parse(readFileSync(p, "utf8"));
        out[r.reviewer] = r;
      }
    }
  };
  walk(dir);
  return out;
}

/** Findings for the sticky comment. Reviewer text is untrusted: anything
 * shaped like a credential is redacted before it is rendered. */
export function renderFindings(artifacts) {
  const blocks = [];
  for (const [name, r] of Object.entries(artifacts)) {
    const via = r.model_selector && r.model_selector !== r.model ? ` via ${r.model_selector}` : "";
    const lines = [`**${name}** (${r.model || r.model_selector || "model unknown"}${via}) — ${r.description}`];
    if (r.summary) lines.push(`> ${r.summary.replace(/\n/g, " ")}`);
    for (const f of [...(r.blocking || []), ...(r.other || [])]) {
      const where = f.line ? `${f.file}:${f.line}` : f.file;
      lines.push(`- **[${f.severity}${f.downgraded ? ", downgraded: no concrete scenario" : ""}]** \`${where}\` — ${f.title}`);
      if (f.failure_scenario) lines.push(`  - scenario: ${f.failure_scenario}`);
      if (f.fix) lines.push(`  - fix: ${f.fix}`);
    }
    if (r.error) lines.push(`- error: ${r.error}`);
    blocks.push(lines.map(redact).join("\n"));
  }
  return redact(blocks.join("\n\n"));
}

/**
 * Owner tier: did the owner approve this head with the merge:approve label?
 * The run of his labeling records it first (an App check run on the head he
 * labeled); every run then needs that record on the current head.
 * @param {object|null} app  the merge-bot App client (null: nothing can be recorded)
 */
export async function ownerApprovalFor(gh, pr, policy, ev, app) {
  if (!approvalRunAllows(ev, pr.head.sha)) return false;
  const labels = pr.labels.map((l) => l.name);
  if (!labels.includes(LABELS.approve)) return false;
  const appId = botAppId(policy);
  const runs = [];
  if (app && approvalToRecord(ev, pr, policy.owner_login)) {
    const posted = await app
      .post(`/repos/{repo}/check-runs`, approvalCheck({ pr: pr.number, head: pr.head.sha, approver: policy.owner_login }))
      .catch((e) => console.log(`approval record not posted: ${e.message}`));
    if (posted) runs.push(posted);
  }
  const listed = await gh.paginate(`/repos/{repo}/commits/${pr.head.sha}/check-runs?filter=all&app_id=${appId}&check_name=${APPROVAL_CHECK}`, "check_runs");
  runs.push(...listed);
  const record = approvalRecord(runs, { sha: pr.head.sha, prNumber: pr.number, appId, ownerLogin: policy.owner_login });
  if (!record) return false;
  const events = await gh.paginate(`/repos/{repo}/issues/${pr.number}/events`);
  return ownerApproved(events, { ownerLogin: policy.owner_login, labels, record });
}

async function upsertSticky(gh, pr, body) {
  const comments = await gh.paginate(`/repos/{repo}/issues/${pr.number}/comments`);
  const mine = comments.find((c) => c.user?.login === ACTIONS_BOT && c.body?.startsWith(STICKY));
  if (mine) await gh.patch(`/repos/{repo}/issues/comments/${mine.id}`, { body });
  else await gh.post(`/repos/{repo}/issues/${pr.number}/comments`, { body });
  return mine?.body || "";
}

/**
 * One mention of the owner per head: a new comment (not an edit), so it
 * reaches GitHub email and Mobile. Posted as the merge-bot App when there is
 * one. Deduped on the gate's own earlier comments for this head only.
 */
export async function notifyOwnerOnce(gh, app, pr, body, botLogin, log = console.log) {
  try {
    const comments = await gh.paginate(`/repos/{repo}/issues/${pr.number}/comments`);
    if (ownerNotified(comments, pr.head.sha, [ACTIONS_BOT, botLogin].filter(Boolean))) return false;
    const path = `/repos/{repo}/issues/${pr.number}/comments`;
    if (app) {
      try {
        await app.post(path, { body });
        return true;
      } catch (e) {
        log(`owner mention as the App failed (${e.message}); posting it with the Actions token`);
      }
    }
    await gh.post(path, { body });
    return true;
  } catch (e) {
    // The decision and its check are already posted; a lost mention changes neither.
    log(`owner mention failed: ${e.message}`);
    return false;
  }
}

/**
 * Asks the owner to review a ready PR someone else opened (ownerReviewNeeded),
 * once per PR, as the merge-bot App when there is one. Best effort: a failure
 * here never changes the gate's decision.
 */
export async function requestOwnerReview(gh, app, pr, policy, log = console.log) {
  try {
    let need = ownerReviewNeeded(pr, policy);
    if (need === "needs-events") need = ownerReviewNeeded(pr, policy, await gh.paginate(`/repos/{repo}/issues/${pr.number}/events`));
    if (!need) return false;
    await (app || gh).post(`/repos/{repo}/pulls/${pr.number}/requested_reviewers`, { reviewers: [policy.owner_login] });
    log(`requested a review from @${policy.owner_login}`);
    return true;
  } catch (e) {
    log(`owner review request failed: ${e.message}`);
    return false;
  }
}

async function cmdDecide() {
  const { policy, gh, ev, pr } = await loadContext();
  if (!pr) return;
  let d;
  try {
    d = await decideAndApply({ policy, gh, pr, env, event: ev });
  } catch (e) {
    // The decision crashed: say so on the head, so an earlier success on the
    // same SHA cannot stand for this run.
    const app = env.MERGE_TOKEN ? new GitHub(env.MERGE_TOKEN, repo) : null;
    await failGateCheck({ app, sha: env.HEAD_SHA || pr.head.sha, reason: `decide crashed: ${e.message}`.slice(0, 200), vars: env }).catch((x) =>
      console.log(`posting the failing merge-gate check failed: ${x.message}`),
    );
    throw e;
  }
  if (d.conclusion === "failure") process.exitCode = 1;
}

/** Classification did not complete: post a failing merge-gate check where
 * possible, and fail the job either way. */
async function cmdFailCheck() {
  const reason = env.REASON || "classification did not complete";
  console.log(`::error::${reason}; refusing to pass`);
  const app = env.MERGE_TOKEN ? new GitHub(env.MERGE_TOKEN, repo) : null;
  const posted = await failGateCheck({ app, sha: env.HEAD_SHA, reason, vars: env }).catch((e) => {
    console.log(`posting the failing merge-gate check failed: ${e.message}`);
    return false;
  });
  if (!posted) console.log("no merge-bot token or head SHA: the merge-gate check stays missing (pending), which also blocks the merge");
  process.exitCode = 1;
}

/** Posts classify's carried passes as the App. A failure exits non-zero; the
 * step continues on error, and decide then finds the verdict missing. */
async function cmdCarryPost() {
  const policy = loadPolicy(env.MERGE_POLICY_PATH || ".github/merge-policy.json");
  if (!env.MERGE_TOKEN) {
    console.log("::warning::no merge-bot App token: carried verdicts are not posted, so the gate counts them as missing");
    return;
  }
  const gh = new GitHub(env.GH_TOKEN, repo);
  const pr = await gh.get(`/repos/{repo}/pulls/${Number(env.PR_NUMBER)}`);
  const r = await postCarried({ gh, app: new GitHub(env.MERGE_TOKEN, repo), policy, pr });
  if (r.failed.length) process.exitCode = 1;
}

/**
 * Decide for one PR and perform the side effects: arm/disarm/merge, labels,
 * sticky comment, owner mention. Everything external comes in through `gh`,
 * `vars` and `deps`, so tests drive it with fakes and no network.
 * @param {object} a
 * @param {object} a.policy  merged policy
 * @param {object} a.gh      GitHub client for the Actions token
 * @param {object} a.pr      the PR (REST shape)
 * @param {object} a.vars    HEAD_SHA, TIER, REASONS, REVIEWERS, MERGE_TOKEN, MERGE_BOT_LOGIN, REVIEW_DIR, GITHUB_SERVER_URL, GITHUB_RUN_ID
 * @param {object} [a.event] the workflow event payload (owner approval is bound to it)
 * @param {object} [a.deps]  { makeMerger(token), reviewVerdicts(gh, sha, pr, appId), log(md) }
 */
export async function decideAndApply({ policy, gh, pr, env: vars, event = {}, deps = {} }) {
  const makeMerger = deps.makeMerger || ((t) => new GitHub(t, repo));
  const verdicts = deps.reviewVerdicts || reviewVerdicts;
  const log = deps.log || summary;
  const mergeToken = vars.MERGE_TOKEN || "";
  // The App client posts the merge-gate check on every path and performs the
  // merge. Without an App token neither can happen: that mode already fails.
  const app = mergeToken ? makeMerger(mergeToken) : null;
  const classifiedSha = vars.HEAD_SHA;
  if (classifiedSha && pr.head.sha !== classifiedSha) {
    log(`merge-gate: head moved ${classifiedSha.slice(0, 7)} → ${pr.head.sha.slice(0, 7)}; the newer run decides.`);
    // Never report success for a head this run did not evaluate.
    await failGateCheck({ app, sha: classifiedSha, reason: `head moved to ${pr.head.sha.slice(0, 7)}; the newer run decides`, vars });
    return { conclusion: "failure", action: "none", add: [], remove: [], headline: "head moved", notifyOwner: false };
  }
  const c = {
    tier: vars.TIER,
    reasons: (vars.REASONS || "").split("; ").filter(Boolean),
    reviewers: JSON.parse(vars.REVIEWERS || "[]"),
  };
  const reviews = c.reviewers.length ? await verdicts(gh, pr.head.sha, pr, botAppId(policy)) : {};
  const approved = c.tier === "owner" ? await ownerApprovalFor(gh, pr, policy, event, app) : false;
  const d = decide(c, {
    ownerApproved: approved,
    reviews,
    mode: policy.mode,
    gateRequired: policy.mode === "native" ? await gateIsRequired(gh, pr.base.ref, botAppId(policy)) : undefined,
    ciGreen: policy.mode === "direct" ? await ciState(gh, pr.head.sha, policy.required_checks) : undefined,
    mergeBot: Boolean(mergeToken),
  });

  let actionNote = "";
  // Only the App can disarm: GitHub refuses disablePullRequestAutoMerge from
  // the job's Actions token (contents: read; "Resource not accessible by
  // integration"). Without an App token the attempt fails and no merge-gate
  // check is posted, so a leftover arming still cannot fire.
  const disarmer = app || gh;
  try {
    const ownerArmed = keepOwnerArming(c.tier, pr, policy.owner_login);
    if (d.action === "disarm") {
      if (ownerArmed) actionNote = "auto-merge enabled by the owner left as is";
      else if (await disarm(disarmer, pr)) actionNote = "auto-merge disarmed";
    } else if (d.action === "arm" && ownerArmed) {
      actionNote = "auto-merge enabled by the owner left as is";
    } else if (d.action === "arm") {
      // decide() never arms without a merge-bot token, so `app` exists here.
      const merger = app;
      const botArmed = pr.auto_merge && pr.auto_merge.enabled_by?.login === vars.MERGE_BOT_LOGIN;
      if (!botArmed) {
        // Re-arm under the merge bot so the eventual merge triggers push workflows.
        if (pr.auto_merge) await disarm(merger, pr);
        await merger.graphql(ENABLE, { id: pr.node_id, method: policy.merge_method.toUpperCase(), oid: pr.head.sha });
      }
      actionNote = `auto-merge armed (${policy.merge_method}) at ${pr.head.sha.slice(0, 7)}`;
    } else if (d.action === "merge") {
      await app.put(`/repos/{repo}/pulls/${pr.number}/merge`, { sha: pr.head.sha, merge_method: policy.merge_method });
      actionNote = `merged ${pr.head.sha.slice(0, 7)} (${policy.merge_method})`;
    }
  } catch (e) {
    d.conclusion = "failure";
    d.add = d.add.filter((l) => l !== LABELS.armed);
    d.remove = [...new Set([...d.remove, LABELS.armed])];
    d.headline = `${d.action} failed — ${e.message}`;
  }

  // The authoritative merge-gate check, with this run's final conclusion.
  if (app) {
    const reviewLine = c.reviewers.map((r) => `${r}: ${reviewText(reviews[r])}`).join(" · ");
    try {
      await postGateCheck(app, {
        sha: pr.head.sha,
        conclusion: d.conclusion,
        title: `${c.tier} · ${d.headline}`,
        summary: [
          `- head: \`${pr.head.sha}\``,
          `- tier: **${c.tier}**${c.reasons.length ? ` (${c.reasons.join("; ")})` : ""}`,
          `- decision: ${d.headline}`,
          reviewLine ? `- reviews: ${reviewLine}` : "",
          `- run: ${runLink(vars)}`,
        ]
          .filter(Boolean)
          .join("\n"),
        detailsUrl: runLink(vars),
      });
    } catch (e) {
      d.conclusion = "failure";
      d.headline = `${d.headline} — merge-gate check not posted: ${e.message}`;
    }
  } else {
    log("merge-gate: no merge-bot App token, so the merge-gate check cannot be posted; the required check stays pending.");
  }

  await applyLabels(gh, pr, d.add, d.remove);

  const icon = d.conclusion === "failure" ? "🔴" : d.action === "arm" || d.action === "merge" ? "🟢" : c.tier === "owner" ? "🟣" : "⚪";
  const artifacts = readReviewArtifacts(vars.REVIEW_DIR);
  const findings = renderFindings(artifacts);
  const header = [
    STICKY,
    `### ${icon} merge-policy · tier \`${c.tier}\` · ${d.headline}`,
    "",
    `Head \`${pr.head.sha.slice(0, 7)}\`${actionNote ? ` · ${actionNote}` : ""} · [run](${vars.GITHUB_SERVER_URL}/${repo}/actions/runs/${vars.GITHUB_RUN_ID})`,
    c.reasons.length ? `Why this tier: ${c.reasons.join("; ")}` : "",
    c.reviewers.length
      ? `Reviews: ${c.reviewers.map((r) => `${r} ${reviewText(reviews[r])}`).join(" · ")}`
      : "",
  ].filter(Boolean);
  const findingsStart = `<!-- findings sha=${pr.head.sha} -->`;
  let body = header.join("\n");
  if (findings) body += `\n\n${findingsStart}\n<details${d.conclusion === "failure" ? " open" : ""}><summary>Findings</summary>\n\n${findings}\n\n</details>`;
  body = redact(body);
  const previous = await upsertSticky(gh, pr, body);
  if (!findings) {
    // Reviews were reused from an earlier run on this head, or carried from
    // the head they were made on: keep that head's findings.
    const from = new Set([pr.head.sha, ...Object.values(reviews).map((v) => v?.carried_from).filter(Boolean)]);
    const at = [...from].map((sha) => previous.indexOf(`<!-- findings sha=${sha} -->`)).filter((i) => i >= 0);
    if (at.length) await upsertSticky(gh, pr, `${body}\n\n${previous.slice(Math.min(...at))}`);
  }

  if (d.notifyOwner && policy.owner_login) {
    const body = ownerNotice({
      sha: pr.head.sha,
      owner: policy.owner_login,
      tier: c.tier,
      reasons: c.reasons,
      headline: d.headline,
      approvalNeeded: Boolean(d.approvalNeeded),
      reviews: c.reviewers.map((r) => `${r} ${reviewText(reviews[r])}`).join(" · "),
    });
    // Dedupe on the App's login from the policy, not on this run's minted token:
    // a run whose minting failed must still see the App's earlier notice.
    await notifyOwnerOnce(gh, app, pr, redact(body), policy.bot_slug ? `${policy.bot_slug}[bot]` : undefined);
  }
  await requestOwnerReview(gh, app, pr, policy, (m) => console.log(m));

  log(`### merge-gate decide — PR #${pr.number}\n\n- tier: **${c.tier}**\n- decision: **${d.headline}**\n- action: ${d.action}${actionNote ? ` (${actionNote})` : ""}`);
  return d;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const cmd = process.argv[2];
  const run = { classify: cmdClassify, decide: cmdDecide, "fail-check": cmdFailCheck, "carry-post": cmdCarryPost }[cmd];
  if (!run) {
    console.error("usage: run-gate.mjs classify|decide|fail-check|carry-post");
    process.exit(2);
  }
  run().catch((e) => {
    console.error(e.stack || e.message);
    process.exit(1);
  });
}
