// models — reviewer model selectors ("latest:<family>") resolved at review time.
//
// A policy names a family, not an id, so every repo reviews with the newest
// generally available model of that family without an install PR per release.
// Resolution reads the provider's models list with the review's own model
// credential; when that fails, or finds nothing at or above the family's
// pinned floor, the floor is used. Pure parsing and picking are separate from
// the two list calls so tests drive them with fixtures.

export const SELECTOR = /^latest:([a-z][a-z0-9-]*)$/;

/**
 * The families a selector can name. `floor` is the pinned fallback and the
 * oldest model the resolver will ever pick; `pattern` matches the family's
 * plain ids (a mini/nano/preview/other suffix never matches) and yields its
 * version and, for a dated snapshot, the date.
 */
export const FAMILIES = {
  opus: { provider: "anthropic", floor: "claude-opus-5-5", pattern: /^claude-opus-(\d+)(?:-(\d{1,2}))?(?:-(\d{8}))?$/ },
  fable: { provider: "anthropic", floor: "claude-fable-5-1", pattern: /^claude-fable-(\d+)(?:-(\d{1,2}))?(?:-(\d{8}))?$/ },
  sol: { provider: "openai", floor: "gpt-6.1-sol", pattern: /^gpt-(\d+)(?:\.(\d+))?-sol(?:-(\d{4}-\d{2}-\d{2}))?$/ },
};

/** "latest:opus" -> "opus"; anything else (a pinned id) -> null. */
export function selectorFamily(model) {
  const m = SELECTOR.exec(String(model || ""));
  return m ? m[1] : null;
}

/** Which API serves `model` (a selector or an id): "anthropic" | "openai" | null. */
export function providerOf(model) {
  const family = selectorFamily(model);
  if (family) return FAMILIES[family]?.provider ?? null;
  if (/^claude-/.test(model || "")) return "anthropic";
  if (/^(gpt-|o\d)/.test(model || "")) return "openai";
  return null;
}

/** {major, minor, dated} for an id of `family`, or null when it is not one of the family's plain ids. */
export function parseVersion(family, id) {
  const m = FAMILIES[family]?.pattern.exec(String(id || ""));
  if (!m) return null;
  return { major: Number(m[1]), minor: m[2] === undefined ? 0 : Number(m[2]), dated: m[3] || "" };
}

const cmp = (a, b) => a.major - b.major || a.minor - b.minor;

/**
 * The newest generally available model of `family` among `models`
 * ({id, created?, shutdown_date?} or bare ids). Undated ids win; a dated
 * snapshot counts only when the family has no undated id. A model whose
 * shutdown date has passed is skipped. Never older than the family's floor.
 * @param {string} family
 * @param {Array<string|{id: string, created?: number, created_at?: string, shutdown_date?: string|null}>} models
 * @param {Date} [now]
 * @returns {string|null} null when the listing holds nothing of the family
 */
export function pickLatest(family, models, now = new Date()) {
  const spec = FAMILIES[family];
  if (!spec) throw new Error(`unknown model family "${family}"`);
  const rows = [];
  for (const m of models || []) {
    const id = typeof m === "string" ? m : m?.id;
    const v = parseVersion(family, id);
    if (!v) continue;
    const shutdown = typeof m === "object" && m?.shutdown_date ? Date.parse(m.shutdown_date) : NaN;
    if (Number.isFinite(shutdown) && shutdown <= now.getTime()) continue;
    const created = typeof m === "object" ? Number(m?.created) || Date.parse(m?.created_at || "") || 0 : 0;
    rows.push({ id, v, created });
  }
  const undated = rows.filter((r) => !r.v.dated);
  const pool = undated.length ? undated : rows;
  if (!pool.length) return null;
  pool.sort((a, b) => cmp(b.v, a.v) || b.v.dated.localeCompare(a.v.dated) || b.created - a.created || a.id.localeCompare(b.id));
  const best = pool[0];
  const floor = parseVersion(family, spec.floor);
  return cmp(best.v, floor) < 0 ? spec.floor : best.id;
}

/**
 * Resolves a policy's model value. A pinned id is returned as is; a selector
 * is resolved through `list` (the provider's models list), falling back to the
 * family's floor when the list fails or holds nothing of the family.
 * @param {string} model  "latest:<family>" or a model id
 * @param {{list: (provider: string) => Promise<Array>, now?: Date}} io
 * @returns {Promise<{model: string, selector: string, source: "pinned"|"latest"|"floor", floor?: string, note?: string}>}
 */
export async function resolveModel(model, { list, now } = {}) {
  const family = selectorFamily(model);
  if (!family) {
    if (!model) throw new Error("no model configured for this reviewer");
    return { model, selector: model, source: "pinned" };
  }
  const spec = FAMILIES[family];
  if (!spec) throw new Error(`unknown model family in "${model}" (known: ${Object.keys(FAMILIES).join(", ")})`);
  try {
    const picked = pickLatest(family, await list(spec.provider), now);
    if (picked) return { model: picked, selector: model, source: "latest", floor: spec.floor };
    return { model: spec.floor, selector: model, source: "floor", floor: spec.floor, note: `no ${family} model in the ${spec.provider} models list` };
  } catch (e) {
    return { model: spec.floor, selector: model, source: "floor", floor: spec.floor, note: `models list failed: ${String(e.message).slice(0, 200)}` };
  }
}

// I/O: the providers' models lists. Each call carries the review's own model
// credential and nothing else; it runs in the review process, never in the model.

const TIMEOUT_MS = 15_000;

async function getJson(url, headers, fetchImpl) {
  const res = await fetchImpl(url, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!res.ok) {
    await res.body?.cancel?.();
    throw new Error(`GET ${new URL(url).pathname} -> ${res.status}`);
  }
  return res.json();
}

/**
 * Anthropic GET /v1/models, every page. An API key goes in x-api-key; a Claude
 * subscription token (CLAUDE_CODE_OAUTH_TOKEN) goes in Authorization with the
 * OAuth beta header.
 * @param {{ANTHROPIC_API_KEY?: string, CLAUDE_CODE_OAUTH_TOKEN?: string}} cred
 */
export async function listAnthropicModels(cred, fetchImpl = fetch) {
  const headers = { "anthropic-version": "2023-06-01" };
  if (cred?.ANTHROPIC_API_KEY) headers["x-api-key"] = cred.ANTHROPIC_API_KEY;
  else if (cred?.CLAUDE_CODE_OAUTH_TOKEN) {
    headers.authorization = `Bearer ${cred.CLAUDE_CODE_OAUTH_TOKEN}`;
    headers["anthropic-beta"] = "oauth-2025-04-20";
  } else throw new Error("no Anthropic credential");
  const out = [];
  let after = "";
  for (let page = 0; page < 10; page += 1) {
    const body = await getJson(`https://api.anthropic.com/v1/models?limit=1000${after ? `&after_id=${encodeURIComponent(after)}` : ""}`, headers, fetchImpl);
    out.push(...(body?.data || []));
    if (!body?.has_more || !body.last_id) return out;
    after = body.last_id;
  }
  return out;
}

/** OpenAI GET /v1/models. */
export async function listOpenAIModels(apiKey, fetchImpl = fetch) {
  if (!apiKey) throw new Error("no OpenAI credential");
  const body = await getJson("https://api.openai.com/v1/models", { authorization: `Bearer ${apiKey}` }, fetchImpl);
  return body?.data || [];
}
