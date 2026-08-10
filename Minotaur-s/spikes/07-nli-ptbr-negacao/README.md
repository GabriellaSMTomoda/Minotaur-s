# Spike 7 — NLI nativo de PT-BR + verificação por negação

Código **descartável**, fora do app. Endereça o item aberto 24 da spec (risco
materializado em 7.1: o pipeline confirma notícias comprovadamente falsas) e o
item aberto 25 (robustez a afirmações curtas).

> A pasta `spikes/07-tokenizer-parity/` é anterior e não tem relação com este
> spike — o "7" ali é só numeração de pasta. O "Spike 7" da spec é este.

## O que este spike responde

- **(a)** Existe modelo de NLI com base **nativa de português** que execute em
  device e julgue melhor os pares reais que o `MiniLMv2-L6` de hoje (DT-18)?
- **(b)** Rodar o par também com a **afirmação negada** recupera casos? Qual das
  duas leituras do sinal recupera mais, e quanto custa gerar a negação em PT-BR?

Resultados e recomendação: [`RESULTADO.md`](./RESULTADO.md).

## Ordem dos filtros

A do Spike 2c, que existe por causa do mDeBERTa — ele converteu, bateu logits no
desktop e **não executa em device nenhum**. Qualidade medida antes de execução é
qualidade jogada fora.

| | Filtro | Script |
|---|---|---|
| 0 | três classes NLI de verdade (RF-07.2) | `candidates.py`, `convert_and_reference.py` |
| — | ordem índice→rótulo confirmada empiricamente | `probe_labels.py` |
| 1 | converte para Core ML INT8 sem custom op | `convert_and_reference.py` |
| 2 | **executa em device físico** com logits batendo em PyTorch | `run_gate_device.sh` + `xcode-bench/` |
| 3 | só então: qualidade PT-BR nos pares reais | `qualidade_ptbr.py` |

## Conjunto de teste

`dataset.py` — todo texto é real, colhido da investigação instrumentada
pós-Fase 5. Ver a seção "Conjunto de teste" do `RESULTADO.md`.

## Como reproduzir

```bash
cd spikes/07-nli-ptbr-negacao
V=../02-coreml-latencia/.venv/bin/python

$V probe_labels.py                 # ordem dos rótulos (bloqueante)
$V convert_and_reference.py        # FILTRO 0+1 -> build/*.mlpackage + manifest.json
./run_gate_device.sh               # FILTRO 2 (iPhone físico)
$V qualidade_ptbr.py               # FILTRO 3

$V negacao.py --exportar-claims                                   # caminho (b)
swift negador/negador.swift build/claims.json build/negacoes_auto.json
$V negacao.py
```

`build/` não é versionado (`.mlpackage` de centenas de MB).
