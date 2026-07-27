"""
Spike 4 — estabilidade do scraping de html.duckduckgo.com com queries
restritas por `site:` ... `OR` ... aos domínios da allowlist (RF-02.3).

Duas fases:
  A) domain_limit_test  — mesma keyword-query, número crescente de
     domínios no OR, para achar empiricamente até quantos `site:` cabem
     numa query antes de degradar (item 4 da tarefa).
  B) stability_test      — 20 buscas distintas (temas variados, ver
     queries.py), espaçadas no tempo, usando o limite de domínios
     encontrado na fase A (ou todos os 30, se a fase A não mostrar
     degradação).

Se qualquer sinal de bloqueio (CAPTCHA, 429, HTML de "unusual traffic")
aparecer, o script para imediatamente e grava o que já tiver.

Código descartável, isolado do app iOS — não decide biblioteca Swift,
não implementa nada do app.
"""
import json
import random
import re
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

from domains import TRUSTED_DOMAINS
from queries import CLAIMS, extract_keywords

ENDPOINT = "https://html.duckduckgo.com/html/"
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

BLOCK_MARKERS = [
    "unusual traffic",
    "captcha",
    "verify you are a human",
    "are you a robot",
    "automated queries",
    "anomaly",
    "blocked",
    "access denied",
    "rate limit",
]

RESULT_LINK_RE = re.compile(r'class="result__a"[^>]*href="([^"]+)"')


def looks_blocked(status_code, text):
    if status_code in (403, 429, 503):
        return True, f"HTTP {status_code}"
    if status_code != 200:
        return True, f"HTTP {status_code} inesperado"
    low = text.lower()
    for marker in BLOCK_MARKERS:
        if marker in low:
            return True, f"marcador de bloqueio no corpo: '{marker}'"
    if len(text) < 1500:
        return True, f"corpo suspeito pequeno ({len(text)} bytes)"
    return False, None


def do_search(query: str):
    t0 = time.time()
    resp = requests.get(
        ENDPOINT, params={"q": query}, headers=HEADERS, timeout=TIMEOUT
    )
    elapsed = time.time() - t0
    blocked, block_reason = looks_blocked(resp.status_code, resp.text)
    hrefs = RESULT_LINK_RE.findall(resp.text) if not blocked else []
    hosts = []
    for href in hrefs:
        try:
            host = urlparse(href).netloc.lower()
            if host.startswith("www."):
                host = host[4:]
            hosts.append(host)
        except Exception:
            pass
    return {
        "query": query,
        "status_code": resp.status_code,
        "elapsed_s": round(elapsed, 2),
        "body_len": len(resp.text),
        "blocked": blocked,
        "block_reason": block_reason,
        "result_count": len(hrefs),
        "result_hosts": hosts,
    }


def host_in_allowlist(host: str, allowlist):
    return any(host == d or host.endswith("." + d) for d in allowlist)


def sleep_like_a_human():
    delay = random.uniform(10, 25)
    print(f"    (aguardando {delay:.1f}s antes da próxima busca)")
    time.sleep(delay)


def phase_a_domain_limit_test():
    """Mesma keyword-query, aumentando o número de domínios no OR."""
    print("\n=== FASE A — limite prático de domínios por query (site: OR) ===")
    base_query = extract_keywords(CLAIMS[0])
    counts_to_try = [3, 5, 8, 12, 16, 20, 25, 30]
    rows = []
    for n in counts_to_try:
        subset = TRUSTED_DOMAINS[:n]
        site_clause = " OR ".join(f"site:{d}" for d in subset)
        query = f"{base_query} {site_clause}"
        print(f"\n[A] n_domains={n} query_len={len(query)} chars")
        result = do_search(query)
        result["n_domains"] = n
        result["query_len"] = len(query)
        matched = [h for h in result["result_hosts"] if host_in_allowlist(h, subset)]
        result["hosts_matching_subset"] = len(matched)
        result["hosts_total"] = len(result["result_hosts"])
        rows.append(result)

        status = "BLOQUEADO" if result["blocked"] else "ok"
        print(
            f"    status={result['status_code']} {status} "
            f"resultados={result['result_count']} "
            f"dentro_do_subset={result['hosts_matching_subset']}/{result['hosts_total']} "
            f"tempo={result['elapsed_s']}s"
        )
        if result["blocked"]:
            print(f"    !!! BLOQUEIO DETECTADO: {result['block_reason']} — parando fase A")
            return rows, True

        sleep_like_a_human()

    return rows, False


def phase_b_stability_test(max_domains: int):
    print(f"\n=== FASE B — 20 buscas distintas (max_domains={max_domains}) ===")
    subset = TRUSTED_DOMAINS[:max_domains]
    rows = []
    for i, claim in enumerate(CLAIMS, start=1):
        keywords = extract_keywords(claim)
        site_clause = " OR ".join(f"site:{d}" for d in subset)
        query = f"{keywords} {site_clause}"
        print(f"\n[B {i}/20] claim: {claim[:70]}...")
        result = do_search(query)
        result["claim"] = claim
        result["keywords"] = keywords
        matched = [h for h in result["result_hosts"] if host_in_allowlist(h, TRUSTED_DOMAINS)]
        result["hosts_matching_allowlist"] = len(matched)
        result["hosts_total"] = len(result["result_hosts"])
        rows.append(result)

        status = "BLOQUEADO" if result["blocked"] else "ok"
        print(
            f"    status={result['status_code']} {status} "
            f"resultados={result['result_count']} "
            f"na_allowlist={result['hosts_matching_allowlist']}/{result['hosts_total']} "
            f"tempo={result['elapsed_s']}s"
        )
        if result["blocked"]:
            print(f"    !!! BLOQUEIO DETECTADO: {result['block_reason']} — parando fase B")
            return rows, True

        if i < len(CLAIMS):
            sleep_like_a_human()

    return rows, False


def main():
    all_data = {"phase_a": [], "phase_b": [], "stopped_early": False, "stop_reason": None}

    phase_a_rows, blocked_a = phase_a_domain_limit_test()
    all_data["phase_a"] = phase_a_rows

    if blocked_a:
        all_data["stopped_early"] = True
        all_data["stop_reason"] = "bloqueio detectado na fase A"
        Path("results.json").write_text(json.dumps(all_data, ensure_ascii=False, indent=2))
        print("\nParando após bloqueio na fase A. Resultados parciais salvos em results.json.")
        return

    # Determina o maior n testado sem degradação de allowlist-match na fase A
    safe_n = 30
    for row in phase_a_rows:
        if row["hosts_total"] > 0:
            match_rate = row["hosts_matching_subset"] / row["hosts_total"]
            if match_rate < 0.5:
                safe_n = max(3, row["n_domains"] - 1)
                break

    phase_b_rows, blocked_b = phase_b_stability_test(max_domains=safe_n)
    all_data["phase_b"] = phase_b_rows
    all_data["safe_n_domains_used_in_phase_b"] = safe_n

    if blocked_b:
        all_data["stopped_early"] = True
        all_data["stop_reason"] = "bloqueio detectado na fase B"

    Path("results.json").write_text(json.dumps(all_data, ensure_ascii=False, indent=2))
    print("\nConcluído. Resultados em results.json.")


if __name__ == "__main__":
    main()
