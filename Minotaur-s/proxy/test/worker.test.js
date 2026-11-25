import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createWorker } from "../src/index.js";
import { ALLOWED_DOMAINS, WIKIPEDIA_HOST } from "../src/domains.js";
import { WIKI_USER_AGENT } from "../src/index.js";

function database() {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../migrations/0001_search_budget.sql", import.meta.url), "utf8"));
  return { db, prepare(sql) { return { bind(...values) { return { async first() { return db.prepare(sql).get(...values) ?? null; } }; } }; } };
}
function request(body = { query: "Uma afirmação a verificar" }, headers = {}) {
  return new Request("https://proxy.example/", { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
}
function setup(fetchImpl = async () => Response.json({ results: [] })) {
  const budget = database();
  const worker = createWorker({ fetchImpl, now: () => new Date("2026-11-04T12:00:00Z") });
  return { worker, budget, env: { SEARCH_BUDGET: budget, TAVILY_API_KEY: "test-key", EVALUATION_KEY: "test-evaluation" } };
}

test("client cannot enable LLM answers, increase cost, replace key or broaden domains", async () => {
  let upstream;
  const { worker, env } = setup(async (url, init) => { upstream = { url, ...init, body: JSON.parse(init.body) }; return Response.json({ results: [] }); });
  assert.equal((await worker.fetch(request({ query: "Uma afirmação", search_depth: "advanced", include_answer: true,
    auto_parameters: true, include_domains: ["untrusted.example"], api_key: "injected", max_results: 1000 }), env)).status, 200);
  assert.equal(upstream.body.search_depth, "basic");
  assert.equal(upstream.body.include_answer, false);
  assert.equal(upstream.body.auto_parameters, false);
  assert.equal(upstream.body.language, "pt");
  assert.equal(upstream.body.filter_by_language, true);
  assert.equal(upstream.body.max_results, 20);
  assert.deepEqual(upstream.body.include_domains, ALLOWED_DOMAINS);
  assert.equal(upstream.body.api_key, undefined);
  assert.equal(upstream.headers.Authorization, "Bearer test-key");
});

test("atomic reservation never exceeds 800 production calls under concurrent requests", async () => {
  let calls = 0;
  const { worker, env, budget } = setup(async () => { calls++; return Response.json({ results: [] }); });
  budget.db.prepare("INSERT INTO search_budget VALUES (?, ?, ?, ?, ?)").run("2026-11", 795, 0, 0, 0);
  const results = await Promise.all(Array.from({ length: 40 }, () => worker.fetch(request(), env)));
  assert.equal(calls, 5);
  assert.equal(results.filter(r => r.status === 200).length, 5);
  assert.equal(budget.db.prepare("SELECT production FROM search_budget").get().production, 800);
  for (const response of results.filter(r => r.status === 429)) assert.equal(response.headers.get("X-Search-Error"), "quota_exceeded");
});

test("evaluation has a distinct 200-call allowance and requires a secret", async () => {
  const { worker, env, budget } = setup();
  budget.db.prepare("INSERT INTO search_budget VALUES (?, ?, ?, ?, ?)").run("2026-11", 800, 199, 0, 0);
  assert.equal((await worker.fetch(request({}, { "X-Evaluation-Key": "wrong" }), env)).status, 400);
  assert.equal((await worker.fetch(request(undefined, { "X-Evaluation-Key": "wrong" }), env)).status, 403);
  assert.equal((await worker.fetch(request(undefined, { "X-Evaluation-Key": "test-evaluation" }), env)).status, 200);
  assert.equal((await worker.fetch(request(undefined, { "X-Evaluation-Key": "test-evaluation" }), env)).status, 429);
  const row = budget.db.prepare("SELECT production, evaluation FROM search_budget").get();
  assert.equal(row.production + row.evaluation, 1000);
});

test("uncertain upstream failures consume their reservation", async () => {
  const { worker, env, budget } = setup(async () => { throw new Error("network"); });
  assert.equal((await worker.fetch(request(), env)).status, 502);
  assert.equal(budget.db.prepare("SELECT production FROM search_budget").get().production, 1);
});

test("missing or failed D1 fails closed before touching upstream", async () => {
  let calls = 0;
  const { worker, env } = setup(async () => { calls++; return Response.json({ results: [] }); });
  assert.equal((await worker.fetch(request(), { ...env, SEARCH_BUDGET: undefined })).status, 503);
  env.SEARCH_BUDGET = { prepare() { throw new Error("unavailable"); } };
  assert.equal((await worker.fetch(request(), env)).status, 503);
  assert.equal(calls, 0);
});

test("reject oversized/malformed requests and queries over 200 graphemes", async () => {
  const { worker, env, budget } = setup();
  assert.equal((await worker.fetch(request({ query: "x".repeat(201) }), env)).status, 400);
  assert.equal((await worker.fetch(request({ query: "x".repeat(9000) }), env)).status, 413);
  assert.equal((await worker.fetch(new Request("https://proxy.example"), env)).status, 405);
  assert.equal(budget.db.prepare("SELECT count(*) AS n FROM search_budget").get().n, 0);
});

test("burst protection is atomic and distinct from monthly quota", async () => {
  const { worker, env, budget } = setup();
  const results = await Promise.all(Array.from({ length: 40 }, () => worker.fetch(request(), env)));
  assert.equal(results.filter(r => r.status === 200).length, 30);
  assert.equal(results.find(r => r.status === 429).headers.get("X-Search-Error"), "rate_limited");
  assert.equal(budget.db.prepare("SELECT production FROM search_budget").get().production, 30);
});

test("new period resets counters without recording request content", async () => {
  const { worker, env, budget } = setup();
  budget.db.prepare("INSERT INTO search_budget VALUES (?, ?, ?, ?, ?)").run("2026-10", 800, 200, 0, 0);
  assert.equal((await worker.fetch(request(), env)).status, 200);
  const columns = budget.db.prepare("PRAGMA table_info(search_budget)").all().map(x => x.name);
  assert.deepEqual(columns, ["period", "production", "evaluation", "minute", "burst"]);
});

test("domain lists match the Swift allowlist", () => {
  const swift = readFileSync(new URL("../../Minotaur-s/Models/Verificador/TrustedDomain.swift", import.meta.url), "utf8").split("static let allowlist: Set<String> = [")[1];
  const entries = [...swift.matchAll(/^\s*"([a-z0-9.-]+)"/gm)].map(x => x[1]);
  assert.deepEqual(new Set(ALLOWED_DOMAINS), new Set(entries));
});

test("preserves legacy country/time routing without forwarding arbitrary filters", async () => {
  const bodies = [];
  const { worker, env } = setup(async (_, init) => {
    bodies.push(JSON.parse(init.body)); return Response.json({ results: [] });
  });
  await worker.fetch(request({ query: "Uma afirmação", topic: "general", country: "brazil", time_range: "year" }), env);
  await worker.fetch(request({ query: "Uma afirmação", topic: "news", country: "brazil", time_range: "year" }), env);
  await worker.fetch(request({ query: "Uma afirmação", topic: "news", country: "other", time_range: "century" }), env);
  assert.equal(bodies[0].country, "brazil");
  assert.equal(bodies[0].time_range, undefined);
  assert.equal(bodies[1].time_range, "year");
  assert.equal(bodies[1].country, undefined);
  assert.equal(bodies[2].time_range, undefined);
  assert.equal(bodies[2].country, undefined);
});

test("operator usage requires authentication and returns only counters/plan without reserving a search", async () => {
  let calls = 0;
  const { worker, env, budget } = setup(async (url, init) => {
    calls++;
    assert.equal(url, "https://api.tavily.com/usage");
    assert.equal(init.headers.Authorization, "Bearer test-key");
    return Response.json({ account: { current_plan: "Researcher", plan_usage: 17, plan_limit: 1000,
      paygo_usage: 0, paygo_limit: null, unrelated_private_data: "never return" }, key: { usage: 17, api_key: "never return" } });
  });
  const url = "https://proxy.example/_admin/usage";
  assert.equal((await worker.fetch(new Request(url), env)).status, 404);
  assert.equal(calls, 0);
  const response = await worker.fetch(new Request(url, { headers: { "X-Evaluation-Key": "test-evaluation" } }), env);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.deepEqual(await response.json(), { account: { current_plan: "Researcher", plan_usage: 17, plan_limit: 1000,
    paygo_usage: 0, paygo_limit: null }, key_usage: 17 });
  assert.equal(budget.db.prepare("SELECT count(*) AS n FROM search_budget").get().n, 0);
});

// --- POST /wiki (Wikipedia PT) ---------------------------------------------------------------

function wikiRequest(body = { query: "Capital do Brasil" }, headers = {}) {
  return new Request("https://proxy.example/wiki", { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
}
// Mocked MediaWiki API: search returns `hits`; each extracts call returns the matching page.
function wikiMock(hits, pages, calls = []) {
  return async (url, init) => {
    const parsed = new URL(url);
    calls.push({ url: parsed, init });
    if (parsed.searchParams.get("list") === "search") return Response.json({ query: { search: hits } });
    const id = Number(parsed.searchParams.get("pageids"));
    return Response.json({ query: { pages: pages.filter(page => page.pageid === id) } });
  };
}
const brasilia = { pageid: 10, title: "Brasília", canonicalurl: "https://pt.wikipedia.org/wiki/Bras%C3%ADlia",
  extract: "Brasília é a capital federal do Brasil. ".repeat(400) };
const distrito = { pageid: 20, title: "Distrito Federal (Brasil)", fullurl: "https://pt.wikipedia.org/wiki/Distrito_Federal_(Brasil)",
  extract: "O Distrito Federal abriga Brasília." };

test("wiki returns Tavily-shaped results from the two best Wikipedia PT pages without Tavily or D1", async () => {
  const calls = [];
  const worker = createWorker({ fetchImpl: wikiMock([{ pageid: 10 }, { pageid: 20 }, { pageid: 30 }], [brasilia, distrito], calls),
    now: () => new Date("2026-11-04T12:00:00Z") });
  const response = await worker.fetch(wikiRequest(), {});
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  const { results } = await response.json();
  assert.deepEqual(results.map(r => r.url), ["https://pt.wikipedia.org/wiki/Bras%C3%ADlia", "https://pt.wikipedia.org/wiki/Distrito_Federal_(Brasil)"]);
  assert.deepEqual(results.map(r => r.score), [1, 0.67]);
  assert.equal(results[0].title, "Brasília");
  assert.ok(Array.from(results[0].raw_content).length <= 6000 && results[0].raw_content.length > 5000);
  assert.ok(Array.from(results[0].content).length <= 2000 && results[0].raw_content.startsWith(results[0].content));
  assert.equal(results[1].content, distrito.extract);
  assert.equal(results[0].published_date, undefined);

  assert.equal(calls.length, 3);
  for (const { url, init } of calls) {
    assert.equal(url.origin, `https://${WIKIPEDIA_HOST}`);
    assert.equal(url.pathname, "/w/api.php");
    assert.equal(init.headers["User-Agent"], WIKI_USER_AGENT);
    assert.doesNotMatch(WIKI_USER_AGENT, /@/);
    assert.equal(init.headers.Authorization, undefined);
    assert.ok(init.signal instanceof AbortSignal);
  }
  assert.equal(calls[0].url.searchParams.get("srsearch"), "Capital do Brasil");
  assert.equal(calls[0].url.searchParams.get("srlimit"), "3");
  assert.deepEqual(calls.slice(1).map(c => c.url.searchParams.get("pageids")), ["10", "20"]);
  for (const { url } of calls.slice(1)) {
    assert.equal(url.searchParams.get("explaintext"), "1");
    assert.equal(url.searchParams.get("inprop"), "url");
    assert.match(url.searchParams.get("prop"), /extracts/);
    assert.equal(url.searchParams.has("exintro"), false, "any exintro value would limit to the intro");
  }
});

test("wiki validates like search, accepts the evaluation header and never touches the Tavily budget", async () => {
  let calls = 0;
  const { worker, env, budget } = setup(async () => { calls++; return Response.json({ query: { search: [] } }); });
  assert.equal((await worker.fetch(wikiRequest({ query: "x".repeat(201) }), env)).status, 400);
  assert.equal((await worker.fetch(wikiRequest({ query: "x".repeat(9000) }), env)).status, 413);
  assert.equal((await worker.fetch(wikiRequest({}), env)).status, 400);
  assert.equal((await worker.fetch(new Request("https://proxy.example/wiki"), env)).status, 405);
  assert.equal((await worker.fetch(wikiRequest(undefined, { "X-Evaluation-Key": "wrong" }), env)).status, 403);
  assert.equal(calls, 0);
  const evaluation = await worker.fetch(wikiRequest(undefined, { "X-Evaluation-Key": "test-evaluation" }), env);
  assert.equal(evaluation.status, 200);
  assert.deepEqual((await evaluation.json()).results, []);
  assert.equal((await worker.fetch(wikiRequest(), env)).status, 200);
  assert.equal(calls, 2, "empty search makes no extract calls");
  assert.equal(budget.db.prepare("SELECT count(*) AS n FROM search_budget").get().n, 0);
});

test("wiki burst cap is per minute and keeps the evaluation lane separate", async () => {
  let minute = "2026-11-04T12:00:00Z";
  const worker = createWorker({ fetchImpl: wikiMock([], []), now: () => new Date(minute) });
  const env = { EVALUATION_KEY: "test-evaluation" };
  const results = await Promise.all(Array.from({ length: 31 }, () => worker.fetch(wikiRequest(), env)));
  assert.equal(results.filter(r => r.status === 200).length, 30);
  const limited = results.find(r => r.status === 429);
  assert.equal(limited.headers.get("X-Search-Error"), "rate_limited");
  assert.equal(limited.headers.get("Retry-After"), "60");
  assert.equal((await worker.fetch(wikiRequest(undefined, { "X-Evaluation-Key": "test-evaluation" }), env)).status, 200);
  minute = "2026-11-04T12:01:00Z";
  assert.equal((await worker.fetch(wikiRequest(), env)).status, 200);
});

test("wiki skips disambiguation/empty pages and rebuilds non-Wikipedia URLs from the title", async () => {
  const pages = [
    { pageid: 1, title: "Mercúrio", pageprops: { disambiguation: "" }, canonicalurl: "https://pt.wikipedia.org/wiki/Merc%C3%BArio", extract: "Mercúrio pode referir-se a:" },
    { pageid: 2, title: "Mercúrio (planeta)", canonicalurl: "https://evil.example/wiki/x", extract: "Mercúrio é o menor planeta.\n\n\n\nÓrbita" },
  ];
  const worker = createWorker({ fetchImpl: wikiMock([{ pageid: 1 }, { pageid: 2 }], pages) });
  const { results } = await (await worker.fetch(wikiRequest(), {})).json();
  assert.equal(results.length, 1);
  assert.equal(results[0].url, "https://pt.wikipedia.org/wiki/Merc%C3%BArio_(planeta)");
  assert.equal(results[0].content, "Mercúrio é o menor planeta.\n\nÓrbita");
  const empty = createWorker({ fetchImpl: wikiMock([{ pageid: 3 }], [{ pageid: 3, title: "Vazio", extract: "" }]) });
  assert.deepEqual((await (await empty.fetch(wikiRequest(), {})).json()).results, []);
});

test("wiki upstream errors and the 4 s timeout are 5xx, never an empty result", async () => {
  const failing = createWorker({ fetchImpl: async () => new Response("busy", { status: 503 }) });
  assert.equal((await failing.fetch(wikiRequest(), {})).status, 502);
  const apiError = createWorker({ fetchImpl: async () => Response.json({ error: { code: "internal" } }) });
  assert.equal((await apiError.fetch(wikiRequest(), {})).status, 502);
  const extractFails = createWorker({ fetchImpl: async url =>
    new URL(url).searchParams.get("list") ? Response.json({ query: { search: [{ pageid: 1 }] } }) : Promise.reject(new Error("network")) });
  assert.equal((await extractFails.fetch(wikiRequest(), {})).status, 502);
  const slow = createWorker({ wikiTimeoutMs: 20, fetchImpl: (_, init) =>
    new Promise((_, reject) => init.signal.addEventListener("abort", () => reject(init.signal.reason))) });
  const timedOut = await slow.fetch(wikiRequest(), {});
  assert.equal(timedOut.status, 504);
  assert.equal(timedOut.headers.get("X-Search-Error"), "upstream_timeout");
});
