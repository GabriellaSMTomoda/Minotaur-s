"""
Baixa o HTML de cada URL em urls.py com um User-Agent realista de navegador.
Salva em html/<domain>/<index>.html e um manifest.json com status/tempo/erro
por URL — inclusive falhas (bloqueio, timeout, etc), que são dado relevante
do spike, não um "erro do spike".
"""
import hashlib
import json
import time
from pathlib import Path

import requests

from urls import URLS

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
}

TIMEOUT = 15
OUT_DIR = Path("html")
OUT_DIR.mkdir(exist_ok=True)


def slug(url: str) -> str:
    return hashlib.sha1(url.encode()).hexdigest()[:10]


def main():
    manifest = []
    for domain, urls in URLS.items():
        domain_dir = OUT_DIR / domain
        domain_dir.mkdir(parents=True, exist_ok=True)
        for url in urls:
            entry = {"domain": domain, "url": url}
            t0 = time.time()
            try:
                resp = requests.get(url, headers=HEADERS, timeout=TIMEOUT, allow_redirects=True)
                elapsed = time.time() - t0
                entry["status_code"] = resp.status_code
                entry["elapsed_s"] = round(elapsed, 2)
                entry["final_url"] = resp.url
                entry["content_length"] = len(resp.text)
                if resp.status_code == 200 and len(resp.text) > 0:
                    fname = f"{slug(url)}.html"
                    (domain_dir / fname).write_text(resp.text, encoding="utf-8", errors="replace")
                    entry["html_file"] = str(domain_dir / fname)
                    entry["error"] = None
                else:
                    entry["html_file"] = None
                    entry["error"] = f"HTTP {resp.status_code}"
            except Exception as exc:
                elapsed = time.time() - t0
                entry["status_code"] = None
                entry["elapsed_s"] = round(elapsed, 2)
                entry["final_url"] = None
                entry["content_length"] = 0
                entry["html_file"] = None
                entry["error"] = f"{type(exc).__name__}: {exc}"

            manifest.append(entry)
            status = entry.get("status_code")
            err = entry.get("error")
            print(f"{domain:28s} {status!s:5s} {entry['elapsed_s']:6.2f}s  {url[:80]}" + (f"  ERRO: {err}" if err else ""))
            time.sleep(0.3)

    with open("download_manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    ok = sum(1 for e in manifest if e["error"] is None)
    print(f"\n{ok}/{len(manifest)} downloads OK")


if __name__ == "__main__":
    main()
