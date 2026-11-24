"""Network access for the harness with a permanent on-disk cache.

Search goes through the project's Worker using the evaluation lane (`X-Evaluation-Key`,
200 credits/month). Every response and every downloaded HTML page is cached under
`evaluation/snapshots/` (git-ignored) so re-runs cost zero credits.
"""
from __future__ import annotations

import hashlib
import json
import os
import ssl
import time
import urllib.error
import urllib.request
from pathlib import Path

import truststore

truststore.inject_into_ssl()

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOTS = ROOT / "snapshots"
PROXY = "https://minotaurs-tavily-proxy.hen-lac-sil.workers.dev"
KEY_PATH = Path.home() / "Library/Application Support/Minotaur-s/credentials/evaluation-key"
UA_ARTICLE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
UA_HARNESS = "MinotaursHarness/0.1"
OFFLINE = os.environ.get("HARNESS_OFFLINE") == "1"


class OfflineMiss(Exception):
    pass


def _key() -> str:
    return KEY_PATH.read_text().strip()


def _digest(payload) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:24]


def _cached(kind: str, payload, fetch, keep=lambda data: True):
    path = SNAPSHOTS / kind / f"{_digest(payload)}.json"
    if path.exists():
        return json.loads(path.read_text())
    if OFFLINE:
        raise OfflineMiss(f"{kind}: {payload}")
    data = fetch()
    if not keep(data):  # transient failures are returned but never cached
        return {"request": payload, "response": data}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"request": payload, "response": data, "fetched_at": time.time()}, ensure_ascii=False))
    return json.loads(path.read_text())


def usage() -> dict:
    req = urllib.request.Request(PROXY + "/_admin/usage", headers={"X-Evaluation-Key": _key(), "User-Agent": UA_HARNESS})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def search(body: dict) -> dict:
    """POST to the Worker exactly like `TavilySearchService.perform`, cached by body."""
    def fetch():
        req = urllib.request.Request(PROXY, data=json.dumps(body).encode(), method="POST",
                                     headers={"Content-Type": "application/json", "X-Evaluation-Key": _key(), "User-Agent": UA_HARNESS})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return {"status": r.status, "json": json.loads(r.read())}
        except urllib.error.HTTPError as e:
            return {"status": e.code, "json": None, "error": e.headers.get("X-Search-Error")}
    return _cached("search", body, fetch, keep=lambda d: d["status"] == 200)["response"]


def wiki(endpoint: str, params: dict) -> dict:
    """Direct Wikipedia API call (free). Used until the Worker `/wiki` route exists."""
    import urllib.parse
    import time
    import urllib.error
    def fetch():
        url = endpoint + "?" + urllib.parse.urlencode({**params, "maxlag": 5})
        req = urllib.request.Request(url, headers={"User-Agent": "MinotaursHarness/0.1 (development evaluation)",
                                                   "Accept-Encoding": "identity"})
        for attempt in range(5):
            time.sleep(1.0)  # serial and throttled, as the Wikimedia API etiquette asks
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    return json.loads(r.read())
            except urllib.error.HTTPError as e:
                if e.code != 429 or attempt == 4:
                    raise
                time.sleep(float(e.headers.get("Retry-After") or 10 * (attempt + 1)))
    return _cached("wiki", {"endpoint": endpoint, **params}, fetch)["response"]


def html(url: str) -> dict:
    """Downloads an article like `ArticleExtractor.extract` (3 MiB cap, final URL kept)."""
    def fetch():
        req = urllib.request.Request(url, headers={"User-Agent": UA_ARTICLE, "Accept-Language": "pt-BR,pt;q=0.9"})
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                raw = r.read(3 * 1024 * 1024 + 1)
                if len(raw) > 3 * 1024 * 1024:
                    return {"status": r.status, "final_url": r.geturl(), "html": None, "error": "too_large"}
                enc = (r.headers.get("Content-Encoding") or "").lower()
                if raw[:2] == b"\x1f\x8b" or enc == "gzip":
                    import gzip
                    raw = gzip.decompress(raw)
                elif enc == "deflate":
                    import zlib
                    raw = zlib.decompress(raw)
                elif enc == "br":
                    return {"status": r.status, "final_url": r.geturl(), "html": None, "error": "brotli"}
                charset = r.headers.get_content_charset() or "utf-8"
                return {"status": r.status, "final_url": r.geturl(), "html": raw.decode(charset, errors="replace")}
        except urllib.error.HTTPError as e:
            return {"status": e.code, "final_url": url, "html": None, "error": "http"}
        except Exception as e:  # noqa: BLE001 - network failures are data here
            return {"status": 0, "final_url": url, "html": None, "error": type(e).__name__}
    return _cached("html", {"url": url}, fetch)["response"]
