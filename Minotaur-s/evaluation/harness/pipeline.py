"""Offline replica of `VerificationPipeline` (baseline v0.5) with pluggable stages."""
from __future__ import annotations

import json
import re
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field, asdict
from datetime import datetime, timedelta
from urllib.parse import urlsplit

from bs4 import BeautifulSoup

import models
import netcache
import textutil as tu

ALLOWLIST = ["g1.globo.com", "oglobo.globo.com", "folha.uol.com.br", "estadao.com.br", "cnnbrasil.com.br",
             "veja.abril.com.br", "valor.globo.com", "exame.com", "r7.com", "terra.com.br", "metropoles.com",
             "poder360.com.br", "gauchazh.clicrbs.com.br", "correiobraziliense.com.br", "agenciabrasil.ebc.com.br",
             "otempo.com.br", "www.band.com.br", "ge.globo.com", "aosfatos.org", "www.agencialupa.org", "bbc.com",
             "dw.com", "elpais.com", "apnews.com", "gov.br", "agenciagov.ebc.com.br", "camara.leg.br",
             "senado.leg.br", "stf.jus.br", "tse.jus.br", "who.int"]
FACT_CHECK = ["aosfatos.org", "www.agencialupa.org", "g1.globo.com", "estadao.com.br"]


def _canon_host(h: str) -> str:
    h = h.lower().rstrip(".")
    return h[4:] if h.startswith("www.") else h


def matched_domain(url: str) -> str | None:
    try:
        p = urlsplit(url)
    except ValueError:
        return None
    if p.scheme != "https" or not p.hostname or p.username:
        return None
    host = _canon_host(p.hostname)
    hits = [d for d in ALLOWLIST if host == _canon_host(d) or host.endswith("." + _canon_host(d))]
    return max(hits, key=lambda d: len(_canon_host(d))) if hits else None


def editorial_origin(domain: str) -> str:
    clean = domain.replace("www.", "")
    if clean.endswith("globo.com"):
        return "grupo-globo"
    if clean.endswith("ebc.com.br"):
        return "ebc"
    return clean


def source_kind(domain: str) -> str:
    clean = domain.replace("www.", "")
    if clean == "pt.wikipedia.org":
        return "encyclopedia"
    if clean.endswith(("gov.br", "leg.br", "jus.br")) or clean == "who.int":
        return "primary"
    if clean in ("aosfatos.org", "agencialupa.org"):
        return "factCheck"
    return "journalism"


# ---- query plan (SearchQueryBuilder.plan) ---------------------------------------------
def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    head = text[:limit]
    cut = head.rfind(" ")
    return head if cut <= 0 else head[:cut].strip() or head


def query_plan(ctx: dict) -> list[dict]:
    text = ctx["text"]
    if ctx["start"]:
        for rel in ("hoje", "ontem"):
            text = re.sub(rf"\b{rel}\b", "em " + ctx["start"].isoformat(), text, flags=re.I)
    primary = truncate(text, 200)
    if len(text) > 200:
        suffix = text[-200:]
        contextual = suffix[suffix.find(" ") + 1:] if " " in suffix else suffix
    elif ctx["kind"] == "current":
        contextual = truncate(text, 175) + " " + ctx["reference"].isoformat()
    else:
        contextual = primary
    plan = [("descriptive", primary), ("contextual", truncate(contextual, 200)),
            ("factCheck", truncate(text, 188) + " checagem")]
    seen, out = set(), []
    for kind, q in plan:
        if q and q not in seen:
            seen.add(q)
            out.append({"kind": kind, "text": q})
    return out


def search_body(query: dict, ctx: dict) -> dict:
    body = {"query": query["text"][:200], "search_depth": "basic", "max_results": 20,
            "include_domains": FACT_CHECK if query["kind"] == "factCheck" else sorted(ALLOWLIST),
            "include_domains_mode": "restrict", "include_answer": False, "auto_parameters": False,
            "include_usage": True, "language": "pt", "filter_by_language": True, "include_published_date": True,
            "query_kind": query["kind"]}
    if ctx["kind"] in ("current", "recent"):
        if ctx["start"]:
            body["start_date"] = ctx["start"].isoformat()
        body["topic"] = "news"
    return body


def run_search(query: dict, ctx: dict) -> list[dict]:
    resp = netcache.search(search_body(query, ctx))
    if resp["status"] != 200 or not resp.get("json"):
        raise RuntimeError(f"search failed: {resp['status']} {resp.get('error')}")
    return [r for r in resp["json"].get("results", []) if matched_domain(r.get("url", ""))][:20]


def rank_articles(items: list[dict], claim: str) -> list[dict]:
    lexical = tu.bm25(claim, [i["title"] + " " + i.get("content", "") for i in items])
    order = sorted(range(len(items)), key=lambda k: (-(lexical[k] + (items[k].get("score") or 0)), k))
    seen_urls, seen_origins, diverse, others = set(), set(), [], []
    for k in order:
        item = items[k]
        dom = matched_domain(item["url"])
        if not dom or tu.canonical_url(item["url"]) in seen_urls:
            continue
        seen_urls.add(tu.canonical_url(item["url"]))
        origin = editorial_origin(dom)
        (diverse if origin not in seen_origins else others).append(item)
        seen_origins.add(origin)
    return diverse + others


# ---- extraction (ArticleExtractor) ----------------------------------------------------
MIN_TEXT = 200


def _normalize(text: str) -> str:
    lines = [" ".join(l.split()) for l in text.splitlines()]
    return "\n".join(l for l in lines if l).strip()


def _main_text(soup: BeautifulSoup) -> str:
    for tag in ["script", "style", "noscript", "iframe", "svg", "form", "nav", "header", "footer", "aside",
                "figure", "figcaption"]:
        for el in soup.find_all(tag):
            el.decompose()
    best, best_score = None, 0.0
    for el in soup.find_all(["article", "main", "section", "div"]):
        ps = el.find_all("p")
        if not ps:
            continue
        length = sum(len(t) for t in (p.get_text(" ", strip=True) for p in ps) if len(t) >= 25)
        if length <= 0:
            continue
        links = sum(len(a.get_text(" ", strip=True)) for a in el.find_all("a"))
        score = length * (1 - min(1.0, links / length))
        if score > best_score:
            best, best_score = el, score
    if best is None:
        return _normalize(soup.get_text("\n"))
    paras = [p.get_text(" ", strip=True) for p in best.find_all("p")]
    paras = [p for p in paras if p]
    return _normalize("\n".join(paras)) if paras else _normalize(best.get_text("\n"))


def extract(item: dict) -> dict | None:
    page = netcache.html(item["url"])
    snippet = _normalize(item.get("content", ""))
    def fallback():
        if len(snippet) < MIN_TEXT:
            return None
        return {"url": item["url"], "final_url": item["url"], "title": item["title"], "text": snippet,
                "published": tu.parse_date(item.get("published_date")), "provenance": "searchSnippet",
                "partial": True, "canonical": None, "original": None}
    if not page.get("html") or not matched_domain(page.get("final_url") or ""):
        return fallback()
    soup = BeautifulSoup(page["html"], "lxml")
    structured = []
    def visit(obj):
        if isinstance(obj, list):
            for x in obj:
                visit(x)
            return
        if not isinstance(obj, dict):
            return
        types = obj.get("@type")
        types = types if isinstance(types, list) else [types or ""]
        if any(t in ("NewsArticle", "Article", "ReportageNewsArticle", "ClaimReview") for t in types):
            structured.append(obj)
        for k in ("@graph", "mainEntity"):
            if k in obj:
                visit(obj[k])
    for s in soup.find_all("script", attrs={"type": "application/ld+json"}):
        try:
            visit(json.loads(s.string or ""))
        except (ValueError, TypeError):
            pass
    data = structured[0] if structured else {}
    def meta(key):
        el = soup.find("meta", attrs={"property": key}) or soup.find("meta", attrs={"name": key})
        return el.get("content") if el and el.get("content") else None
    free = data.get("isAccessibleForFree")
    paywalled = free is False or (isinstance(free, str) and free.lower() == "false")
    og_type = meta("og:type") or ""
    paid_marker = bool(soup.select("[itemprop='isAccessibleForFree'][content='false'],[data-paywall='true'],"
                                   "[data-article-access='paid'],.paywall,.subscription-required,.article-preview"))
    canonical = soup.find("link", attrs={"rel": "canonical"})
    title = data.get("headline") if isinstance(data.get("headline"), str) else (meta("og:title") or item["title"])
    published = tu.parse_date(data.get("datePublished") if isinstance(data.get("datePublished"), str) else None) \
        or tu.parse_date(meta("article:published_time")) or tu.parse_date(item.get("published_date"))
    visible = _main_text(soup)
    body = data.get("articleBody") if isinstance(data.get("articleBody"), str) else None
    use_structured = not paywalled and len(visible) < MIN_TEXT and body and len(body) >= MIN_TEXT
    text = _normalize(body) if use_structured else visible
    if len(text) < MIN_TEXT:
        return fallback()
    return {"url": item["url"], "final_url": page["final_url"], "title": title, "text": text,
            "published": published, "provenance": "structuredData" if use_structured else "articleBody",
            "partial": paywalled or og_type == "website" or paid_marker,
            "canonical": canonical.get("href") if canonical else None,
            "original": data.get("isBasedOn") if isinstance(data.get("isBasedOn"), str) else meta("citation_source")}


def collect(ctx: dict, max_queries: int = 1, force_expand: bool = False) -> dict:
    """Search + reading, approximating the concurrent scheduling of `collect()`."""
    queries = query_plan(ctx)
    items, seen, errors = [], set(), []
    def add(results):
        for r in results:
            key = tu.canonical_url(r["url"])
            if key not in seen:
                seen.add(key)
                items.append(r)
    try:
        add(run_search(queries[0], ctx))
    except RuntimeError as e:
        errors.append(str(e))
    calls = 1
    origins = {editorial_origin(matched_domain(i["url"])) for i in items}
    expanded = False
    if (force_expand or len(origins) < 2 or len(items) < 4) and calls < max_queries:
        expanded = True
        for q in queries[1:max_queries]:
            try:
                add(run_search(q, ctx)); calls += 1
            except RuntimeError as e:
                errors.append(str(e))
    queue = rank_articles(items, ctx["text"])[:8]
    with ThreadPoolExecutor(4) as pool:
        articles = [a for a in pool.map(extract, queue) if a]
    return {"queries": queries[:calls], "items": items, "articles": articles, "errors": errors,
            "expanded": expanded}


def reference_for(record: dict) -> datetime:
    if record.get("reference_date"):
        return datetime.fromisoformat(record["reference_date"]) + timedelta(days=1)
    return datetime(2026, 11, 24)
