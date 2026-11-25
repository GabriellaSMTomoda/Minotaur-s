"""Wikipedia PT as an encyclopedic source (free API). Mirrors the planned Worker `/wiki` route."""
from __future__ import annotations

import re

import evidence
import netcache
import textutil as tu

API = "https://pt.wikipedia.org/w/api.php"


def wiki_query(claim: str) -> list[str]:
    terms = [t for t in re.findall(r"[\wÀ-ÿ]+", claim) if tu.folded(t) not in evidence.STOPWORDS and len(t) > 2]
    full = " ".join(terms)
    keys = [t for i, t in enumerate(re.findall(r"[\wÀ-ÿ]+", claim)) if t[:1].isupper() or t.isdigit()]
    out = [full]
    if keys and " ".join(keys) != full:
        out.append(" ".join(keys))
    return [q for q in out if q][:2]


def collect_wiki(ctx: dict, pages: int = 2) -> list[dict]:
    ids: list[int] = []
    for q in wiki_query(ctx["text"]):
        res = netcache.wiki(API, {"action": "query", "list": "search", "srsearch": q, "srlimit": 3,
                                  "format": "json", "utf8": 1})
        for hit in res.get("query", {}).get("search", []):
            if hit["pageid"] not in ids:
                ids.append(hit["pageid"])
        if len(ids) >= pages:
            break
    ids = ids[:pages]
    if not ids:
        return []
    out = []
    for pid in ids:
        # Full-text extracts are served one page per request (exlimit=1 without exintro).
        res = netcache.wiki(API, {"action": "query", "prop": "extracts|info", "explaintext": 1, "exsectionformat": "plain",
                                  "inprop": "url", "pageids": str(pid), "format": "json", "utf8": 1})
        page = res.get("query", {}).get("pages", {}).get(str(pid))
        if not page or not page.get("extract"):
            continue
        text = page["extract"][:20000]
        text = "\n".join(l.strip() for l in text.splitlines() if len(l.strip()) > 30)
        out.append({"url": page["fullurl"], "final_url": page["fullurl"], "title": page["title"], "text": text,
                    "published": None, "provenance": "articleBody", "partial": False, "canonical": page["fullurl"],
                    "original": None, "domain": "pt.wikipedia.org", "kind": "encyclopedia"})
    return out
