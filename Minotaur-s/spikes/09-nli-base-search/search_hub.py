#!/usr/bin/env python3
"""Spike 9 / Etapa 1: busca reprodutivel de NLI PT-BR base no HF Hub.

Nao baixa pesos. Enumera metadados, config.json e model cards, deixando um
snapshot auditavel para revisao humana. A classificacao final continua no
RESULTADO.md, porque config.id2label nao e evidencia suficiente neste projeto.
"""

from __future__ import annotations

import concurrent.futures
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "hub_audit.json"
USER_AGENT = "Minotaur-Spike9-NLI-search/1.0"

SEARCH_TERMS = (
    "nli",
    "mnli",
    "xnli",
    "entailment",
    "contradiction",
    "rte",
    "assin",
    "inferbr",
    "plue",
    "bertimbau nli",
    "portuguese nli",
)

# Bases nativas PT-BR de tamanho base identificadas no Hub. A lista inclui
# familias alem do BERTimbau para evitar que a busca fique presa ao nome obvio.
NATIVE_BASES = (
    "neuralmind/bert-base-portuguese-cased",
    "PORTULAN/albertina-100m-portuguese-ptbr-encoder",
    "PortBERT/PortBERT_base",
    "ricardoz/BERTugues-base-portuguese-cased",
    "pysentimiento/bertabaporu-base-uncased",
    "josu/roberta-pt-br",
    "rdenadai/BR_BERTo",
)

NLI_SIGNAL = re.compile(
    r"nli|mnli|xnli|natural language inference|recognizing textual entailment|"
    r"entailment|contradiction|\brte\b|assin|inferbr|plue",
    re.IGNORECASE,
)

NATIVE_SIGNAL = re.compile(
    r"portugu|bertimbau|ptbr|pt-br|albertina|bertugues|portbert|bertabaporu|"
    r"debertinha|br_berto|roberta-pt|inferbr|plue",
    re.IGNORECASE,
)


def request(url: str, *, retries: int = 3) -> tuple[bytes, dict[str, str]]:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=20) as response:
                return response.read(), dict(response.headers.items())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            if isinstance(exc, urllib.error.HTTPError) and exc.code == 404:
                raise
            if attempt == retries - 1:
                raise
            time.sleep(2**attempt)
    raise AssertionError("unreachable")


def get_json(url: str):
    body, _ = request(url)
    return json.loads(body)


def paginate(params: dict[str, str], *, max_pages: int | None = None) -> list[dict]:
    query = urllib.parse.urlencode(params)
    url = f"https://huggingface.co/api/models?{query}"
    rows: list[dict] = []
    pages = 0
    while url and (max_pages is None or pages < max_pages):
        body, headers = request(url)
        page = json.loads(body)
        rows.extend(page)
        pages += 1
        link = headers.get("Link", "") or headers.get("link", "")
        match = re.search(r'<([^>]+)>;\s*rel="next"', link)
        url = match.group(1) if match else ""
    print(f"catalog {params}: {len(rows)} rows / {pages} pages", flush=True)
    return rows


def raw_text(model_id: str, filename: str) -> str | None:
    quoted = "/".join(urllib.parse.quote(part, safe="") for part in model_id.split("/"))
    url = f"https://huggingface.co/{quoted}/resolve/main/{filename}"
    try:
        body, _ = request(url)
        return body.decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def fetch_config(model_id: str) -> tuple[str, dict | None, str | None]:
    try:
        text = raw_text(model_id, "config.json")
        return model_id, json.loads(text) if text else None, None
    except Exception as exc:  # snapshot deve registrar falhas, nao esconde-las
        return model_id, None, f"{type(exc).__name__}: {exc}"


def compact_model(row: dict) -> dict:
    return {
        "id": row.get("id"),
        "pipeline_tag": row.get("pipeline_tag"),
        "tags": row.get("tags", []),
        "downloads": row.get("downloads"),
        "lastModified": row.get("lastModified"),
        "siblings": [item.get("rfilename") for item in row.get("siblings", [])],
    }


def config_summary(config: dict | None) -> dict | None:
    if not config:
        return None
    id2label = config.get("id2label")
    inferred_labels = len(id2label) if isinstance(id2label, dict) else config.get("num_labels")
    return {
        "architectures": config.get("architectures"),
        "model_type": config.get("model_type"),
        "num_labels": inferred_labels,
        "id2label": id2label,
        "label2id": config.get("label2id"),
        "hidden_size": config.get("hidden_size") or config.get("dim"),
        "num_hidden_layers": config.get("num_hidden_layers") or config.get("n_layers"),
        "num_attention_heads": config.get("num_attention_heads") or config.get("n_heads"),
        "vocab_size": config.get("vocab_size"),
    }


def text_blob(row: dict, config: dict | None) -> str:
    return json.dumps(
        {"id": row.get("id"), "tags": row.get("tags", []), "config": config},
        ensure_ascii=False,
    )


def main() -> None:
    sources: dict[str, list[str]] = {}
    models: dict[str, dict] = {}

    def add(rows: list[dict], source: str) -> None:
        for row in rows:
            model_id = row.get("id")
            if not model_id:
                continue
            models.setdefault(model_id, compact_model(row))
            sources.setdefault(model_id, []).append(source)

    pt_classifiers = paginate(
        {"filter": "pt,text-classification", "limit": "100", "full": "true"}
    )
    add(pt_classifiers, "filter=pt,text-classification")

    for tag in ("nli", "mnli", "xnli"):
        add(
            paginate({"filter": tag, "limit": "100", "full": "true"}),
            f"filter={tag}",
        )

    for term in SEARCH_TERMS:
        add(
            paginate(
                {"search": term, "limit": "1000", "full": "true"},
                max_pages=1,
            ),
            f"search={term}",
        )

    for base in NATIVE_BASES:
        add(
            paginate(
                {"filter": f"base_model:{base}", "limit": "100", "full": "true"}
            ),
            f"base_model={base}",
        )

    audit_ids = []
    for model_id, row in models.items():
        discovery = sources[model_id]
        tags = row.get("tags", [])
        from_pt_catalog = "filter=pt,text-classification" in discovery
        from_native_lineage = any(item.startswith("base_model=") for item in discovery)
        explicit_pt = "pt" in tags or "portuguese" in tags
        native_named = bool(NATIVE_SIGNAL.search(text_blob(row, None)))
        if from_pt_catalog or from_native_lineage or (explicit_pt and native_named):
            audit_ids.append(model_id)

    configs: dict[str, dict | None] = {}
    config_errors: dict[str, str] = {}
    print(f"unique catalog rows: {len(models)}; configs to audit: {len(audit_ids)}", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(fetch_config, model_id) for model_id in sorted(audit_ids)]
        for index, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            model_id, config, error = future.result()
            configs[model_id] = config
            if error:
                config_errors[model_id] = error
            if index % 100 == 0 or index == len(futures):
                print(f"configs: {index}/{len(futures)}", flush=True)

    interesting_ids: list[str] = []
    for model_id in audit_ids:
        row = models[model_id]
        summary = config_summary(configs.get(model_id))
        labels = summary.get("num_labels") if summary else None
        if NLI_SIGNAL.search(text_blob(row, configs.get(model_id))) or labels == 3:
            interesting_ids.append(model_id)

    cards: dict[str, str | None] = {}
    print(f"interesting before card review: {len(interesting_ids)}", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(raw_text, model_id, "README.md"): model_id for model_id in interesting_ids}
        for index, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            model_id = futures[future]
            try:
                cards[model_id] = future.result()
            except Exception as exc:
                cards[model_id] = f"[FETCH ERROR] {type(exc).__name__}: {exc}"
            if index % 50 == 0 or index == len(futures):
                print(f"cards: {index}/{len(futures)}", flush=True)

    interesting = []
    for model_id in sorted(interesting_ids, key=str.casefold):
        row = models[model_id]
        interesting.append(
            {
                **row,
                "discovered_by": sorted(set(sources[model_id])),
                "config": config_summary(configs.get(model_id)),
                "card": cards.get(model_id),
            }
        )

    output = {
        "method": {
            "search_terms": SEARCH_TERMS,
            "native_bases": NATIVE_BASES,
            "note": "Snapshot sem pesos. id2label e apenas pista de triagem.",
        },
        "counts": {
            "pt_text_classification": len(pt_classifiers),
            "unique_catalog_models": len(models),
            "models_with_config_audited": len(audit_ids),
            "interesting_models": len(interesting),
            "config_fetch_errors": len(config_errors),
        },
        "config_fetch_errors": config_errors,
        "interesting_models": interesting,
    }
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(output["counts"], ensure_ascii=False, indent=2))
    print(f"snapshot: {OUTPUT}")


if __name__ == "__main__":
    main()
