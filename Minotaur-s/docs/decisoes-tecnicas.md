# Decisões técnicas do Verificador

Cada decisão importante do Verificador saiu de um experimento pequeno e descartável (um *spike*), com uma pergunta, uma medição e um resultado registrado antes de mexer no app. Esta página resume os experimentos no formato **pergunta → experimento → resultado → decisão**. Os detalhes, scripts e números completos estão no `RESULTADO.md` de cada pasta em [`spikes/`](../spikes).

## Restrições que orientaram tudo

- **Sem API paga de LLM.** O veredito vem de modelos clássicos de NLP rodando no próprio iPhone (Core ML).
- **Custo de operação ≈ zero.** A busca usa a cota gratuita da Tavily (1.000 créditos/mês), protegida por um Worker Cloudflare com contadores em D1. A Wikipédia é gratuita.
- **Privacidade.** Nenhum histórico de verificações; o proxy guarda só contadores; a chave da API nunca vai para o app.
- **Hardware real.** Modelos precisam executar em iPhone, caber em 1 GB de RAM e responder em menos de 1 s por par.

## Spikes 01–10

| # | Pergunta | Experimento | Resultado | Decisão |
|---|---|---|---|---|
| [01](../spikes/01-modelos-ptbr/RESULTADO.md) | Um par embeddings + NLI multilíngue funciona em português? | MiniLM-L12 multilíngue + mDeBERTa-v3 em Python sobre trechos reais de imprensa | Classificou corretamente, com alta confiança, os casos PT-BR | Seguir com embeddings + NLI |
| [02](../spikes/02-coreml-latencia/RESULTADO.md) | Os modelos convertem para Core ML? | Conversão + quantização INT8 | Embeddings: sim (113 MB, cos 0,9999). mDeBERTa: não (op `XSoftmax`) | Reabrir a escolha do NLI |
| [02b](../spikes/02b-alternativas-nli/RESULTADO.md) | Há NLI alternativo conversível? | Patch do XSoftmax e candidatos menores | Todos converteram com saída idêntica no desktop | Testar execução no aparelho antes de qualidade |
| [02c](../spikes/02c-nli-executavel/RESULTADO.md) | Qual NLI **executa** num iPhone físico? | Execução real em device antes de medir qualidade | mDeBERTa converte mas trava no device; MiniLMv2-L6/L12 executam | Lição: "converte" ≠ "executa"; validar no aparelho primeiro |
| [03](../spikes/03-extracao-texto/RESULTADO.md) | Dá para extrair o corpo das matérias com HTML estático? | Extração heurística em 34 domínios | 30/34 limpos; os 4 que falharam eram bloqueio de bot | Extração Readability-like em Swift; remover os 4 domínios |
| [04](../spikes/04-ddg-scraping/RESULTADO.md) / [04b](../spikes/04b-ddg-urlsession/RESULTADO.md) | Raspar o DuckDuckGo é estável? | Python e `URLSession` no iPhone | Bloqueio por bot nos dois clientes | Descartar scraping de buscador |
| [05](../spikes/05-tavily-validacao/RESULTADO.md) | A API da Tavily cumpre o que promete? | Chamadas reais com a allowlist | Viável; 1 crédito por busca basic | Tavily via proxy, dentro da cota gratuita |
| [07](../spikes/07-nli-ptbr-negacao/RESULTADO.md) | Um NLI com base em português acerta mais? Negar a afirmação ajuda? | Pares reais de produção; variante com negação automática | BERTimbau (PLUE) corrigiu Terra plana/vacina; a negação piorou todos os modelos | Trocar para BERTimbau; nunca gerar negação |
| [08](../spikes/08-gate-ram/RESULTADO.md) | BERTimbau-**large** cabe na RAM? | Pico de memória no iPhone 16 com os dois modelos | 1.125–1.314 MB, acima do teto de 1 GB | Reprovado; procurar uma versão *base* |
| [09](../spikes/09-nli-base-search/RESULTADO.md) | Um BERTimbau-**base** com cabeça NLI resolve RAM e latência? | Treino local (6 h 29 min no Mac, R$ 0) no PLUE/MNLI + gate físico | Macro-F1 0,817 no dev; pico 383 MB; ~69 ms por par | Modelo atual do app |
| [10](../spikes/10-ensemble-minilm/RESULTADO.md) | Um segundo NLI em ensemble melhora o veredito? | MiniLMv2-L6 em Core ML (paridade 34/35) + quatro estratégias no harness | Nenhuma combinação melhorou o dev; todas aumentaram erros de direção oposta | Não embarcar (+103 MB sem ganho) |

## A correção de novembro de 2026: "Fontes divergentes" para tudo

**Sintoma.** O app respondia "Fontes divergentes" até para fatos triviais ("A Terra gira em torno do Sol").

**Diagnóstico** (medido no harness offline, conjunto dev de 120 afirmações, não-gold):

1. A regra de agregação da v0.5 declarava DIVERGENTE se **uma** passagem, entre até 24 pares NLI, passasse de 0,5 em contradição e outra passasse de 0,5 em entailment.
2. Modelos NLI treinados em MNLI dão contradição alta para texto **fora do tema**: "Lula visitou a China" vs. "Brasília é a capital do Brasil" → 0,94 de contradição. Com 24 pares, quase sempre aparece uma.
3. As premissas eram janelas de até 440 tokens que misturavam vários fatos.

Resultado: 77 de 120 vereditos eram DIVERGENTE, com acerto de 24%.

**Correção (política de evidência v3).**

- O NLI passa a comparar **frases** com a afirmação, não janelas longas.
- Cada passagem atravessa **portões de relevância** antes de votar: os mesmos nomes próprios (correspondência exata, para "Brasil" não casar com "Brasília"), os mesmos números, e as palavras mais específicas da afirmação. A especificidade vem da raridade no vocabulário do tokenizador XLM-R, sem modelo extra.
- Uma refutação só conta em formas reconhecíveis: mesmo sujeito com outro atributo, mesmo predicado com outro sujeito nomeado, ou outro número.
- Regras para checagens: frase que relata o boato não é apoio, e o título da agência que desmente vira refutação.
- Cada origem editorial vota uma vez. DIVERGENTE exige um lado oposto real.

**Como foi feito.** Um harness em Python roda os mesmos arquivos `.mlmodelc` do app sobre buscas cacheadas; reavaliar custa zero crédito. Cada regra nova foi motivada por erros concretos listados no relatório por caso. A regra foi escrita primeiro em Python (`evaluation/harness/evidence.py`) e depois portada para Swift. Um teste de paridade compara as duas implementações em 120 passagens reais.

**O que foi testado e descartado, com números.** Ensemble com um segundo NLI (Spike 10); sempre executar a consulta "checagem" (mesmo acerto nos boatos e o dobro de créditos).

## Ferramentas avaliadas para o desenvolvimento

| Ferramenta | Veredito | Motivo |
|---|---|---|
| Claude Code (subagentes, skills) | Usada | Sessões paralelas para conversão do MiniLM, rota `/wiki` e script de retreino; skill `avaliar-verificador` e agente `analista-erros-verificador` versionados em `.claude/` |
| `uv` | Usada | Ambientes Python reproduzíveis com lockfile para harness, spikes e treino |
| MCP (XcodeBuildMCP) | Usada | Build e testes Swift no simulador e no iPhone nas rodadas de validação |
| Ollama (LLM local) | Planejada, só desenvolvimento | Rotular pares NLI do domínio de notícias para o retreino; nunca no app. Exige ~15 GB livres de disco |
| RAG | Parcial | O pipeline já é recuperação + leitura por NLI; a geração é justamente o que está fora do escopo |
| Claude Agents SDK | Descartada | Custo de API à parte; subagentes do Claude Code cobrem o uso |
| LangSmith | Descartada | SaaS que receberia textos das consultas; conflita com a política de privacidade |
| LangGraph, n8n | Descartadas | Orquestram LLMs/fluxos com servidor; o pipeline é determinístico e roda no aparelho |
| pgvector | Descartada | Exige Postgres hospedado; um índice vetorial, se preciso, roda no aparelho |
| Docker | Descartada | Core ML só roda em macOS e contêiner no Mac não usa a GPU/MPS |
| Cline | Descartada | Duplica o agente de código já usado |
