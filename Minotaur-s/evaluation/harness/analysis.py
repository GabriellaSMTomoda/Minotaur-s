"""Analysis stage: windows → retrieval → NLI. `baseline` mirrors the Swift v0.5 code."""
from __future__ import annotations

import re

import models
import pipeline as p
import textutil as tu

TOP_CHUNKS = 3
PAIR_BUDGET = 24


def _names(text):
    return set(re.findall(r"\b[A-ZÁÉÍÓÚÂÊÔÃÕÇ][\wÀ-ÿ]+\b", text))


def near_duplicate(a: str, b: str) -> bool:
    ta, tb = tu.terms(a), tu.terms(b)
    if ta == tb:
        return True
    if _names(a) != _names(b):
        return False
    def shingles(t):
        return set(t) if len(t) < 5 else {" ".join(t[i:i + 5]) for i in range(len(t) - 4)}
    x, y = shingles(ta), shingles(tb)
    union = len(x | y)
    return union > 0 and len(x & y) / union >= 0.85


def windows_for(text: str, claim: str) -> list[str]:
    nli, emb = models.nli(), models.embeddings()
    premise_budget = 509 - nli.token_count(claim)
    nli_chunker = tu.TextChunker(premise_budget, nli.token_count)
    emb_chunker = tu.TextChunker(126, emb.token_count)
    return [w for c in emb_chunker.chunks(text) for w in nli_chunker.chunks(c) if tu.chunk_ok(w)]


def select_top(claim: str, windows: list[str], claim_vec) -> list[tuple[int, float]]:
    emb = models.embeddings()
    lexical = tu.bm25(claim, windows)
    cand = sorted(range(len(windows)), key=lambda i: (-lexical[i], i))[:48]
    stride = max(1, len(windows) // 16)
    cand += list(range(0, len(windows), stride))[:16]
    cand = sorted(set(cand))
    sims = [emb.cosine(claim_vec, emb.embed(windows[i])) for i in cand]
    lex = [lexical[i] for i in cand]
    order = tu.fused_order(lex, sims)[:TOP_CHUNKS]
    return [(cand[k], sims[k]) for k in order]


def expand(selected, windows, claim):
    nli = models.nli()
    available = max(1, 509 - nli.token_count(claim))
    out, seen = [], set()
    for index, sim in selected:
        text = windows[index]
        for nb in (index + 1, index - 1):
            if 0 <= nb < len(windows):
                cand = text + " " + windows[nb] if nb > index else windows[nb] + " " + text
                if nli.token_count(cand) <= available:
                    text = cand
        if text not in seen:
            seen.add(text)
            out.append((text, sim))
    return out


def analyze_baseline(ctx: dict, articles: list[dict], pair_budget: int = PAIR_BUDGET) -> dict:
    nli, emb = models.nli(), models.embeddings()
    claim = ctx["text"]
    claim_vec = emb.embed(claim)
    sources, previous, pairs, exhausted = [], [], 0, False
    for art in sorted(articles, key=lambda a: a["partial"]):
        if exhausted:
            break
        key = tu.canonical_url(art.get("canonical") or art["final_url"])
        dup = next((s for s, a in previous if tu.canonical_url(a.get("canonical") or a["final_url"]) == key
                    or near_duplicate(a["text"], art["text"])), None)
        domain = p.matched_domain(art["url"]) or ""
        if dup:
            sources.append({**dup, "url": art["final_url"], "domain": domain, "duplicate_of": dup["url"]})
            continue
        windows = windows_for(art["text"], claim)
        if not windows:
            continue
        selected = select_top(claim, windows, claim_vec)
        if not selected:
            continue
        passages = []
        for text, sim in expand(selected, windows, claim):
            if pairs >= pair_budget:
                exhausted = True
                break
            pairs += 1
            logits, probs = nli.predict(text, claim)
            passages.append({"text": text, "similarity": round(sim, 4), "probs": probs.as_dict(),
                             "logits": [round(x, 4) for x in logits]})
        if not passages:
            continue
        joined = " ".join(x["text"] for x in passages)
        align = tu.alignment(ctx, art["published"], joined)
        origin = art.get("original") or p.editorial_origin(domain)
        src = {"url": art["final_url"], "domain": domain, "title": art["title"], "kind": p.source_kind(domain),
               "provenance": art["provenance"], "partial": art["partial"], "alignment": align,
               "published": art["published"].isoformat() if art["published"] else None,
               "origin": origin, "duplicate_of": None, "passages": passages}
        sources.append(src)
        previous.append((src, art))
    return {"sources": sources, "pairs": pairs, "pair_budget_exhausted": exhausted}


def eligible(src: dict) -> bool:
    return (not src["partial"] and src["provenance"] != "searchSnippet" and src["alignment"] == "compatible"
            and src["duplicate_of"] is None)


def best_label(pr: dict) -> str:
    if pr["neutral"] >= pr["entailment"] and pr["neutral"] >= pr["contradiction"]:
        return "neutral"
    return "entailment" if pr["entailment"] >= pr["contradiction"] else "contradiction"


def verdict_baseline(sources: list[dict], minimum: float = 0.5, single: float = 0.5) -> tuple[str, list]:
    """`VerdictAggregator.verdict` v0.5: any qualified support + any qualified refutation = DIVERGENTE."""
    if not sources:
        return "NAO_ENCONTRADO", []
    votes = []
    for s in sources:
        if not eligible(s):
            continue
        for ps in s["passages"]:
            lab = best_label(ps["probs"])
            conf = ps["probs"][lab]
            if lab != "neutral" and conf >= minimum:
                votes.append({"label": lab, "confidence": conf, "origin": s["origin"], "url": s["url"],
                              "text": ps["text"][:200]})
    one = len({v["origin"] for v in votes}) == 1
    votes = [v for v in votes if v["confidence"] >= (single if one else minimum)]
    sup = any(v["label"] == "entailment" for v in votes)
    ref = any(v["label"] == "contradiction" for v in votes)
    if sup and ref:
        return "DIVERGENTE", votes
    if sup:
        return "CONFIRMADO", votes
    if ref:
        return "CONTRADITO", votes
    return "SEM_INFORMACAO", votes
