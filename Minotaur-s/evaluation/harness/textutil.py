"""Ports of the Swift text utilities (ClaimAnalyzer, HybridRetrieval, TextChunker, filters)."""
from __future__ import annotations

import math
import re
import unicodedata
from datetime import date, datetime, timedelta
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode


def folded(text: str) -> str:
    nfkd = unicodedata.normalize("NFD", text)
    return "".join(c for c in nfkd if unicodedata.category(c) != "Mn").casefold()


TERM = re.compile(r"[\w]+(?:[.,]\d+)?", re.UNICODE)


def terms(text: str) -> list[str]:
    return [t for t in TERM.findall(folded(text)) if t != "_"]


def bm25(query: str, documents: list[str]) -> list[float]:
    if not documents:
        return []
    tokens = [terms(d) for d in documents]
    q = set(terms(query))
    avg = max(1.0, sum(len(t) for t in tokens) / len(tokens))
    df: dict[str, int] = {}
    for words in tokens:
        for w in set(words):
            df[w] = df.get(w, 0) + 1
    out = []
    n = len(tokens)
    for words in tokens:
        counts: dict[str, int] = {}
        for w in words:
            counts[w] = counts.get(w, 0) + 1
        total = 0.0
        for term in q:
            tf = counts.get(term, 0)
            d = df.get(term, 0)
            idf = math.log(1 + (n - d + 0.5) / (d + 0.5))
            total += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * len(words) / avg))
        out.append(total)
    return out


def fused_order(lexical: list[float], semantic: list[float], min_similarity: float = 0.25) -> list[int]:
    def order(values):
        return sorted(range(len(values)), key=lambda i: (-values[i], i))
    scores = [0.0] * len(lexical)
    for rank, i in enumerate(order(lexical)):
        if lexical[i] > 0:
            scores[i] += 1 / (60 + rank + 1)
    for rank, i in enumerate(order(semantic)):
        if semantic[i] >= min_similarity:
            scores[i] += 1 / (60 + rank + 1)
    return [i for i in order(scores) if scores[i] > 0]


def canonical_url(text: str) -> str:
    try:
        p = urlsplit(text)
    except ValueError:
        return text
    host = (p.hostname or "").lower().replace("www.", "")
    query = [(k, v) for k, v in parse_qsl(p.query) if not (k.startswith("utm_") or k in ("fbclid", "gclid"))]
    return urlunsplit((p.scheme, host, p.path, urlencode(query), "")).strip("/")


# ---- sentences / chunking -------------------------------------------------------------
_ABBREV = {"sr", "sra", "dr", "dra", "prof", "profa", "av", "etc", "ex", "n", "nº", "jr", "st", "vol", "pág", "cap"}
_SENT_END = re.compile(r"([.!?…]+[\"'”»)]*)\s+(?=[\"'“«(]?[A-ZÁÉÍÓÚÂÊÔÃÕÇ0-9])")


def sentences(text: str) -> list[str]:
    out, start = [], 0
    for m in _SENT_END.finditer(text):
        before = text[start:m.start()].split()
        last = before[-1].lower().strip("(\"'") if before else ""
        if last in _ABBREV or (len(last) == 1 and last.isalpha()):
            continue
        out.append(text[start:m.end(1)].strip())
        start = m.end()
    tail = text[start:].strip()
    if tail:
        out.append(tail)
    return [s for s in out if s]


class TextChunker:
    def __init__(self, max_tokens: int, count):
        self.max = max(1, max_tokens)
        self.count = count

    def chunks(self, text: str) -> list[str]:
        result, overlap = [], None
        for paragraph in [p.strip() for p in text.splitlines() if p.strip()]:
            body = f"{overlap} {paragraph}" if overlap else paragraph
            produced = self._subdivide(body)
            if not produced:
                continue
            result.extend(produced)
            s = sentences(produced[-1])
            overlap = s[-1] if s else None
        return result

    def _subdivide(self, text: str) -> list[str]:
        if not text:
            return []
        if self.count(text) <= self.max:
            return [text]
        sents = sentences(text)
        if len(sents) <= 1:
            return self._by_words(text)
        pieces, current = [], []
        for sentence in sents:
            units = [sentence] if self.count(sentence) <= self.max else self._by_words(sentence)
            for unit in units:
                if not current:
                    current = [unit]
                    continue
                if self.count(" ".join(current + [unit])) <= self.max:
                    current.append(unit)
                    continue
                pieces.append(" ".join(current))
                prev = current[-1]
                current = [prev, unit] if self.count(prev + " " + unit) <= self.max else [unit]
        if current:
            pieces.append(" ".join(current))
        return pieces

    def _by_words(self, text: str) -> list[str]:
        pieces, current = [], []
        for word in text.split():
            if not current:
                current = [word]
            elif self.count(" ".join(current + [word])) <= self.max:
                current.append(word)
            else:
                pieces.append(" ".join(current))
                current = [word]
        if current:
            pieces.append(" ".join(current))
        return pieces


_NAV = [folded(x) for x in ["navegue direto pelo app", "mais lidas", "leia também", "leia mais", "veja também",
                            "continua depois da publicidade", "compartilhe", "últimas notícias", "pular para o conteúdo",
                            "todos os direitos reservados", "receba as principais notícias", "assine a newsletter",
                            "newsletter", "clique aqui", "web stories"]]
_CHROME = [re.compile(p) for p in [r"\bPor\s+[A-ZÁÉÍÓÚÂÊÔÃÕÇ][\w'-]+(?:\s+(?:d[aeo]s?\s+)?[A-ZÁÉÍÓÚÂÊÔÃÕÇ][\w'-]+)*\*?",
                                   r"\b\d{1,2}/\d{1,2}/\d{2,4}\b", r"\b\d{1,2}h\d{2}\b", r"\b\d{1,2}:\d{2}\b",
                                   r"\b(?:Atualizado|Publicado)(?:\s+em)?\b",
                                   r"\b(?:Foto|Fotos|Imagem|Imagens|Crédito|Créditos|Arte|Ilustração|Legenda|Reprodução|Divulgação)\s*:.*$"]]


def chunk_ok(chunk: str) -> bool:
    text = " ".join(chunk.split())
    f = folded(text)
    if f.startswith("title:") or (" | " in text and text[-1:] not in ".!?…"):
        return False
    if any(m in f for m in _NAV):
        return False
    body = text
    for rx in _CHROME:
        body = rx.sub(" ", body)
    body = " ".join(body.split()).strip(" —–-•|,;:")
    return len(body) >= 40 and len(body.split()) >= 5


# ---- claim context (ClaimAnalyzer.context / ClaimContext.alignment) ---------------------
def claim_context(text: str, ref: datetime) -> dict:
    lower = folded(text)
    today = ref.date()
    ctx = {"text": text, "reference": today, "kind": "timeless", "start": None, "end": None}
    if re.search(r"\b(hoje|ontem)\b", lower):
        day = today - timedelta(days=1) if "ontem" in lower else today
        return {**ctx, "kind": "recent", "start": day, "end": day + timedelta(days=1)}
    m = re.search(r"\b(\d{1,2})/(\d{1,2})/(20\d{2}|19\d{2})\b", text)
    if m:
        try:
            start = date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
            return {**ctx, "kind": "historical", "start": start, "end": start + timedelta(days=1)}
        except ValueError:
            pass
    m = re.search(r"\b(?:19|20)\d{2}\b", text)
    if m:
        y = int(m.group(0))
        return {**ctx, "kind": "historical", "start": date(y, 1, 1), "end": date(y + 1, 1, 1)}
    if re.search(r"\b(atualmente|atual|agora|e presidente|preside|ocupa o cargo|esta no cargo)\b", lower):
        return {**ctx, "kind": "current", "start": today - timedelta(days=30), "end": today}
    if re.search(r"\b(recentemente|nesta semana|esta semana|ultimos dias|acabou de)\b", lower):
        return {**ctx, "kind": "recent", "start": today - timedelta(days=7), "end": today}
    return ctx


MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro",
          "novembro", "dezembro"]


def alignment(ctx: dict, published: date | None, text: str) -> str:
    if ctx["kind"] == "timeless":
        return "compatible"
    start, end = ctx["start"], ctx["end"]
    if ctx["kind"] == "historical" and start:
        # A dated past event is discussed long after it happened; the contested element is the
        # date itself, so later (or undated) publications are compatible. An article published
        # before the claimed period only counts when it states dates of its own.
        if published is None or published >= start:
            return "compatible"
        return "compatible" if re.search(r"\b(1[5-9]|20)\d{2}\b", text) else "incompatible"
    if published is None:
        return "unknown"
    if start and published < start:
        return "incompatible"
    if end and published > end:
        return "incompatible"
    return "compatible"


def parse_date(text: str | None) -> date | None:
    if not text:
        return None
    t = text.strip()
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d",
                "%a, %d %b %Y %H:%M:%S %Z", "%a, %d %b %Y %H:%M:%S %z"):
        try:
            return datetime.strptime(t.replace("Z", "+0000") if "%z" in fmt else t, fmt).date()
        except ValueError:
            continue
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", t)
    return date(int(m[1]), int(m[2]), int(m[3])) if m else None
