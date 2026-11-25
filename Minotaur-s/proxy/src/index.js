import { ALLOWED_DOMAINS, FACT_CHECK_DOMAINS, WIKIPEDIA_HOST } from "./domains.js";

export const RESERVE_SQL = `
INSERT INTO search_budget(period, production, evaluation, minute, burst)
VALUES (?1, ?2, ?3, ?4, 1)
ON CONFLICT(period) DO UPDATE SET
 production = production + excluded.production,
 evaluation = evaluation + excluded.evaluation,
 burst = CASE WHEN minute = excluded.minute THEN burst + 1 ELSE 1 END,
 minute = excluded.minute
WHERE production + excluded.production <= 800
 AND evaluation + excluded.evaluation <= 200
 AND production + evaluation + 1 <= 1000
 AND (minute <> excluded.minute OR burst < 30)
RETURNING production, evaluation`;

function json(status, code, message, headers = {}) {
  return new Response(JSON.stringify({ detail: { code, error: message } }), {
    status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "X-Search-Error": code, ...headers },
  });
}

async function readJSON(request) {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) throw new Error("content_type");
  if (Number(request.headers.get("content-length")) > 8192) throw new Error("body_too_large");
  const reader = request.body?.getReader();
  if (!reader) throw new Error("malformed_body");
  const chunks = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) { await reader.cancel(); throw new Error("body_too_large"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

async function matchesSecret(supplied, expected) {
  if (!supplied || !expected) return false;
  const encode = value => new TextEncoder().encode(value);
  const [a, b] = await Promise.all([crypto.subtle.digest("SHA-256", encode(supplied)), crypto.subtle.digest("SHA-256", encode(expected))]);
  const x = new Uint8Array(a), y = new Uint8Array(b);
  let difference = 0;
  for (let i = 0; i < x.length; i++) difference |= x[i] ^ y[i];
  return difference === 0;
}

/** Shared body/query/credential validation for every POST route. Returns a Response on rejection. */
async function readQuery(request, env) {
  let input;
  try { input = await readJSON(request); }
  catch (error) { return json(error.message === "body_too_large" ? 413 : 400, "invalid_body", "Invalid JSON request."); }
  if (!input || typeof input !== "object" || Array.isArray(input) || typeof input.query !== "string") {
    return json(400, "invalid_query", "A query is required.");
  }
  const query = input.query.trim();
  const length = [...new Intl.Segmenter("pt", { granularity: "grapheme" }).segment(query)].length;
  if (length < 1 || length > 200) return json(400, "invalid_query", "Query must contain 1 to 200 characters.");
  const suppliedKey = request.headers.get("X-Evaluation-Key");
  if (suppliedKey && !await matchesSecret(suppliedKey, env.EVALUATION_KEY)) return json(403, "unauthorized", "Invalid evaluation credentials.");
  return { input, query, evaluation: Boolean(suppliedKey) };
}

// Wikipedia PT: free, no API key, never touches the Tavily D1 budget.
const WIKI_API = `https://${WIKIPEDIA_HOST}/w/api.php`;
const WIKI_PAGES = 2;
const WIKI_RAW_CHARS = 6000;
const WIKI_CONTENT_CHARS = 2000; // within the ~2,200-char snippet size the app already expects in `content`
const WIKI_BURST = 30;
// Wikimedia requires an identifying User-Agent. Generic project name only: no e-mail, account or device data.
export const WIKI_USER_AGENT = "FatoOuFarsa-Verificador/1.0 (proxy educacional de checagem; sem dados de usuarios)";

/** Truncate by code points, backing off to the last whitespace so words are not cut. */
function truncate(text, limit) {
  const chars = Array.from(text.slice(0, limit * 2));
  if (chars.length <= limit && text.length <= limit * 2) return text;
  const cut = chars.slice(0, limit).join("");
  const space = cut.search(/\s\S*$/);
  return (space > cut.length * 0.8 ? cut.slice(0, space) : cut).trimEnd();
}

/** Canonical article URL on pt.wikipedia.org; anything else falls back to the title path. */
function wikiURL(page) {
  for (const candidate of [page.canonicalurl, page.fullurl]) {
    try {
      const url = new URL(candidate);
      if (url.protocol === "https:" && url.hostname === WIKIPEDIA_HOST && url.pathname.startsWith("/wiki/") && url.pathname.length > 6) {
        return `https://${WIKIPEDIA_HOST}${url.pathname}`;
      }
    } catch { /* invalid or absent */ }
  }
  const path = encodeURIComponent(page.title.replaceAll(" ", "_")).replaceAll("%2F", "/").replaceAll("%3A", ":");
  return `https://${WIKIPEDIA_HOST}/wiki/${path}`;
}

async function wikiQuery(fetchImpl, params, signal) {
  const url = new URL(WIKI_API);
  for (const [key, value] of Object.entries({ action: "query", format: "json", formatversion: "2", utf8: "1", ...params })) {
    url.searchParams.set(key, value);
  }
  const response = await fetchImpl(url.toString(), { headers: { "User-Agent": WIKI_USER_AGENT, Accept: "application/json" }, signal });
  if (!response.ok) throw new Error("upstream_status");
  const data = await response.json();
  if (data?.error) throw new Error("upstream_error");
  return data;
}

async function searchWikipedia(fetchImpl, query, signal) {
  const search = await wikiQuery(fetchImpl, { list: "search", srsearch: query, srlimit: "3", srnamespace: "0", srprop: "" }, signal);
  const hits = (search?.query?.search ?? []).filter(hit => Number.isInteger(hit?.pageid)).slice(0, WIKI_PAGES);
  // One request per page: TextExtracts returns a single full-text extract per request unless
  // `exintro` is set, and MediaWiki booleans are true when present with any value (even "0"),
  // so `exintro` is omitted entirely to get the whole article.
  const pages = await Promise.all(hits.map(hit => wikiQuery(fetchImpl, {
    prop: "extracts|info|pageprops", explaintext: "1", exsectionformat: "plain", inprop: "url",
    ppprop: "disambiguation", pageids: String(hit.pageid),
  }, signal).then(data => (data?.query?.pages ?? []).find(page => page?.pageid === hit.pageid))));
  const results = [];
  pages.forEach((page, rank) => {
    if (!page || page.missing || page.pageprops?.disambiguation !== undefined || typeof page.title !== "string") return;
    const text = typeof page.extract === "string" ? page.extract.replace(/\n{3,}/g, "\n\n").trim() : "";
    if (!text) return;
    // Score is the search rank only (1, 0.67), not a confidence; the app ranks by its own similarity.
    results.push({ url: wikiURL(page), title: page.title, content: truncate(text, WIKI_CONTENT_CHARS),
      raw_content: truncate(text, WIKI_RAW_CHARS), score: Math.round((1 - rank / 3) * 100) / 100 });
  });
  return results;
}

export function createWorker({ fetchImpl = fetch, now = () => new Date(), wikiTimeoutMs = 4000 } = {}) {
  // Per-isolate burst window for /wiki (no D1, no content): cheap, but not a global cap.
  const wikiBursts = new Map();
  const takeWikiBurst = (lane, minute) => {
    const entry = wikiBursts.get(lane);
    if (!entry || entry.minute !== minute) { wikiBursts.set(lane, { minute, count: 1 }); return true; }
    if (entry.count >= WIKI_BURST) return false;
    entry.count++; return true;
  };
  return {
    async fetch(request, env) {
      // Read-only operator check for reconciliation; never exposes the Tavily secret,
      // queries or search results, and never consumes the search budget.
      if (request.method === "GET" && new URL(request.url).pathname === "/_admin/usage") {
        if (!await matchesSecret(request.headers.get("X-Evaluation-Key"), env.EVALUATION_KEY)) {
          return json(404, "not_found", "Not found.");
        }
        if (!env.TAVILY_API_KEY) return json(503, "configuration", "Search is not configured.");
        try {
          const response = await fetchImpl("https://api.tavily.com/usage", {
            headers: { Authorization: `Bearer ${env.TAVILY_API_KEY}` },
            signal: AbortSignal.any([request.signal, AbortSignal.timeout(4500)]),
          });
          if (!response.ok) return json(503, "usage_unavailable", "Usage is temporarily unavailable.");
          const data = await response.json();
          const account = {};
          for (const field of ["current_plan", "plan_usage", "plan_limit", "paygo_usage", "paygo_limit"]) {
            account[field] = data.account?.[field] ?? null;
          }
          return Response.json({ account, key_usage: data.key?.usage ?? null }, { headers: { "Cache-Control": "no-store" } });
        } catch { return json(503, "usage_unavailable", "Usage is temporarily unavailable."); }
      }
      if (request.method !== "POST") return json(405, "method_not_allowed", "Use POST.");
      if (new URL(request.url).pathname === "/wiki") {
        const parsed = await readQuery(request, env);
        if (parsed instanceof Response) return parsed;
        if (!takeWikiBurst(parsed.evaluation ? "evaluation" : "production", Math.floor(now().getTime() / 60000))) {
          return json(429, "rate_limited", "Please wait before searching again.", { "Retry-After": "60" });
        }
        try {
          const results = await searchWikipedia(fetchImpl, parsed.query, AbortSignal.any([request.signal, AbortSignal.timeout(wikiTimeoutMs)]));
          return Response.json({ query: parsed.query, results }, { headers: { "Cache-Control": "no-store" } });
        } catch (error) {
          return error?.name === "TimeoutError" ? json(504, "upstream_timeout", "Encyclopedia request timed out.")
                                                : json(502, "upstream_failed", "Encyclopedia request failed.");
        }
      }
      if (!env.TAVILY_API_KEY || !env.SEARCH_BUDGET) return json(503, "configuration", "Search is not configured.");
      const parsed = await readQuery(request, env);
      if (parsed instanceof Response) return parsed;
      const { input, query, evaluation } = parsed;
      const date = now();
      // Calendar-month UTC; changing the reset requires reconciling the provider cycle.
      const period = date.toISOString().slice(0, 7);
      const minute = Math.floor(date.getTime() / 60000);
      let reserved;
      try {
        reserved = await env.SEARCH_BUDGET.prepare(RESERVE_SQL).bind(period, evaluation ? 0 : 1, evaluation ? 1 : 0, minute).first();
      } catch { return json(503, "budget_unavailable", "Search budget is temporarily unavailable."); }
      if (!reserved) {
        let row;
        try { row = await env.SEARCH_BUDGET.prepare("SELECT production, evaluation FROM search_budget WHERE period = ?").bind(period).first(); }
        catch { return json(503, "budget_unavailable", "Search budget is temporarily unavailable."); }
        const quota = row && (evaluation ? row.evaluation >= 200 : row.production >= 800);
        return quota ? json(429, "quota_exceeded", "Monthly free search budget exhausted.")
                     : json(429, "rate_limited", "Please wait before searching again.", { "Retry-After": "60" });
      }
      // Server-owned policy. Discard client-supplied costs, answer flags, keys and domains.
      const body = {
        query, search_depth: "basic", max_results: 20, include_answer: false, auto_parameters: false,
        include_raw_content: false, include_images: false, include_image_descriptions: false,
        include_usage: true, include_published_date: true, chunks_per_source: 3,
        language: "pt", filter_by_language: true,
        include_domains_mode: "restrict", include_domains: input.query_kind === "factCheck" ? FACT_CHECK_DOMAINS : ALLOWED_DOMAINS,
        topic: input.topic === "news" ? "news" : "general",
      };
      // Preserve the validated geographic/time routing used by the deployed v1 clients.
      // These filters do not change the search credit cost.
      if (body.topic === "general" && input.country === "brazil") body.country = "brazil";
      if (body.topic === "news" && input.time_range === "year") body.time_range = "year";
      // Dates do not change the credit cost; reject invalid values without forwarding them.
      if (typeof input.start_date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(input.start_date) && !Number.isNaN(Date.parse(input.start_date))
          && new Date(input.start_date).toISOString().slice(0, 10) === input.start_date) {
        body.start_date = input.start_date;
      }
      let upstream;
      try {
        upstream = await fetchImpl("https://api.tavily.com/search", {
          method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${env.TAVILY_API_KEY}` },
          body: JSON.stringify(body), signal: AbortSignal.any([request.signal, AbortSignal.timeout(4500)]),
        });
      } catch { return json(502, "upstream_failed", "Search request failed."); }
      // Never refund uncertain attempts: the provider may already have consumed a credit.
      const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
      if ([432, 433].includes(upstream.status)) headers["X-Search-Error"] = "quota_exceeded";
      if (upstream.status === 429) headers["X-Search-Error"] = "rate_limited";
      const retry = upstream.headers.get("Retry-After");
      if (retry) headers["Retry-After"] = retry;
      return new Response(upstream.body, { status: upstream.status, headers });
    },
  };
}
export default createWorker();
