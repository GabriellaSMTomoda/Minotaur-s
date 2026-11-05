import { ALLOWED_DOMAINS, FACT_CHECK_DOMAINS } from "./domains.js";

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

export function createWorker({ fetchImpl = fetch, now = () => new Date() } = {}) {
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
      if (!env.TAVILY_API_KEY || !env.SEARCH_BUDGET) return json(503, "configuration", "Search is not configured.");
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
      const evaluation = Boolean(suppliedKey);
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
