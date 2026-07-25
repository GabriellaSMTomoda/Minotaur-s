# SPIKE 4 — Resultado: Estabilidade do Scraping de `html.duckduckgo.com`

**Data:** 2026-07-24
**Objetivo:** validar se `html.duckduckgo.com` é fonte de busca estável o
suficiente para produção, usando queries restritas por `site:` ... `OR`
... aos domínios da allowlist (RF-02.3), contra os 30 domínios que
restaram após a Tarefa 1 (remoção de `uol.com.br`, `espn.com.br`,
`reuters.com`, `ibge.gov.br` — Spike 3). Último spike da ordem definida em
§7.4 do `spec.md`.

Código de validação descartável, isolado do app iOS (Python). Não decide
biblioteca Swift, não implementa nada do app, não remove nada da
allowlist.

---

## Veredito rápido

> **Bloqueio ocorreu na 1ª requisição do script automatizado** (fase A,
> `n_domains=3`), com resposta `HTTP 202` e corpo de 14.439 bytes sem
> nenhum resultado de busca — o mesmo padrão de "202 com corpo
> anômalo/sem conteúdo útil" que o Spike 3 já tinha registrado para
> `espn.com.br` como assinatura de bot-detection, não de erro de rede.
> Isso aconteceu **apesar de uma requisição manual (`curl`) minutos antes,
> com query quase idêntica, ter funcionado normalmente (`HTTP 200`, 10
> resultados)**. Os testes foram interrompidos imediatamente, como
> instruído. **Não foi possível completar nem a fase A (limite de
> domínios por query) nem a fase B (20 buscas distintas)** — a amostra
> real coletada é de **1 requisição automatizada bloqueada + 1 requisição
> manual bem-sucedida**, nada além disso.

---

## Metodologia

1. `domains.py` — cópia dos 30 domínios da allowlist pós-Tarefa 1.
2. `queries.py` — 20 afirmações distintas em PT-BR (política, economia,
   esportes, saúde, justiça, internacional), com uma extração de
   keywords trivial (remoção de stopwords, top-8 palavras) só para gerar
   queries realistas — não é uma decisão de implementação para
   RF-02.2, que segue `[EM ABERTO]`.
3. `search_ddg.py` — script com duas fases planejadas:
   - **Fase A**: mesma query-base, número crescente de domínios no `OR`
     (3, 5, 8, 12, 16, 20, 25, 30), para achar o limite prático do
     operador.
   - **Fase B**: as 20 buscas distintas de `queries.py`, uma a cada
     10–25s (delay aleatório, não em rajada), usando o limite de
     domínios encontrado na fase A.
   - Detecção de bloqueio: `status_code` em `{403, 429, 503}`, qualquer
     `status_code` fora de `200`, marcadores textuais no corpo
     (`captcha`, `unusual traffic`, `blocked`, etc.) ou corpo
     suspeitosamente pequeno (<1.500 bytes). Ao primeiro sinal, o script
     para e grava o que já tiver em `results.json`.
4. Antes de rodar o script, uma **requisição manual exploratória** (via
   `curl`, fora do script, não contabilizada nas fases) foi feita para
   confirmar o formato de resposta de `html.duckduckgo.com/html/` e
   escrever o regex de parsing dos resultados (`class="result__a"
   href="..."`). Essa requisição teve sucesso: `HTTP 200`, 33.936 bytes,
   10 resultados, todos de `folha.uol.com.br` (query: `governo anuncia
   medida site:g1.globo.com OR site:folha.uol.com.br`).

---

## O que de fato aconteceu

| # | Origem | Query (resumida) | `n_domains` | Status | Corpo | Resultados | Nota |
|---|---|---|---:|---:|---:|---:|---|
| 1 | manual (`curl`, exploratório) | `governo anuncia medida site:g1.globo.com OR site:folha.uol.com.br` | 2 | 200 | 33.936 bytes | 10 | OK — usado só para validar o parsing |
| 2 | `search_ddg.py`, fase A, primeira query | `Governo federal anuncia isenção imposto renda quem ganha site:g1.globo.com OR site:oglobo.globo.com OR site:folha.uol.com.br` | 3 | **202** | 14.439 bytes | **0** | **BLOQUEIO** — parou aqui |

Nada além disso foi enviado a `html.duckduckgo.com` nesta rodada. A fase A
não avançou para `n_domains=5` em diante; a fase B (as 20 buscas
temáticas) **não chegou a começar**.

`results.json` e `run_log.txt` (log bruto da execução) documentam o
estado exato no momento da parada.

---

## Análise do sinal de bloqueio

- `HTTP 202` não é uma resposta normal de `html.duckduckgo.com/html/`
  para uma busca — o esperado é `200` com o HTML de resultados
  (confirmado pela requisição manual, item 1 da tabela).
- O corpo de 14.439 bytes não é vazio, mas não continha nenhum link
  `class="result__a"` — ou seja, não é uma página de "0 resultados"
  normal (que ainda teria a estrutura de busca), é outra coisa (provável
  página de checagem/challenge).
- É **exatamente o mesmo padrão** (`202` + corpo sem conteúdo útil) que
  o Spike 3 registrou para `espn.com.br` como bloqueio de bot-detection
  — reforça que `202` com corpo anômalo é uma assinatura real de bloqueio
  nesse tipo de infraestrutura, não coincidência.
- A requisição manual (`curl`) minutos antes, com uma query quase igual
  (2 domínios em vez de 3, texto de afirmação diferente), funcionou sem
  problema. Isso é consistente com bloqueio por **fingerprint do
  cliente HTTP** (a biblioteca Python `requests` tem assinatura
  TLS/HTTP diferente de `curl` — ordem de headers, ausência de suporte a
  HTTP/2, ausência de headers tipo `Sec-Fetch-*` que navegadores reais
  enviam) mais do que por volume de requisições — só 2 requisições
  totais foram feitas nesta sessão inteira antes do bloqueio aparecer.
- **Não foi possível confirmar com mais certeza** porque o script não
  salvou o corpo bruto da resposta bloqueada em disco (só o tamanho) — o
  script parou antes de eu decidir investigar mais, e investigar mais
  teria significado enviar outra requisição, o que as instruções pedem
  para não fazer.

---

## Respostas às perguntas da tarefa

- **Taxa de sucesso das buscas automatizadas:** 0/1 requisição da fase A
  teve sucesso (0%); a fase B nunca rodou. Amostra insuficiente para uma
  taxa confiável — o resultado é "bloqueou na primeira tentativa real",
  não uma taxa percentual robusta.
- **Taxa de resultados dentro da allowlist:** não mensurável — a única
  requisição automatizada que retornou resultados de verdade foi a
  manual/exploratória (10/10 dentro do subconjunto testado, mas com
  query manual fora do desenho formal do spike).
- **Limite prático de domínios por query (`site:` `OR`):** **não
  determinado**. A fase A parou no primeiro ponto testado
  (`n_domains=3`), antes de haver qualquer sinal de degradação por
  tamanho de query — o bloqueio não tem relação aparente com o número de
  domínios (3 é um valor baixo).
- **Sinal de instabilidade/bloqueio:** sim, um bloqueio (`HTTP 202`,
  corpo sem resultados) na primeira requisição automatizada da sessão,
  igual ao padrão já visto no Spike 3 para `espn.com.br`.
- **Requisições feitas até o bloqueio:** 1 requisição automatizada (a
  primeira da fase A) + 1 requisição manual exploratória anterior e
  bem-sucedida (não fazia parte do desenho formal de teste).

---

## Recomendação final

**Inviável tal como testado — com ressalva de amostra pequena.**

O risco descrito em §7.1/§7.2 do `spec.md` ("Bloqueio/rate-limit do
scraping do DDG") **se materializou imediatamente**, na primeira
requisição automatizada real feita nesta sessão, não depois de dezenas
de buscas. Isso é um resultado mais grave do que "instável sob uso
intenso" — sugere que mesmo o uso leve e espaçado que o app faria pode
esbarrar em bloqueio dependendo de como a requisição HTTP é montada no
cliente (aqui, `requests` em Python; o app real usaria `URLSession` em
Swift, que tem sua própria assinatura TLS/HTTP — pode se comportar
diferente, melhor ou pior, não testado).

Dado que:
- este é o único provedor de busca da spec, sem API paga como
  alternativa (DT-11 revisada);
- a amostra é pequena (1 bloqueio em 1 tentativa automatizada) e o
  spike foi interrompido exatamente como instruído ao primeiro sinal,
  então **não dá para descartar que tenha sido um evento pontual**
  (ex: um IP/rede específico sinalizado, um horário de maior triagem
  anti-bot, etc.) em vez de bloqueio sistemático;

**não estou concluindo "provado inviável para sempre"**, e sim que **a
evidência coletada não sustenta "viável para produção"** com confiança.
Não tentei contornar o bloqueio (proxy, rotação de User-Agent, retry
imediato) — isso ficou fora do escopo deste spike, como instruído.

Esta é uma decisão que cabe a você: as opções que vejo, sem implementar
nenhuma delas, são (a) repetir o teste em outro dia/rede para descartar
coincidência antes de decidir; (b) aceitar o risco e seguir com DT-11
revisada mesmo assim, com degradação elegante e mensagem clara ao
usuário quando a busca falhar (mitigação já prevista em §7.1); ou (c)
reabrir a decisão de provedor de busca (DT-11). Não escolhi nenhuma
dessas por conta própria.

---

## O que este spike NÃO fez

- **Não determinou o limite prático de domínios por query** — a fase A
  parou no primeiro valor testado.
- **Não completou as 20 buscas temáticas da fase B** — não chegaram a
  rodar.
- **Não tentou contornar o bloqueio** de nenhuma forma (proxy, rotação
  de User-Agent, retry, espera e nova tentativa) — fora de escopo por
  instrução explícita.
- **Não testou `URLSession`/Swift real** — o sinal de bloqueio veio de
  um cliente Python (`requests`); o comportamento do app real (Swift,
  `URLSession`) pode ser igual, melhor ou pior — não foi medido.
- **Não decide o destino de DT-11 nem implementa nenhuma mitigação**
  (cache, retry, mudança de provedor) — apenas relata o que ocorreu.
- **Não editou `spec.md`** além do que já estava coberto pela Tarefa 1.

---

## Como reproduzir

```bash
cd spikes/04-ddg-scraping
python3 -m venv .venv && source .venv/bin/activate
pip install requests
python search_ddg.py    # roda fase A e, se não bloquear, fase B -> results.json
```

Aviso: rodar isso de novo é uma nova tentativa de scraping real contra
`html.duckduckgo.com` — trate com o mesmo cuidado do spike original (não
usar em rajada, parar ao primeiro sinal de bloqueio).

Scripts: [`domains.py`](./domains.py) (allowlist de 30 domínios),
[`queries.py`](./queries.py) (20 afirmações + extração trivial de
keywords), [`search_ddg.py`](./search_ddg.py) (fases A e B, detecção de
bloqueio). Resultado bruto em [`results.json`](./results.json) e log de
execução em [`run_log.txt`](./run_log.txt).
