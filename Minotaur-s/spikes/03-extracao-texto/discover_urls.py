"""
Descobre URLs reais de artigo/notícia para cada domínio da allowlist, a partir
da homepage/seção de notícias (SEED_PAGES em domains.py).

Heurística: baixa a seed page, extrai todos os <a href>, filtra para links que
parecem ser de matéria individual (mesmo domínio/subdomínio, path com slug
longo e/ou dígitos típicos de ID/data), deduplica e pega os N primeiros.

Isso é só para achar candidatos reais e atuais (não inventados) sem precisar
de busca manual em 34 sites. Uso único, resultado salvo em urls.json — as
rodadas de download/extração usam o urls.json congelado, não este script de
novo (para não re-sortear URLs a cada execução).
"""
import json
import re
import time
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

from domains import SEED_PAGES

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
}

N_PER_DOMAIN = 3

# paths/termos que indicam NÃO ser matéria (seções, busca, login, vídeo puro, etc)
EXCLUDE_PATTERNS = re.compile(
    r"(/tag/|/tags/|/busca|/search|/login|/assine|/assinatura|/newsletter|"
    r"/video/|/videos/|/podcast|/ao-vivo|/live|#|javascript:|/sobre|"
    r"/politica-de-privacidade|/termos|/contato|mailto:|\.pdf$|\.jpg$|\.png$)",
    re.I,
)

# indício de matéria: slug com várias palavras separadas por hífen, ou dígitos
# longos (id numérico), ou padrão de data /2026/07/ ou /2026-07-
ARTICLE_HINT = re.compile(r"(-.*-.*-)|(\d{5,})|(/20\d{2}[/-]\d{1,2}[/-])")


def base_domain(host: str) -> str:
    parts = host.split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else host


def same_family(link_host: str, seed_domain: str) -> bool:
    lh = link_host.lower().lstrip("www.")
    sd = seed_domain.lower().lstrip("www.")
    return lh == sd or lh.endswith("." + sd) or sd.endswith("." + lh) or base_domain(lh) == base_domain(sd)


def discover(domain: str, seed_url: str):
    try:
        resp = requests.get(seed_url, headers=HEADERS, timeout=15)
        resp.raise_for_status()
    except Exception as exc:
        return [], f"ERRO ao baixar seed: {exc}"

    soup = BeautifulSoup(resp.text, "lxml")
    candidates = []
    seen = set()
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if not href or EXCLUDE_PATTERNS.search(href):
            continue
        full = urljoin(seed_url, href)
        parsed = urlparse(full)
        if parsed.scheme not in ("http", "https"):
            continue
        if not same_family(parsed.netloc, domain):
            continue
        if full in seen:
            continue
        path = parsed.path
        if len(path.strip("/")) < 8:
            continue
        if not ARTICLE_HINT.search(path):
            continue
        seen.add(full)
        candidates.append(full)

    return candidates[:N_PER_DOMAIN], None


def main():
    result = {}
    for domain, seed in SEED_PAGES.items():
        urls, err = discover(domain, seed)
        result[domain] = {"seed": seed, "urls": urls, "error": err}
        print(f"{domain:30s} -> {len(urls)} candidatos" + (f" ({err})" if err else ""))
        time.sleep(0.5)

    with open("urls_discovered.json", "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
