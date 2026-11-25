"""Evidence v3: sentence-level premises, relevance gates and origin-weighted aggregation.

This is the reference implementation that the Swift `EvidenceScorer` mirrors.
"""
from __future__ import annotations

import re

import analysis
import models
import pipeline as p
import textutil as tu

STOPWORDS = set(tu.folded(w) for w in """a o as os um uma uns umas de da do das dos em na no nas nos por pela pelo pelas pelos
para pra com sem sob sobre entre ate até e ou mas que se ao aos à às é ser foi são era eram está estão esta este
isso isto essa esse seu sua seus suas lhe lhes já não nao mais muito muita também tambem como quando onde qual quais
quem cujo cuja há ha tem têm ter sido pode podem vai vão""".split())
PRONOUN_START = re.compile(r"^(ele|ela|eles|elas|isso|isto|esse|essa|esses|essas|o mesmo|a mesma|segundo ele|"
                           r"segundo ela|além disso|porém|mas|no entanto|contudo|entretanto|também)\b", re.I)
DEBUNK = re.compile(r"\b(e falso|falso que|nao e verdade|e fake|fake news|boato|enganos[oa]|desinformacao|"
                    r"mentira|desmente|desmentiu|nao procede|sem comprovacao|nao ha evidencias?|teoria da conspiracao|"
                    r"checagem|#fake|e #fake|e mito|mito que|desmentid[oa]s?|enganam|diferentemente do que|"
                    r"informacao falsa|noticia falsa|nao e capaz de|nao existe(m)? evidencias?)\b")
# Sentences that report what circulates (hoax quoted by a fact-check) do not assert it.
REPORTED = re.compile(r"\b(circula(m|ram|va)?|circulou|viraliz\w*|nas redes|redes sociais|post(s|agens?)? (que|com)|"
                      r"publica(cao|coes) (que|nas|com)|alegacao|legenda|video que|mensage(m|ns) que|corrente|promete(m)?|"
                      r"trabalho de verificacao|teorias? da conspiracao|acredita(m)? que|quem acredita|terraplanistas?|"
                      r"segundo (o|a)s? (boatos?|posts?|publicac\w+)|usuarios? (afirma|compartilha)\w*)\b")
HEDGE = re.compile(r"\b(pode|podem|poderia|poderiam|talvez)\s+nao\b")
# Superlative claim vs. ranked passage: "7º maior produtor" refutes "o maior produtor".
SUPERLATIVE = re.compile(r"\b(o|a|os|as) (maior|menor|mais|melhor|pior|primeir[oa]|unic[oa])\b")
RANKED = re.compile(r"(\b\d{1,2}\s?[ºª°o]|\b(segund|terceir|quart|quint|sext|setim|oitav|non|decim)[oa]s?\b)"
                    r"\s*(\w+\s){0,3}?(maior|menor|mais|melhor|pior|posicao|lugar|coloca)")
# Boilerplate that leaks names into passages ("Agência Brasil", photo credits, breadcrumbs).
BOILERPLATE = [re.compile(p, re.I) for p in (
    r">>\s*Siga o canal.*$", r"\s*[—-]\s*Foto:.*$", r"Foto:\s*[^.]*?/\s*Agência Brasil", r"^PUBLICIDADE\s*",
    r"^(Página Inicial|Home)\s*».*?»\s*[^»]*?(?=[A-ZÀ-Ú][a-zà-ú]+ (é|foi|são|tem)\b)", r"\s*\|\s*(G1|Agência de Notícias|Agência Brasil)\s*$",
    r"\s+-\s+Portal Gov\.br\s*$", r"^Oferecido por\s+")]
STARTERS = set("""outro outra outros outras ele ela eles elas segundo quando apesar hoje veja confira ainda assim
porem contudo entretanto alem desde durante enquanto embora depois antes agora entao tambem cada todo toda todos todas
muitos muitas alguns algumas este esta estes estas esse essa esses essas aquele aquela nesta neste nessa nesse
por fim leia saiba entenda""".split())
OPTION = re.compile(r"^\(?[A-Ea-e1-5][).]\s")
NEGATION = re.compile(r"\b(nao|nunca|jamais|nem|nenhum|nenhuma)\b")
NUMBER = re.compile(r"\b\d+(?:[.,]\d+)?\b")

DEFAULT_POLICY = {
    "version": "evidence-v3-dev",
    "premises_per_article": 4,
    "max_pairs": 48,
    "min_sentence_similarity": 0.30,
    "support": {"min_prob": 0.60, "min_margin": 0.30, "min_coverage": 0.50},
    "refute": {"min_prob": 0.70, "min_margin": 0.40, "min_coverage": 0.60, "min_similarity": 0.45},
    "numeric_mismatch_min_contradiction": 0.40,
    "mixed_delta": 0.10,
    "weights": {"encyclopedia": 1.0, "primary": 1.0, "factCheck": 1.1, "journalism": 0.8},
    "partial_weight": 0.5,
    "divergence_ratio": 0.6,
    "divergence_min_side": 0.9,
    "divergence_min_origins": 2,
    "balanced_ratio": 0.85,
    "single_origin_min": 0.85,
    "decide_min": 0.6,
    "debunk_guard": True,
}


# ---- claim features --------------------------------------------------------------------
def _stem(t: str) -> str:
    return t[:5] if len(t) > 5 and not t.isdigit() else t


def content_terms(text: str) -> list[str]:
    out = []
    for t in tu.terms(text):
        if t in STOPWORDS or (len(t) < 3 and not t.isdigit()):
            continue
        out.append(t)
    return list(dict.fromkeys(out))


def key_terms(claim: str) -> list[str]:
    """Named entities (capitalized, excluding the first word) and numbers."""
    words = re.findall(r"[\wÀ-ÿ]+", claim)
    keys = [w for i, w in enumerate(words) if (i > 0 and w[:1].isupper()) or w.isdigit()]
    if words and words[0][:1].isupper() and tu.folded(words[0]) not in STOPWORDS:
        keys.insert(0, words[0])
    return list(dict.fromkeys(tu.folded(k) for k in keys))


_RARITY = None


def rarity(term: str) -> float:
    """Negative unigram log-probability of the XLM-R pieces: higher = rarer/more specific."""
    global _RARITY
    if _RARITY is None:
        import json
        data = json.loads((models.TOKENIZERS / "EmbeddingsTokenizer.json").read_text())
        _RARITY = {piece: score for piece, score in data["model"]["vocab"]}
    tok = models.embeddings().tok
    return -sum(_RARITY.get(p, -20.0) for p in tok.encode(" " + term, add_special_tokens=False).tokens)


def anchor_terms(claim: str, k: int = 2) -> list[str]:
    """The k most specific non-name content words (rarity measured on the original spelling)."""
    words = {}
    names = set(key_terms(claim))
    for w in re.findall(r"[\wÀ-ÿ]+", claim):
        f = tu.folded(w)
        if f in STOPWORDS or len(f) < 3 or f.isdigit() or f in words or f in names:
            continue
        words[f] = rarity(w.lower())
    return sorted(words, key=lambda t: -words[t])[:k]


def clean_premise(text: str) -> str:
    for pat in BOILERPLATE:
        text = pat.sub("", text).strip()
    return text


def competitor_names(text: str, names: list[str]) -> list[str]:
    """Capitalized tokens of the passage that are not names of the claim (another subject)."""
    out = []
    for w in re.findall(r"[\wÀ-ÿ]+", text):
        f = tu.folded(w)
        if w[:1].isupper() and len(f) >= 3 and f not in names and f not in STOPWORDS and f not in STARTERS:
            out.append(f)
    return out


def subject_first(names: list[str], anchors: list[str], text: str) -> bool:
    """The claim's subject (first name) appears before its predicate in the passage."""
    if not names or not anchors:
        return True
    toks = tu.terms(text)
    try:
        subj = toks.index(names[0])
    except ValueError:
        return False
    stems = [_stem(t) for t in toks]
    pred = [i for i, st in enumerate(stems) if st in {_stem(a) for a in anchors}]
    return not pred or subj < min(pred)


def numbers(text: str) -> list[str]:
    return NUMBER.findall(text)


def coverage(claim_terms: list[str], passage: str) -> float:
    if not claim_terms:
        return 0.0
    stems = {_stem(t) for t in tu.terms(passage)}
    return sum(_stem(t) in stems for t in claim_terms) / len(claim_terms)


def numeric_mismatch(claim: str, passage: str, keys: list[str]) -> bool:
    """Same entities, but the claim's number is absent and another number of the same shape appears."""
    nums = [n for n in NUMBER.findall(claim)]
    if not nums:
        return False
    names = [k for k in keys if not k.isdigit()]
    if names and coverage(names, passage) < 1.0:
        return False
    pnums = NUMBER.findall(passage)
    for n in nums:
        if n in pnums:
            continue
        same_shape = [x for x in pnums if len(x) == len(n) and (len(n) != 4 or x[:2] in ("18", "19", "20"))]
        if same_shape:
            return True
    return False


# ---- analysis: sentence-level premises ----------------------------------------------------
def premises_for(article: dict, claim: str, claim_vec, policy) -> list[dict]:
    emb = models.embeddings()
    windows = analysis.windows_for(article["text"], claim)
    sents = []
    if article.get("title"):
        sents.append(("title", clean_premise(article["title"].strip())))
    if windows:
        top = analysis.select_top(claim, windows, claim_vec)
        idxs = sorted({i for i, _ in top} | {min(len(windows) - 1, i + 1) for i, _ in top})
        for i in idxs:
            ss = [clean_premise(x) for x in tu.sentences(windows[i])]
            for k, s in enumerate(ss):
                if PRONOUN_START.match(s) and k > 0:
                    s = ss[k - 1] + " " + s
                sents.append(("body", s))
    seen, scored = set(), []
    lexical = tu.bm25(claim, [s for _, s in sents]) if sents else []
    for (where, s), lex in zip(sents, lexical):
        key = " ".join(s.split())
        # Questions and multiple-choice options do not assert anything.
        if key in seen or len(key) < 25 or key.rstrip(' "”»\'').endswith("?") or OPTION.match(key):
            continue
        seen.add(key)
        sim = emb.cosine(claim_vec, emb.embed(key))
        scored.append({"text": key, "where": where, "similarity": round(sim, 4), "lexical": round(lex, 3)})
    scored = [x for x in scored if x["similarity"] >= policy["min_sentence_similarity"] or x["lexical"] > 0]
    scored.sort(key=lambda x: -(x["similarity"] + 0.05 * min(x["lexical"], 6)))
    return scored[: policy["premises_per_article"]]


def analyze_sentences(ctx: dict, articles: list[dict], policy=DEFAULT_POLICY) -> dict:
    nli, emb = models.nli(), models.embeddings()
    claim = ctx["text"]
    claim_vec = emb.embed(claim)
    sources, previous, pairs, exhausted = [], [], 0, False
    for art in sorted(articles, key=lambda a: a["partial"]):
        key = tu.canonical_url(art.get("canonical") or art["final_url"])
        dup = next((s for s, a in previous if tu.canonical_url(a.get("canonical") or a["final_url"]) == key
                    or analysis.near_duplicate(a["text"], art["text"])), None)
        domain = p.matched_domain(art["url"]) or art.get("domain") or ""
        if dup:
            sources.append({**dup, "url": art["final_url"], "domain": domain, "duplicate_of": dup["url"]})
            continue
        passages = []
        for prem in premises_for(art, claim, claim_vec, policy):
            if pairs >= policy["max_pairs"]:
                exhausted = True
                break
            pairs += 1
            logits, probs = nli.predict(prem["text"], claim)
            passages.append({**prem, "probs": probs.as_dict(), "logits": [round(x, 4) for x in logits]})
        if not passages:
            continue
        align = tu.alignment(ctx, art["published"], " ".join(x["text"] for x in passages))
        kind = art.get("kind") or p.source_kind(domain)
        src = {"url": art["final_url"], "domain": domain, "title": art["title"], "kind": kind,
               "provenance": art["provenance"], "partial": art["partial"], "alignment": align,
               "published": art["published"].isoformat() if art["published"] else None,
               "origin": art.get("original") or p.editorial_origin(domain), "duplicate_of": None,
               "passages": passages}
        sources.append(src)
        previous.append((src, art))
    return {"sources": sources, "pairs": pairs, "pair_budget_exhausted": exhausted, "ctx_kind": ctx["kind"],
            "claim": claim}


ANALYZERS = {"sentence": analyze_sentences}


# ---- scoring & aggregation -----------------------------------------------------------------
def name_coverage(names: list[str], passage: str) -> float:
    """Exact (folded) token match: 'Brasil' must not match 'brasileiro', nor 'Brasília'."""
    if not names:
        return 1.0
    tokens = set(tu.terms(passage))
    return sum(n in tokens for n in names) / len(names)


def claim_features(claim: str) -> dict:
    keys = key_terms(claim)
    names = [k for k in keys if not k.isdigit()]
    nonname = [t for t in content_terms(claim) if not t.isdigit() and t not in names]
    return {"terms": content_terms(claim), "keys": keys, "names": names, "numbers": numbers(claim),
            "anchors": anchor_terms(claim), "nonname": nonname,
            "terms_no_numbers": [t for t in content_terms(claim) if not t.isdigit()]}


def score_passage(claim: str, ps: dict, policy, feats=None) -> dict:
    f = feats or claim_features(claim)
    pr, text = ps["probs"], ps["text"]
    cov = coverage(f["terms"], text)
    names_cov = name_coverage(f["names"], text)
    anchors_cov = coverage(f["anchors"], text) if f["anchors"] else 1.0
    nonname_cov = coverage(f["nonname"], text) if f["nonname"] else 0.0
    pnums = numbers(text)
    nums_present = all(n in pnums for n in f["numbers"])
    ftext = tu.folded(text)
    debunk = bool(DEBUNK.search(ftext))
    reported = bool(REPORTED.search(ftext))
    ranked = bool(SUPERLATIVE.search(tu.folded(claim))) and not RANKED.search(tu.folded(claim)) and bool(RANKED.search(ftext))
    s, r = policy["support"], policy["refute"]
    sup = ref = 0.0
    why = []
    if (pr["entailment"] >= s["min_prob"] and pr["entailment"] - pr["contradiction"] >= s["min_margin"]
            and cov >= s["min_coverage"] and names_cov == 1.0 and nums_present
            and (anchors_cov > 0 or pr["entailment"] >= s.get("no_anchor_min_prob", 0.97))):
        if policy.get("debunk_guard") and debunk:
            why.append("support_blocked_debunk")
        elif reported:
            why.append("support_blocked_reported")
        elif ranked:
            why.append("support_blocked_ranked")
        else:
            sup = pr["entailment"]
    # Shape A: same subject, conflicting attribute. Shape B: same full predicate, another subject
    # (superlatives/unique roles: "Júpiter é o maior planeta" refutes "Marte é o maior planeta").
    shape_a = names_cov == 1.0 and nums_present and (anchors_cov == 1.0 or len(f["nonname"]) <= 2)
    negated = bool(NEGATION.search(ftext)) and not NEGATION.search(tu.folded(claim))
    shape_a = shape_a and (subject_first(f["names"], f["anchors"], text) or negated)
    # Direct denial: the same names and most of the claim's words, negated.
    shape_a = shape_a or (names_cov == 1.0 and nums_present and negated and cov >= r["min_coverage"]
                          and not HEDGE.search(ftext))
    shape_b = (names_cov < 1.0 and nums_present and f["nonname"] and nonname_cov == 1.0
               and bool(competitor_names(text, f["names"])))
    nli_refutes = (pr["contradiction"] >= r["min_prob"] and pr["contradiction"] - pr["entailment"] >= r["min_margin"]
                   and ps.get("similarity", 0) >= r["min_similarity"])
    mismatch = (f["numbers"] and not nums_present and names_cov == 1.0
                and coverage(f["terms_no_numbers"], text) >= policy.get("mismatch_min_coverage", 1.0)
                and numeric_mismatch(claim, text, f["keys"]))
    if nli_refutes and (shape_a or shape_b):
        ref = pr["contradiction"]
        why.append("shape_a" if shape_a else "shape_b")
        # Explicit denial of the same proposition is the most direct evidence available.
        if (shape_a and NEGATION.search(ftext) and not HEDGE.search(ftext)
                and not NEGATION.search(tu.folded(claim))):
            ref *= policy.get("explicit_negation_boost", 1.3)
            why.append("explicit_negation")
    elif mismatch and pr["contradiction"] >= policy["numeric_mismatch_min_contradiction"]:
        ref = max(pr["contradiction"], 0.75)
        why.append("numeric_mismatch")
    elif policy.get("debunk_guard") and debunk and shape_a and pr["entailment"] < 0.5 and cov >= r["min_coverage"]:
        ref = 0.7
        why.append("debunk_marker")
    elif ranked and names_cov == 1.0 and coverage(f["nonname"], text) >= 0.5 and pr["entailment"] >= 0.5:
        ref = 0.8
        why.append("rank_mismatch")
    return {"support": round(sup, 4), "refute": round(ref, 4), "coverage": round(cov, 3), "reported": reported,
            "names": round(names_cov, 3), "anchors": round(anchors_cov, 3), "why": why}


def aggregate(sources: list[dict], ctx_kind: str = "timeless", policy=None, claim: str | None = None):
    policy = policy or DEFAULT_POLICY
    if not sources:
        return "NAO_ENCONTRADO", []
    claim = claim or sources[0].get("claim")
    feats = claim_features(claim)
    by_origin: dict[str, dict] = {}
    votes = []
    for src in sources:
        if src.get("duplicate_of") or src["alignment"] == "incompatible":
            continue
        full = analysis.eligible(src)
        if src["kind"] == "encyclopedia" and ctx_kind in ("current", "recent"):
            full = False
        w = policy["weights"].get(src["kind"], 0.8) * (1.0 if full else policy["partial_weight"])
        best_s = best_r = 0.0
        for ps in src["passages"]:
            sc = score_passage(claim, ps, policy, feats)
            best_s, best_r = max(best_s, sc["support"]), max(best_r, sc["refute"])
            for lab, val in (("entailment", sc["support"]), ("contradiction", sc["refute"])):
                if val > 0:
                    votes.append({"label": lab, "score": val, "confidence": val, "origin": src["origin"],
                                  "url": src["url"], "full": full, "text": ps["text"][:200], "why": sc["why"]})
        # A fact-check that quotes the circulating claim and labels it false refutes it.
        # Fact-check titles state the verdict; their support for the claim is the quoted hoax.
        title = tu.folded(src.get("title") or "")
        fact_check = src["kind"] == "factCheck"
        article_debunks = bool(DEBUNK.search(title)) or any(DEBUNK.search(tu.folded(ps["text"])) for ps in src["passages"]) or (
            fact_check and bool(NEGATION.search(title)) and not NEGATION.search(tu.folded(claim)))
        if fact_check and article_debunks:
            best_s = 0.0
            votes = [v for v in votes if not (v["url"] == src["url"] and v["label"] == "entailment")]
        if article_debunks and best_s == 0:
            for ps in src["passages"]:
                sc = score_passage(claim, ps, policy, feats)
                if (sc["reported"] or fact_check) and sc["names"] == 1.0 and sc["coverage"] >= 0.6:
                    best_r = max(best_r, policy.get("debunked_report_score", 0.8))
                    votes.append({"label": "contradiction", "score": best_r, "confidence": best_r, "origin": src["origin"],
                                  "url": src["url"], "full": full, "text": ps["text"][:200], "why": ["debunked_report"]})
                    break
        if best_s and best_r and min(best_s, best_r) < policy.get("mixed_min", 0.9):
            best_s, best_r = (best_s, 0.0) if best_s >= best_r else (0.0, best_r)
        o = by_origin.setdefault(src["origin"], {"s": 0.0, "r": 0.0, "full_s": False, "full_r": False})
        if best_s * w > o["s"]:
            o["s"] = best_s * w
        if best_r * w > o["r"]:
            o["r"] = best_r * w
        o["full_s"] |= full and best_s > 0
        o["full_r"] |= full and best_r > 0
    S = sum(o["s"] for o in by_origin.values())
    R = sum(o["r"] for o in by_origin.values())
    n_s = sum(o["s"] > 0 for o in by_origin.values())
    n_r = sum(o["r"] > 0 for o in by_origin.values())
    full_s = any(o["full_s"] for o in by_origin.values())
    full_r = any(o["full_r"] for o in by_origin.values())
    votes.sort(key=lambda v: -v["score"])
    if S < policy["decide_min"] * 0.5 and R < policy["decide_min"] * 0.5:
        return "SEM_INFORMACAO", votes
    hi, lo = max(S, R), min(S, R)
    n_lo = n_r if S >= R else n_s
    if lo >= policy["divergence_min_side"] and lo >= policy["divergence_ratio"] * hi and n_lo >= policy.get("divergence_min_origins", 2):
        return "DIVERGENTE", votes
    # A near tie between complete sources is a real conflict even with one origin per side.
    if full_s and full_r and lo >= policy["decide_min"] and lo >= policy.get("balanced_ratio", 0.85) * hi:
        return "DIVERGENTE", votes
    side_s = S >= R
    score, n, full = (S, n_s, full_s) if side_s else (R, n_r, full_r)
    if not full or score < policy["decide_min"]:
        return "SEM_INFORMACAO", votes
    if n == 1 and score < policy["single_origin_min"] * min(policy["weights"].values()):
        return "SEM_INFORMACAO", votes
    return ("CONFIRMADO" if side_s else "CONTRADITO"), votes
