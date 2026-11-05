import { test } from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createWorker } from "../src/index.js";
import { ALLOWED_DOMAINS } from "../src/domains.js";

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
