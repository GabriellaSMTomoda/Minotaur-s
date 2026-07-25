"""Script de uso único para inspecionar manualmente páginas de seção e achar
URLs de artigo de verdade nos domínios em que o discover_urls.py não achou
bons candidatos (páginas de categoria/hub em vez de matéria individual)."""
import sys
import requests
from bs4 import BeautifulSoup

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8",
}

url = sys.argv[1]
verify = "--no-verify" not in sys.argv
try:
    r = requests.get(url, headers=HEADERS, timeout=15, verify=verify)
    print(url, "->", r.status_code, len(r.text))
    soup = BeautifulSoup(r.text, "lxml")
    hrefs = sorted(set(a["href"] for a in soup.find_all("a", href=True) if a["href"].startswith("http") or a["href"].startswith("/")))
    for h in hrefs:
        print("  ", h)
except Exception as e:
    print(url, "ERR", e)
