# -*- coding: utf-8 -*-
"""
SPIKE 8 — sanidade do harness: os logits que o device produziu são os certos?

Não é medição de RAM; é a garantia de que a RAM medida é a de um modelo rodando
DIREITO. O Spike 7 registrou que um BERT alimentado sem `token_type_ids` roda e
devolve logits errados sem erro nenhum — se fosse o caso aqui, o gate estaria
medindo uma interface quebrada em vez do modelo que vai para produção.

Compara o 1º par do fixture (o mesmo que o harness imprime) com o PyTorch fp32.

Uso:
  ../02-coreml-latencia/.venv/bin/python check_parity.py "-1.921,-0.225,1.883"
"""
import json
import os
import sys

import torch
from transformers import AutoModelForSequenceClassification

HERE = os.path.dirname(os.path.abspath(__file__))
NLI_ID = "giotvr/bertimbau_large_plue_mnli_fine_tuned"


def main():
    device_logits = None
    if len(sys.argv) > 1:
        device_logits = [float(x) for x in sys.argv[1].split(",")]

    with open(os.path.join(HERE, "build", "fixture.json"), encoding="utf-8") as fh:
        fixture = json.load(fh)
    pair = fixture["articles"][0]["nli_inputs"][0]

    model = AutoModelForSequenceClassification.from_pretrained(NLI_ID).eval()
    with torch.no_grad():
        out = model(
            input_ids=torch.tensor([pair["input_ids"]]),
            attention_mask=torch.tensor([pair["attention_mask"]]),
            token_type_ids=torch.tensor([pair["token_type_ids"]]),
        )
    reference = out.logits[0].tolist()

    print("seq_len          :", len(pair["input_ids"]))
    print("claim            :", pair["claim"])
    print("PyTorch fp32     :", [round(x, 3) for x in reference])
    if device_logits is None:
        return 0

    print("Core ML (device) :", device_logits)
    dot = sum(a * b for a, b in zip(reference, device_logits))
    na = sum(a * a for a in reference) ** 0.5
    nb = sum(b * b for b in device_logits) ** 0.5
    print("cos              :", round(dot / (na * nb), 6))
    print("argmax           :",
          reference.index(max(reference)), "vs", device_logits.index(max(device_logits)),
          "->", "BATE" if reference.index(max(reference)) == device_logits.index(max(device_logits))
          else "DIVERGE")

    # Sonda do modo de falha do Spike 7: como ficariam os logits SEM token_type_ids.
    with torch.no_grad():
        zeroed = model(
            input_ids=torch.tensor([pair["input_ids"]]),
            attention_mask=torch.tensor([pair["attention_mask"]]),
            token_type_ids=torch.zeros(1, len(pair["input_ids"]), dtype=torch.long),
        )
    print("sem token_type   :", [round(x, 3) for x in zeroed.logits[0].tolist()],
          "(o que o device teria produzido se a 3ª entrada estivesse errada)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
