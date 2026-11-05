#!/usr/bin/env python3
"""Offline, public-data-only curation. Never imports user verification history."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
from datetime import datetime
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

VERDICTS = ("CONFIRMADO", "CONTRADITO", "DIVERGENTE", "SEM_INFORMACAO", "NAO_ENCONTRADO")
TARGETS = {"train": 600, "calibration": 300, "test": 300}

def read(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]

def write(path, records):
    Path(path).write_text("".join(json.dumps(x, ensure_ascii=False, sort_keys=True) + "\n" for x in records))

def canonical(url):
    p = urlsplit(url)
    return urlunsplit((p.scheme, p.netloc.lower().removeprefix("www."), p.path.rstrip("/"), "", ""))

def fingerprint(records):
    return hashlib.sha256(json.dumps(records, sort_keys=True, ensure_ascii=False).encode()).hexdigest()

def import_quiz(source, target):
    records = []
    with Path(source).open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            claim, url = (row.get("Título") or "").strip(), (row.get("URL") or "").strip()
            if not claim or not url.startswith("https://"):
                continue
            family = hashlib.sha256(canonical(url).encode()).hexdigest()[:16]
            records.append({"id": "quiz-" + row["ID"], "claim": claim, "source_url": url,
                            "event_id": family, "family_id": family, "reference_date": None,
                            "source_date_suggestion": row.get("Data"),
                            "topic": row.get("Assunto"), "review_status": "pending", "reviewers": [],
                            "candidate_verdict": "CONTRADITO" if row.get("Binário") == "FARSA" else "CONFIRMADO",
                            "verdict": None, "evidence": [], "sufficient_evidence_sets": [], "pairs": [],
                            "origin": "existing_quiz_candidate_not_gold"})
    write(target, records)
    return len(records)

def validate(records, require_reviewed=False):
    ids, groups = set(), {}
    for row in records:
        if not row.get("id") or row["id"] in ids:
            raise ValueError("Missing/duplicate record id")
        ids.add(row["id"])
        if not row.get("claim") or not row.get("event_id") or not row.get("family_id"):
            raise ValueError(f"{row['id']}: claim/event/family required")
        reviewed = row.get("review_status") == "reviewed"
        if require_reviewed and not reviewed:
            raise ValueError(f"{row['id']}: pending human review")
        if reviewed:
            if row.get("verdict") not in VERDICTS or not row.get("reference_date"):
                raise ValueError(f"{row['id']}: verdict/reference date missing")
            try:
                datetime.fromisoformat(row["reference_date"].replace("Z", "+00:00"))
            except (ValueError, AttributeError):
                raise ValueError(f"{row['id']}: reference date must be ISO 8601") from None
            if len(set(row.get("reviewers", []))) < 2:
                raise ValueError(f"{row['id']}: independent review required")
            evidence = {e["id"] for e in row.get("evidence", [])}
            if row["verdict"] in ("CONFIRMADO", "CONTRADITO", "DIVERGENTE"):
                sets = row.get("sufficient_evidence_sets", [])
                if not sets or any(not s or not set(s) <= evidence for s in sets):
                    raise ValueError(f"{row['id']}: annotated sufficient evidence required")
            for e in row.get("evidence", []):
                if not e.get("url", "").startswith("https://") or not e.get("text"):
                    raise ValueError(f"{row['id']}: evidence URL/text missing")
            for pair in row.get("pairs", []):
                if pair.get("label") not in ("entailment", "neutral", "contradiction") or not pair.get("premise") or not pair.get("hypothesis"):
                    raise ValueError(f"{row['id']}: invalid NLI pair")
        split = row.get("split")
        if split:
            if split not in TARGETS and split != "regression":
                raise ValueError("Unknown split")
            keys = ["event:" + row["event_id"], "family:" + row["family_id"]]
            keys += ["url:" + canonical(e["url"]) for e in row.get("evidence", [])]
            if row.get("source_url"):
                keys += ["url:" + canonical(row["source_url"])]
            for key in keys:
                if key in groups and groups[key] != split:
                    raise ValueError("Cross-split leakage: " + key)
                groups[key] = split
    return {"count": len(records), "reviewed": sum(x.get("review_status") == "reviewed" for x in records),
            "splits": dict(Counter(x.get("split", "unassigned") for x in records)), "sha256": fingerprint(records)}

def split_records(records):
    validate(records, require_reviewed=True)
    if len(records) != sum(TARGETS.values()):
        raise ValueError("The release corpus requires exactly 1200 reviewed claims; no synthetic padding")
    parent = list(range(len(records)))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    keys = {}
    for i, row in enumerate(records):
        row_keys = ["event:" + row["event_id"], "family:" + row["family_id"]]
        row_keys += ["url:" + canonical(e["url"]) for e in row.get("evidence", [])]
        if row.get("source_url"):
            row_keys.append("url:" + canonical(row["source_url"]))
        for key in row_keys:
            if key in keys:
                parent[root(i)] = root(keys[key])
            keys[key] = i
    groups = {}
    for i, row in enumerate(records):
        groups.setdefault(root(i), []).append(row)
    # Pack whole event/family/source components. Never split a family to satisfy a quota.
    ordered = sorted(groups.values(), key=lambda g: (-len(g), fingerprint(g)))
    remaining = dict(TARGETS)
    for group in ordered:
        choices = [s for s in TARGETS if remaining[s] >= len(group)]
        if not choices:
            raise ValueError("Group sizes prevent exact 600/300/300 packing; revise corpus composition, never break groups")
        chosen = max(choices, key=lambda s: remaining[s] / TARGETS[s])
        remaining[chosen] -= len(group)
        for row in group:
            row["split"] = chosen
    validate(records, require_reviewed=True)
    return records

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("import-quiz"); p.add_argument("source"); p.add_argument("target")
    p = commands.add_parser("validate"); p.add_argument("dataset"); p.add_argument("--require-reviewed", action="store_true")
    p = commands.add_parser("split"); p.add_argument("dataset"); p.add_argument("target")
    args = parser.parse_args()
    if args.command == "import-quiz":
        print(json.dumps({"pending_candidates": import_quiz(args.source, args.target)}))
    elif args.command == "validate":
        print(json.dumps(validate(read(args.dataset), args.require_reviewed), indent=2))
    else:
        records = split_records(read(args.dataset)); write(args.target, records)
        print(json.dumps(validate(records, True), indent=2))

if __name__ == "__main__":
    main()
