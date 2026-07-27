"""
Spike 5 — validação técnica do provedor Tavily como substituto do
scraping de html.duckduckgo.com (ver spikes/04-ddg-scraping/RESULTADO.md
e spikes/04b-ddg-urlsession/RESULTADO.md — bloqueio confirmado em 2
clientes HTTP diferentes).

Este NÃO é um spike de decisão de provedor — o provedor (Tavily) já foi
escolhido fora deste repositório. Este spike só confirma, com chamadas
reais à API, se ela se comporta como a documentação promete antes de
autorizar a troca de DT-11/RF-02.3/RF-04 na spec.

Reusa a allowlist de 30 domínios e as 20 afirmações de teste dos Spikes
3/4 (domains.py, queries.py — cópias byte-a-byte, nenhum dataset novo
foi criado).

Quatro fases:
  1) 20 buscas, uma por afirmação, com include_domains = allowlist
     completa (30 domínios de uma vez — exatamente o caso que bloqueou
     no DDG). Registra: resultado obtido, quantidade, hosts dentro da
     allowlist, tempo de resposta, headers relacionados a créditos.
  2) Teste de exclusão: 3 buscas com um domínio FORA da allowlist
     incluído junto dos 30 em include_domains, mais uma busca de
     controle isolada (só o domínio extra) para confirmar que ele tem
     conteúdo indexável sobre o tema — a ausência dele na busca mista
     só é evidência de restrição real se o controle isolado mostrar que
     ele poderia ter aparecido.
  3) Uma busca com query sem sentido, para observar o comportamento de
     "nenhum resultado" (RF-04.4).
  4) Uma busca com chave de API inválida, para observar o formato do
     erro de autenticação (RF-10).

Código descartável, isolado do app iOS (Python). Não decide arquitetura
de proteção de chave de API, não implementa nada do app principal.
"""
import json
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

from domains import TRUSTED_DOMAINS
from queries import CLAIMS

ENDPOINT = "https://api.tavily.com/search"
TIMEOUT = 20
DELAY_BETWEEN_CALLS_S = 1.0

# Domínios fora da allowlist, escolhidos por não serem substring/superstring
# de nenhum dos 30 domínios da allowlist (evita falso positivo de "apareceu
# fora da allowlist" quando na verdade é um subdomínio permitido — ex:
# "uol.com.br" seria ambíguo porque folha.uol.com.br e band.uol.com.br
# ESTÃO na allowlist).
EXCLUSION_TEST_DOMAINS = ["wikipedia.org", "cnn.com", "reuters.com"]


def get_api_key() -> str:
    key = os.environ.get("TAVILY_API_KEY")
    if not key:
        print("ERRO: variável de ambiente TAVILY_API_KEY não definida.")
        print("Rode antes de executar este script:")
        print("    export TAVILY_API_KEY=sua_chave_aqui")
        sys.exit(1)
    return key


def host_of(url: str) -> str:
    try:
        host = urlparse(url).netloc.lower()
        if host.startswith("www."):
            host = host[4:]
        return host
    except Exception:
        return ""


def host_in_allowlist(host: str, allowlist) -> bool:
    return any(host == d or host.endswith("." + d) for d in allowlist)


def do_search(api_key, query, include_domains=None, max_results=5, search_depth="basic"):
    body = {
        "api_key": api_key,
        "query": query,
        "search_depth": search_depth,
        "max_results": max_results,
    }
    if include_domains is not None:
        body["include_domains"] = include_domains

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }

    t0 = time.time()
    try:
        resp = requests.post(ENDPOINT, json=body, headers=headers, timeout=TIMEOUT)
    except requests.RequestException as exc:
        return {
            "query": query,
            "include_domains": include_domains,
            "request_exception": str(exc),
            "elapsed_s": round(time.time() - t0, 2),
        }
    elapsed = time.time() - t0

    credit_headers = {
        k: v
        for k, v in resp.headers.items()
        if any(term in k.lower() for term in ("credit", "usage", "limit", "remaining"))
    }

    record = {
        "query": query,
        "include_domains": include_domains,
        "status_code": resp.status_code,
        "elapsed_s": round(elapsed, 2),
        "credit_related_headers": credit_headers,
    }

    try:
        payload = resp.json()
    except ValueError:
        record["parse_error"] = True
        record["raw_body"] = resp.text[:2000]
        return record

    if resp.status_code != 200:
        record["error_payload"] = payload
        record["result_count"] = 0
        record["results"] = []
        return record

    record["tavily_response_time_field"] = payload.get("response_time")
    results = payload.get("results", [])
    record["result_count"] = len(results)
    parsed_results = []
    for r in results:
        url = r.get("url", "")
        host = host_of(url)
        parsed_results.append(
            {
                "title": r.get("title"),
                "url": url,
                "host": host,
                "in_official_allowlist": host_in_allowlist(host, TRUSTED_DOMAINS),
                "content_len": len(r.get("content") or ""),
                "has_raw_content": r.get("raw_content") is not None,
                "score": r.get("score"),
            }
        )
    record["results"] = parsed_results
    record["response_keys"] = sorted(payload.keys())
    if results:
        record["first_result_raw_keys"] = sorted(results[0].keys())
    return record


def phase1_full_allowlist(api_key):
    print("\n=== FASE 1 — 20 buscas, include_domains = allowlist completa (30 domínios) ===")
    rows = []
    for i, claim in enumerate(CLAIMS, start=1):
        print(f"\n[{i}/20] {claim[:70]}...")
        result = do_search(api_key, claim, include_domains=TRUSTED_DOMAINS, max_results=5)
        result["claim"] = claim
        rows.append(result)

        if result.get("request_exception"):
            print(f"    ERRO DE REDE: {result['request_exception']}")
        elif result.get("parse_error"):
            print(f"    ERRO AO PARSEAR RESPOSTA: status={result['status_code']}")
        else:
            outside = [r for r in result.get("results", []) if not r["in_official_allowlist"]]
            print(
                f"    status={result['status_code']} resultados={result.get('result_count')} "
                f"fora_da_allowlist={len(outside)} tempo={result['elapsed_s']}s"
            )
            if outside:
                print(f"    !!! ATENÇÃO: hosts fora da allowlist: {[r['host'] for r in outside]}")

        time.sleep(DELAY_BETWEEN_CALLS_S)
    return rows


def phase2_exclusion_test(api_key):
    print("\n=== FASE 2 — teste de exclusão (domínio fora da allowlist incluso em include_domains) ===")
    rows = []
    test_claims = CLAIMS[:len(EXCLUSION_TEST_DOMAINS)]
    for extra_domain, claim in zip(EXCLUSION_TEST_DOMAINS, test_claims):
        combined = TRUSTED_DOMAINS + [extra_domain]
        print(f"\n[misto] extra_domain={extra_domain} claim={claim[:60]}...")
        mixed = do_search(api_key, claim, include_domains=combined, max_results=10)
        mixed["claim"] = claim
        mixed["extra_domain"] = extra_domain
        mixed["kind"] = "mixed_30_plus_extra"
        appeared = [
            r
            for r in mixed.get("results", [])
            if r["host"] == extra_domain or r["host"].endswith("." + extra_domain)
        ]
        mixed["extra_domain_appeared"] = len(appeared) > 0
        mixed["extra_domain_appearances"] = appeared
        rows.append(mixed)
        print(
            f"    misto: resultados={mixed.get('result_count')} "
            f"extra_domain_apareceu={mixed['extra_domain_appeared']}"
        )
        time.sleep(DELAY_BETWEEN_CALLS_S)

        print(f"    [controle isolado] include_domains=[{extra_domain}]")
        isolated = do_search(api_key, claim, include_domains=[extra_domain], max_results=5)
        isolated["claim"] = claim
        isolated["extra_domain"] = extra_domain
        isolated["kind"] = "isolated_extra_only"
        rows.append(isolated)
        print(f"    isolado: resultados={isolated.get('result_count')}")
        time.sleep(DELAY_BETWEEN_CALLS_S)
    return rows


def phase3_no_results(api_key):
    print("\n=== FASE 3 — teste de 'nenhum resultado' (RF-04.4) ===")
    nonsense_query = (
        "xzqvwplkjhqwsdfghjklzxcvbnm9876543210 teste deliberado sem "
        "nenhuma noticia correspondente esperada nesta consulta"
    )
    result = do_search(api_key, nonsense_query, include_domains=TRUSTED_DOMAINS, max_results=5)
    result["claim"] = nonsense_query
    print(f"    status={result.get('status_code')} resultados={result.get('result_count')}")
    time.sleep(DELAY_BETWEEN_CALLS_S)
    return [result]


def phase4_invalid_key():
    print("\n=== FASE 4 — teste de chave de API inválida ===")
    fake_key = "tvly-INVALID-TEST-KEY-0000000000000000"
    result = do_search(fake_key, "teste de chave invalida", include_domains=TRUSTED_DOMAINS, max_results=3)
    print(f"    status={result.get('status_code')}")
    return [result]


def main():
    api_key = get_api_key()
    all_data = {}

    all_data["phase1_full_allowlist"] = phase1_full_allowlist(api_key)
    all_data["phase2_exclusion_test"] = phase2_exclusion_test(api_key)
    all_data["phase3_no_results"] = phase3_no_results(api_key)
    all_data["phase4_invalid_key"] = phase4_invalid_key()

    Path("results.json").write_text(json.dumps(all_data, ensure_ascii=False, indent=2))
    print("\nConcluído. Resultados em results.json.")


if __name__ == "__main__":
    main()
