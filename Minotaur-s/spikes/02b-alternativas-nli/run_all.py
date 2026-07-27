# -*- coding: utf-8 -*-
"""
SPIKE 2b — roda a conversão de teste de todos os candidatos do Caminho 2 e
imprime uma tabela-resumo. Cada candidato é convertido num subprocesso isolado
(um crash/erro de conversão de um não derruba os demais).

Uso: python run_all.py [--keep]
"""
import json
import os
import subprocess
import sys

from common import CANDIDATES

HERE = os.path.dirname(__file__)
RESULTS = os.path.join(HERE, "results")


def main():
    keep = "--keep" in sys.argv[1:]
    rows = []
    for c in CANDIDATES:
        model_id = c["id"]
        print("\n" + "=" * 78)
        print(f"CANDIDATO: {model_id}")
        print("=" * 78, flush=True)
        cmd = [sys.executable, os.path.join(HERE, "convert_candidate.py"), model_id]
        if keep:
            cmd.append("--keep")
        subprocess.run(cmd, cwd=HERE)  # não checamos returncode: falha é resultado válido
        rec_path = os.path.join(RESULTS, model_id.replace("/", "__") + ".json")
        if os.path.exists(rec_path):
            with open(rec_path) as f:
                rows.append(json.load(f))

    print("\n\n" + "#" * 78)
    print("RESUMO SPIKE 2b — CONVERSÃO DOS CANDIDATOS")
    print("#" * 78)
    hdr = f"{'modelo':<52} {'conv?':<6} {'classes':<8} {'INT8 MB':<9} {'cos':<7} {'argmax'}"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        conv = "SIM" if r.get("converts") else "NÃO"
        print(f"{r['id']:<52} {conv:<6} {str(r.get('num_labels')):<8} "
              f"{str(r.get('int8_mb')):<9} {str(r.get('logits_cos')):<7} "
              f"{str(r.get('argmax_match'))}")
        if r.get("error"):
            print(f"    erro: {r['error']}")


if __name__ == "__main__":
    main()
