// verdict — the reviewer's structured output contract and how it is judged.
//
// Only findings decide: a review fails iff it reports at least one blocker or
// major finding that names a concrete failure scenario. A free-text "fail"
// with no such finding does not block, and a "pass" with one does.

export const REVIEW_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "findings"],
  properties: {
    summary: { type: "string", description: "One or two sentences: what the change does and the overall risk." },
    findings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["severity", "file", "title", "failure_scenario"],
        properties: {
          severity: { type: "string", enum: ["blocker", "major", "minor", "nit"] },
          file: { type: "string" },
          line: { type: "integer" },
          title: { type: "string" },
          failure_scenario: {
            type: "string",
            description: "Concrete inputs or state -> wrong output, crash, data loss or exposure. Empty if speculative.",
          },
          fix: { type: "string" },
        },
      },
    },
  },
};

/**
 * REVIEW_SCHEMA in the form OpenAI's strict structured outputs accept: every
 * property listed in `required`, an optional one typed as a union with null.
 * judge() reads null like an absent field.
 */
export function strictSchema(schema = REVIEW_SCHEMA) {
  if (!schema || typeof schema !== "object" || Array.isArray(schema)) return schema;
  const out = { ...schema };
  if (schema.properties) {
    const required = new Set(schema.required || []);
    out.properties = {};
    for (const [k, v] of Object.entries(schema.properties)) {
      const inner = strictSchema(v);
      out.properties[k] = required.has(k) ? inner : { ...inner, type: [].concat(inner.type, "null") };
    }
    out.required = Object.keys(schema.properties);
    out.additionalProperties = false;
  }
  if (schema.items) out.items = strictSchema(schema.items);
  return out;
}

const BLOCKING = new Set(["blocker", "major"]);
const MIN_SCENARIO = 20;

/**
 * @param {unknown} raw  the reviewer's structured_output (object or JSON string)
 * @returns {{ok: boolean, state: "success"|"failure"|"error", blocking: object[], other: object[], summary: string, error?: string}}
 */
export function judge(raw) {
  let out = raw;
  if (typeof out === "string") {
    try {
      out = JSON.parse(out);
    } catch {
      return errorResult("reviewer output is not valid JSON");
    }
  }
  if (!out || typeof out !== "object" || !Array.isArray(out.findings) || typeof out.summary !== "string") {
    return errorResult("reviewer output does not match the schema");
  }
  const blocking = [];
  const other = [];
  for (const f of out.findings) {
    if (!f || typeof f !== "object") continue;
    const concrete = typeof f.failure_scenario === "string" && f.failure_scenario.trim().length >= MIN_SCENARIO;
    if (BLOCKING.has(f.severity) && concrete) blocking.push(f);
    else other.push(BLOCKING.has(f.severity) ? { ...f, severity: "minor", downgraded: true } : f);
  }
  return {
    ok: blocking.length === 0,
    state: blocking.length === 0 ? "success" : "failure",
    blocking,
    other,
    summary: out.summary,
  };
}

function errorResult(error) {
  return { ok: false, state: "error", blocking: [], other: [], summary: "", error };
}

/** Commit-status description, <= 140 chars. */
export function describe(result) {
  if (result.state === "error") return `error: ${result.error}`.slice(0, 140);
  const minor = result.other.length;
  const head = result.ok ? "pass" : "fail";
  return `${head} · ${result.blocking.length} blocking · ${minor} non-blocking`.slice(0, 140);
}

// Credential shapes that must never reach a PR comment, a status or an
// artifact: Anthropic keys and OAuth tokens, OpenAI keys (sk-…, sk-proj-…,
// sk-svcacct-…, sk-admin-…), GitHub tokens of every kind.
const SECRET_PATTERNS = [
  /sk-ant-[A-Za-z0-9_-]+/g,
  /\bsk-[A-Za-z0-9_-]{20,}/g,
  /gh[pousr]_[A-Za-z0-9]{20,}/g,
  /github_pat_[A-Za-z0-9_]{20,}/g,
];

/** Replaces anything shaped like a credential with "[redacted]". */
export function redact(text) {
  if (typeof text !== "string") return text;
  return SECRET_PATTERNS.reduce((t, re) => t.replace(re, "[redacted]"), text);
}

// Review verdicts are check runs `merge-review/<name>` that the merge-bot App
// posts on the head SHA from the review job, which runs in the merge-bot
// environment (default branch only). Nothing else holds the App's key there,
// so nothing else can create a check run with the App's id: commit statuses
// and workflow artifacts, which any workflow run can produce, are not evidence.
export const REVIEW_CHECK_PREFIX = "merge-review/";
const STATES = ["success", "failure", "error"];
const MODEL_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$/;

/** A model id fit to show and to bind, or undefined. */
export const modelId = (m) => (typeof m === "string" && MODEL_ID.test(m) ? m : undefined);

const SHA_RE = /^[0-9a-f]{40}$/;

/** Separates a verdict's one-line description from its findings in the check run summary. */
export const FINDINGS_MARK = "<!-- merge-review:findings -->";
/** Characters of findings a verdict carries (and a follow-up review reads). */
export const FINDINGS_MAX = 12000;

/**
 * A review's findings as the verdict's summary keeps them: every blocking
 * finding with its scenario, then the others by title. Reviewer text is
 * untrusted: `<` and `>` are escaped so none of it can forge FINDINGS_MARK or
 * any other markup, and the whole is cut at FINDINGS_MAX.
 * @param {{blocking?: object[], other?: object[]}} result  judge()'s result
 */
export function findingsMarkdown(result, max = FINDINGS_MAX) {
  const esc = (v) => String(v ?? "").replace(/[<>]/g, (c) => (c === "<" ? "&lt;" : "&gt;")).replace(/\s+/g, " ").trim();
  const where = (f) => `${esc(f.file)}${Number.isInteger(f.line) ? `:${f.line}` : ""}`;
  const lines = [];
  for (const f of result?.blocking || []) lines.push(`- **${esc(f.severity)}** ${where(f)}: ${esc(f.title)}. Failure: ${esc(f.failure_scenario)}`);
  for (const f of result?.other || []) lines.push(`- ${esc(f.severity)} ${where(f)}: ${esc(f.title)}`);
  const text = lines.join("\n");
  return text.length > max ? `${text.slice(0, max - 13)}\n[truncated]` : text;
}

/**
 * The check run (POST /repos/{repo}/check-runs body) carrying one verdict.
 * `model` is the id the reviewer actually ran (a selector resolved at review time).
 * `base` is the base commit the reviewer diffed against (`base...head`): a
 * carry (src/carry.mjs) is sound only while the PR's merge-base with the base
 * is still the one the reviewer saw, so a verdict without it never carries.
 * `carriedFrom` is the reviewed head a pass was carried from (src/carry.mjs):
 * only a `success` carries, so any other state drops it.
 * `deltaFrom`/`deltaDepth` mark a follow-up review (src/delta.mjs): the
 * reviewer read the change since its verdict on `deltaFrom`, the n-th such
 * review in a row. Only a reviewed pass or failure records them.
 * `findings` (findingsMarkdown) follow the description in the summary, after
 * FINDINGS_MARK, so the next follow-up review can check what this one found.
 * `cost` (USD) joins the description, so every verdict shows its spend.
 * @param {{reviewer: string, pr: number, head: string, state: string, model?: string, base?: string, description?: string, detailsUrl?: string, carriedFrom?: string, deltaFrom?: string, deltaDepth?: number, findings?: string, cost?: number}} v
 */
export function verdictCheck({ reviewer, pr, head, state, model, base, description, detailsUrl, carriedFrom, deltaFrom, deltaDepth, findings, cost }) {
  const s = STATES.includes(state) ? state : "error";
  const m = modelId(model);
  const b = SHA_RE.test(base || "") ? base : undefined;
  const from = s === "success" && SHA_RE.test(carriedFrom || "") && carriedFrom !== head ? carriedFrom : undefined;
  const delta = s !== "error" && !from && SHA_RE.test(deltaFrom || "") && deltaFrom !== head && Number.isInteger(deltaDepth) && deltaDepth >= 1 ? { delta_from: deltaFrom, delta_depth: deltaDepth } : {};
  const binding = { pr, head, state: s, reviewer, ...(m ? { model: m } : {}), ...(b ? { base: b } : {}), ...(from ? { carried_from: from } : {}), ...delta };
  const spend = Number.isFinite(cost) && cost > 0 ? ` · $${cost.toFixed(2)}` : "";
  const found = s !== "error" && typeof findings === "string" && findings.trim() ? `\n\n${FINDINGS_MARK}\n${findings}` : "";
  const body = {
    name: `${REVIEW_CHECK_PREFIX}${reviewer}`,
    head_sha: head,
    status: "completed",
    conclusion: s === "success" ? "success" : "failure",
    output: {
      title: `${reviewer} review: ${s}${m ? ` (${m})` : ""}${from ? ` · carried from ${from.slice(0, 7)}` : ""}${delta.delta_from ? ` · follow-up of ${delta.delta_from.slice(0, 7)}` : ""}`,
      summary: redact(`${description || s}${spend}${found}`).slice(0, 60000),
      text: JSON.stringify(binding),
    },
  };
  if (detailsUrl) body.details_url = detailsUrl;
  return body;
}

/**
 * How many follow-up reviews in a row this verdict ends: 0 for a full review.
 * A malformed delta binding counts as Infinity, so the next review is full.
 */
function deltaDepthOf(b, sha) {
  if (b.delta_from === undefined && b.delta_depth === undefined) return 0;
  return SHA_RE.test(b.delta_from || "") && b.delta_from !== sha && Number.isInteger(b.delta_depth) && b.delta_depth >= 1 ? b.delta_depth : Infinity;
}

const bindingOf = (run) => {
  try {
    const b = JSON.parse(run.output?.text || "");
    return b && typeof b === "object" ? b : null;
  } catch {
    return null;
  }
};

/**
 * Newest verdict per reviewer among the App's own merge-review/* check runs
 * for this PR and head. A run from another App, on another SHA, for another
 * PR, or whose recorded head, state or conclusion disagree is ignored, i.e.
 * the reviewer counts as missing and the gate fails closed.
 * A carried verdict (src/carry.mjs) is bound by exactly these rules on the
 * head it was carried to; its `carried_from` must be another commit and its
 * state a success, or the run is ignored. Only the App can post one, so a
 * `carried_from` in anyone else's check run counts for nothing.
 * `base` (the commit the reviewer diffed against) is returned only when it is
 * a commit id; a verdict without one still counts, but never carries.
 * @param {object[]} runs  GET /repos/{repo}/commits/{sha}/check-runs check_runs
 * @param {{sha: string, prNumber: number, appId: number, onIgnore?: (run: object, why: string) => void}} o
 * @returns {Record<string, {state: string, description: string, url?: string, model?: string, base?: string, carried_from?: string}>}
 */
export function boundVerdicts(runs, { sha, prNumber, appId, onIgnore = () => {} }) {
  const newest = {};
  for (const run of runs || []) {
    if (typeof run?.name !== "string" || !run.name.startsWith(REVIEW_CHECK_PREFIX)) continue;
    const reviewer = run.name.slice(REVIEW_CHECK_PREFIX.length);
    const b = bindingOf(run);
    const why =
      !appId || Number(run.app?.id) !== Number(appId)
        ? `created by app ${run.app?.id ?? "?"}, not the merge bot`
        : run.head_sha !== sha
          ? "on another commit"
          : run.status !== "completed"
            ? "not completed"
            : !b
              ? "no binding in its output"
              : b.pr !== prNumber
                ? `for PR #${b.pr}`
                : b.head !== sha || b.reviewer !== reviewer
                  ? "binding names another head or reviewer"
                  : !STATES.includes(b.state) || (b.state === "success") !== (run.conclusion === "success")
                    ? "state and conclusion disagree"
                    : b.carried_from !== undefined && (b.state !== "success" || !SHA_RE.test(b.carried_from) || b.carried_from === sha)
                      ? "malformed carried_from"
                      : null;
    if (why) {
      onIgnore(run, why);
      continue;
    }
    const at = `${run.completed_at || run.started_at || ""}`;
    const cur = newest[reviewer];
    if (!cur || at > cur.at || (at === cur.at && Number(run.id) > Number(cur.id))) {
      newest[reviewer] = { at, id: run.id, run, state: b.state, model: modelId(b.model), base: SHA_RE.test(b.base || "") ? b.base : undefined, carried_from: b.carried_from, depth: deltaDepthOf(b, sha) };
    }
  }
  return Object.fromEntries(
    Object.entries(newest).map(([name, { run, state, model, base, carried_from, depth }]) => {
      const summary = String(run.output?.summary || "");
      const cut = summary.indexOf(FINDINGS_MARK);
      return [
        name,
        {
          state,
          description: cut < 0 ? summary : summary.slice(0, cut).trimEnd(),
          url: run.details_url || run.html_url,
          // Only what a follow-up review needs: its findings, and how deep a follow-up this was.
          ...(cut < 0 ? {} : { findings: summary.slice(cut + FINDINGS_MARK.length).trim().slice(0, FINDINGS_MAX) }),
          ...(depth ? { delta_depth: depth } : {}),
          ...(model ? { model } : {}),
          ...(base ? { base } : {}),
          ...(carried_from !== undefined ? { carried_from } : {}),
        },
      ];
    }),
  );
}
