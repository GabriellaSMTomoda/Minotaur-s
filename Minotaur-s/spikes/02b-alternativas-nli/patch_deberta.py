# -*- coding: utf-8 -*-
"""
SPIKE 2b — Caminho 1: patchar o XSoftmax do (m)DeBERTa-v3 e avaliar honestamente.

Contexto: o Spike 2 provou que o mDeBERTa-v3 NÃO converte para Core ML porque a
disentangled-attention usa `XSoftmax`, uma `torch.autograd.Function` customizada
que vira `prim::PythonOp` (op 'pythonop' não implementada no coremltools).

Este script faz DUAS coisas, nesta ordem, e reporta os dois resultados:

  (1) EQUIVALÊNCIA NUMÉRICA — troca `XSoftmax.apply` por um softmax mascarado
      PADRÃO (masked_fill(-inf) -> softmax -> masked_fill(0)) e compara os logits
      do modelo PATCHADO vs. ORIGINAL sobre um par PT-BR real. O forward do
      XSoftmax *é* exatamente esse masked softmax (a autograd.Function existe pelo
      backward otimizado, irrelevante em inferência), então a diferença esperada
      é ~0. Confirmamos, não assumimos.

  (2) CONVERSÃO — tenta converter o DeBERTa PATCHADO para Core ML. Dois desfechos
      possíveis, ambos informativos:
        - converte  -> o XSoftmax era o único muro (ainda faltaria revalidar PT-BR,
                       fora do escopo desta tarefa);
        - NÃO converte -> patchar o XSoftmax só revelou a PRÓXIMA parede (ex.: gathers
                       da disentangled-attention). Imprime a op/mensagem EXATA.

NÃO reescreve mais nada além do XSoftmax. NÃO revalida acurácia em PT-BR.
"""
import os
import sys
import traceback

import numpy as np
import torch

# Reuso defensivo dos shims de versão do Spike 2 (new_ones/bitwise_and). No
# toolchain pinado (torch 2.7) eles não devem disparar; ficam só para garantir
# que uma lacuna de versão não se disfarce de "muro arquitetural".
# append (NÃO insert(0)) para não sombrear o common.py local com o do Spike 2
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "02-coreml-latencia"))
import coreml_shims  # noqa: E402,F401

import coremltools as ct  # noqa: E402
from transformers import AutoModelForSequenceClassification, AutoTokenizer  # noqa: E402
from transformers.models.deberta_v2 import modeling_deberta_v2 as dv2  # noqa: E402

from common import MAX_SEQ, NLI_HYPOTHESIS, NLI_PREMISE  # noqa: E402

NLI_MODEL = "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7"


class XSoftmaxPatched:
    """Masked softmax PADRÃO, rastreável (sem torch.autograd.Function).

    Reproduz o forward do XSoftmax original:
      rmask = ~mask.bool()
      x = x.masked_fill(rmask, min); softmax(x); zera posições mascaradas.
    """

    @staticmethod
    def apply(x, mask, dim):
        rmask = ~(mask.to(torch.bool))
        out = x.masked_fill(rmask, torch.finfo(x.dtype).min)
        out = torch.softmax(out, dim)
        out = out.masked_fill(rmask, 0.0)
        return out


class NLIWrapper(torch.nn.Module):
    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        return self.backbone(input_ids=input_ids, attention_mask=attention_mask,
                             return_dict=False)[0]


def logits_for(backbone, ids, mask):
    with torch.no_grad():
        return backbone(input_ids=ids, attention_mask=mask, return_dict=False)[0].numpy()[0]


def main():
    print(f"[c1] carregando {NLI_MODEL} ...", flush=True)
    backbone = AutoModelForSequenceClassification.from_pretrained(NLI_MODEL).float().eval()
    tok = AutoTokenizer.from_pretrained(NLI_MODEL)
    print(f"[c1] id2label = {backbone.config.id2label}", flush=True)

    enc = tok(NLI_PREMISE, NLI_HYPOTHESIS, return_tensors="pt",
              truncation=True, max_length=MAX_SEQ)
    ids, mask = enc["input_ids"], enc["attention_mask"]

    # (1) EQUIVALÊNCIA -------------------------------------------------------
    has_xsoftmax = hasattr(dv2, "XSoftmax")
    print(f"[c1] modeling_deberta_v2 tem XSoftmax? {has_xsoftmax}", flush=True)
    orig_logits = logits_for(backbone, ids, mask)
    print(f"[c1] logits ORIGINAL (XSoftmax) = {orig_logits}", flush=True)

    original = getattr(dv2, "XSoftmax", None)
    dv2.XSoftmax = XSoftmaxPatched  # monkeypatch do global do módulo
    patched_logits = logits_for(backbone, ids, mask)
    print(f"[c1] logits PATCHADO (softmax)  = {patched_logits}", flush=True)

    max_abs = float(np.max(np.abs(orig_logits - patched_logits)))
    cos = float(np.dot(orig_logits, patched_logits) /
                (np.linalg.norm(orig_logits) * np.linalg.norm(patched_logits) + 1e-9))
    argmatch = int(np.argmax(orig_logits)) == int(np.argmax(patched_logits))
    print("\n=== (1) EQUIVALÊNCIA NUMÉRICA (patchado vs original) ===")
    print(f"  max|Δlogit| = {max_abs:.3e}")
    print(f"  cos(logits) = {cos:.6f}")
    print(f"  argmax igual = {argmatch}")

    # (2) CONVERSÃO do modelo PATCHADO --------------------------------------
    print("\n=== (2) CONVERSÃO DO DeBERTa PATCHADO ===", flush=True)
    conv_ok = False
    conv_err = None
    try:
        model = NLIWrapper(backbone).eval()
        seq = 32
        ex_ids = torch.randint(0, 1000, (1, seq), dtype=torch.long)
        ex_mask = torch.ones((1, seq), dtype=torch.long)
        with torch.no_grad():
            traced = torch.jit.trace(model, (ex_ids, ex_mask), strict=False)
        seq_dim = ct.RangeDim(lower_bound=1, upper_bound=MAX_SEQ, default=seq)
        inputs = [
            ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, seq_dim), dtype=np.int32),
        ]
        mlmodel = ct.convert(
            traced, inputs=inputs, outputs=[ct.TensorType(name="logits")],
            compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=ct.target.iOS16, convert_to="mlprogram",
        )
        conv_ok = True
        print("[c1] CONVERTEU. O XSoftmax era o único muro de conversão.", flush=True)
        # tamanho aproximado (salva temporário)
        build = os.path.join(os.path.dirname(__file__), "build")
        os.makedirs(build, exist_ok=True)
        p = os.path.join(build, "DeBERTa_patched_fp16.mlpackage")
        mlmodel.save(p)
        from common import dir_size_mb
        print(f"[c1] FLOAT16 = {dir_size_mb(p):.1f} MB (INT8 seria ~metade)", flush=True)
    except Exception as e:  # noqa: BLE001
        conv_err = f"{type(e).__name__}: {e}"
        print("[c1] NÃO converteu mesmo com XSoftmax patchado.")
        print(f"[c1] Próxima parede -> {conv_err}")
        traceback.print_exc()
    finally:
        if original is not None:
            dv2.XSoftmax = original  # restaura

    print("\n=== RESUMO CAMINHO 1 ===")
    print(f"  equivalência: max|Δ|={max_abs:.3e} cos={cos:.6f} argmax_igual={argmatch}")
    print(f"  conversão patchada: {'OK' if conv_ok else 'FALHOU'}"
          + ("" if conv_ok else f" ({conv_err})"))


if __name__ == "__main__":
    main()
