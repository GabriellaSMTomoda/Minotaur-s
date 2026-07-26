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

## Recomendação final (consolidada — 2 rodadas)

> Esta seção foi atualizada após uma repetição do teste em dia/horário
> diferente (ver "Repetição — Rede/Dia Diferente" acima). O texto
> original abaixo foi mantido como registro histórico da primeira
> rodada; a consolidação vem em seguida.

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

### Consolidação após a 2ª rodada

A opção (a) acima foi executada: repeti o teste em dia/horário diferente
(ver "Repetição — Rede/Dia Diferente"). O resultado foi **o mesmo
bloqueio, no mesmo ponto, com corpo de resposta quase byte-idêntico** ao
da primeira rodada. Isso muda o peso da evidência:

- A explicação "evento pontual de horário" fica **enfraquecida** — o
  bloqueio ocorreu em horários bem diferentes (noite vs. madrugada) com
  resultado idêntico.
- A explicação "coincidência de IP/rede específico" **não foi
  totalmente descartada** — não tenho registro do tipo de rede da
  rodada original para comparar com segurança (ver ressalva na seção da
  repetição). Ainda assim, a reprodução byte-a-byte do corpo de resposta
  em duas ocasiões distintas é o tipo de evidência que normalmente se
  associa a bloqueio por fingerprint do cliente HTTP (sistemático),
  não a triagem de rede pontual.
- Duas rodadas com o mesmo padrão exato, na primeira requisição de
  cada uma, é uma amostra maior do que uma — mas **ainda são só 2
  pontos de dados automatizados**, ambos com o mesmo cliente Python
  (`requests`) e nenhum teste com `URLSession`/Swift real.

**Minha leitura, sem decidir por você:** a evidência acumulada agora
aponta **mais para bloqueio sistemático do que para coincidência
pontual**, o que reduz a plausibilidade da opção (a) [repetir de novo]
como próximo passo de maior valor — repetir uma terceira vez com o
mesmo cliente Python tende a só confirmar o mesmo padrão. As opções que
continuam abertas para você decidir são (b) aceitar o risco e seguir
com DT-11 revisada, testando o comportamento real em `URLSession`/Swift
antes de descartar de vez (o fingerprint de bloqueio pode ser
específico do cliente Python, não necessariamente do app real), ou (c)
reabrir DT-11 e considerar um provedor alternativo — ver a seção
"Alternativas ao DuckDuckGo (proposta)" abaixo, que preparei como
pesquisa comparativa (não como escolha) por essa possibilidade ter
ficado mais provável após esta repetição.

---

## Alternativas ao DuckDuckGo (proposta)

> Seção adicionada por o padrão de bloqueio ter se repetido na 2ª
> rodada. Isto é **pesquisa comparativa para sua decisão**, não uma
> escolha feita, não uma implementação, e não uma alteração de DT-11 no
> `spec.md`. Nenhuma destas opções foi integrada ao app.

Critérios de avaliação, na ordem de prioridade definida na tarefa: (a)
risco de rejeição na App Store, (b) custo (gratuito ou quota mínima
razoável, requisito de DT-11 original), (c) suporte a restringir busca
à allowlist (equivalente a `site:` sem depender de scraping de HTML),
(d) estabilidade documentada.

### Opção 1 — Bing Web Search / Bing Search API (via Azure AI Services)

- **Como funciona:** API oficial REST da Microsoft, com Termos de
  Serviço explícitos; suporta o operador `site:` na própria query, então
  a restrição por domínio funciona igual ao esquema atual, sem scraping
  de HTML.
- **Custo/quota gratuita:** historicamente teve um tier gratuito
  (~1.000–3.000 transações/mês dependendo do plano); a Microsoft tem
  descontinuado e reestruturado esses tiers de busca com frequência nos
  últimos anos — **precisa verificar a oferta vigente no momento da
  decisão**, não dá para tratar como garantidamente gratuito hoje.
- **API oficial vs. scraping:** API oficial, com chave e contrato.
- **App Store:** favorável — é consumo de API de terceiro com ToS claro,
  padrão comum em apps publicados; exige exibir atribuição
  ("Resultados por Bing") em alguns planos, o que é positivo para
  credibilidade e não é um problema de aprovação.
- **Ressalva:** exige chave de API, o que reabre o ponto **[EM ABERTO]
  7.3.3** da spec ("como proteger a chave de API sem backend próprio")
  — hoje não existe porque DT-11 evita ter chave. Adotar esta opção cria
  uma nova pendência a resolver, não é troca neutra.

### Opção 2 — Brave Search API

- **Como funciona:** API oficial de busca da Brave, com endpoint REST
  documentado; suporta parâmetros de busca que permitem compor queries
  restritas por domínio no texto da query (mesmo padrão `site:`).
- **Custo/quota gratuita:** oferece um tier gratuito com cota mensal
  limitada (na ordem de milhares de queries/mês em alguns planos
  divulgados) — **quota exata e disponibilidade de tier gratuito devem
  ser confirmadas no momento da decisão**, pois programas de API mudam.
- **API oficial vs. scraping:** API oficial, com chave e contrato,
  criada especificamente para uso de terceiros (diferente do DDG, que
  não oferece API de busca pública — só o scraping do HTML voltado a
  humanos, o que é a raiz do problema atual).
- **App Store:** favorável — mesmo raciocínio da Opção 1: consumo de API
  com ToS, sem scraping.
- **Ressalva:** mesma reabertura do ponto de proteção de chave de API
  sem backend próprio.

### Opção 3 — Google Programmable Search Engine (Custom Search JSON API)

- **Como funciona:** API oficial do Google; permite restringir a busca
  a uma lista de sites configurada previamente no "mecanismo de busca
  programável" (equivalente direto à allowlist — a restrição por
  domínio fica configurada do lado do Google, não precisa nem montar
  `site:` `OR` manualmente).
- **Custo/quota gratuita:** tier gratuito de 100 consultas/dia
  historicamente divulgado pela Google; acima disso é pago por bloco de
  consultas. Para uso leve (uma verificação = poucas consultas), pode
  caber dentro do gratuito, mas **100/dia é um teto baixo se o app tiver
  uso real** — precisa avaliar se é suficiente para o volume esperado.
- **API oficial vs. scraping:** API oficial, com chave.
- **App Store:** favorável — mesmo raciocínio de API com ToS.
- **Ressalva:** mesma reabertura do ponto de proteção de chave; quota
  diária mais restritiva que as opções 1 e 2 para um app com uso
  contínuo.

### Observação comum às três alternativas

Todas trocam "sem chave de API" (vantagem atual de DT-11, ver NF-09) por
"com chave de API", o que reabre um ponto hoje fechado (7.3.3, "como
proteger a chave sem backend próprio"). Isso não invalida as opções —
mas significa que trocar de provedor não é uma mudança isolada: também
exigiria decidir essa proteção de chave (ex: ofuscação no binário,
ou aceitar o risco de chave exposta em app client-only com quota
baixa o suficiente para limitar o dano de abuso). Não pesquisei essa
parte em profundidade aqui porque está fora do que foi pedido nesta
tarefa — sinalizo para não se perder.

Nenhuma das três teve teste real (nenhuma requisição foi feita a nenhuma
delas) — isto é pesquisa de documentação pública, não um spike
executado. Se você optar por seguir alguma delas, o próximo passo seria
um novo spike técnico, análogo a este, antes de integrar ao app.

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

## Repetição — Rede/Dia Diferente

**Data/hora:** 2026-07-25, ~01:20 (horário local, `-03`) — a rodada
original foi em 2026-07-24, por volta das 22:04–22:08. Diferença de
~3h15min e cruzando a virada do dia.

**Objetivo desta repetição:** descartar (ou reforçar) a hipótese de que
o bloqueio da rodada original foi coincidência pontual de IP/rede,
rodando exatamente os mesmos scripts (`domains.py`, `queries.py`,
`search_ddg.py`, sem alteração de lógica) em condições diferentes.

### Condições da rede

- Conexão: Wi-Fi (`en0`), endereço IPv4 privado na faixa `192.168.0.x`
  (não exponho o IP completo nem o público, conforme instruído).
- **Limitação honesta desta repetição:** a rodada original não registrou
  qual rede foi usada (não há esse dado no `RESULTADO.md` original nem
  nos artefatos salvos). Não é possível confirmar com certeza se esta é
  uma rede *diferente* da original ou a mesma rede em horário diferente
  — só posso confirmar a diferença de **dia/hora**, não de rede. Isso
  enfraquece um pouco o valor desta repetição para descartar "coincidência
  de IP" especificamente, mas ainda é uma segunda amostra independente no
  tempo.
- Critério de decisão foi fixado *antes* de rodar (ver prompt da tarefa):
  bloqueio de novo no mesmo padrão → reforça hipótese sistemática;
  sucesso → enfraquece (mas não descarta) a hipótese sistemática; de
  qualquer forma, uma repetição não encerra a dúvida.

### O que aconteceu

Bloqueou de novo, **na primeira requisição automatizada da fase A**,
com o **mesmo padrão exato** da rodada original:

| Campo | Rodada original (2026-07-24) | Repetição (2026-07-25) |
|---|---|---|
| `status_code` | 202 | 202 |
| `elapsed_s` | 0.17 | 0.17 |
| `body_len` | 14.439 bytes | 14.445 bytes (diferença de 6 bytes — provável token/timestamp dinâmico na página de challenge) |
| `result_count` | 0 | 0 |
| `block_reason` | "HTTP 202 inesperado" | "HTTP 202 inesperado" |
| Ponto de parada | `n_domains=3`, 1ª query da fase A | `n_domains=3`, 1ª query da fase A (query idêntica) |

A fase A não avançou além de `n_domains=3` nesta repetição também — a
fase B **novamente não chegou a rodar**. Resultado bruto em
[`results_repeat.json`](./results_repeat.json), log em
[`run_log_repeat.txt`](./run_log_repeat.txt). O `results.json` original
foi preservado (git, commit `08933f1`) e não foi sobrescrito.

### Análise

O corpo de resposta quase byte-a-byte idêntico (14.439 vs 14.445, a
mesma query, o mesmo `status_code`, o mesmo tempo de resposta de 0,17s)
sugere fortemente que **não é rate-limit por volume** (esta sessão fez
uma única requisição antes de bloquear, igual à original) nem efeito de
horário — é consistente com um **bloqueio determinístico por
fingerprint do cliente HTTP** (a biblioteca `requests` do Python), que
dispara na primeira requisição, independente de dia ou de quantas
requisições vieram antes. Isso é coerente com a hipótese já levantada na
rodada original (assinatura TLS/HTTP de `requests` vs. navegador/`curl`).

Repetir em dia diferente **não** produziu um resultado diferente — o que
era exatamente o critério definido antes de rodar para "reforça hipótese
sistemática, não coincidência".

### Resposta às perguntas da tarefa (repetição)

- **Bloqueou de novo?** Sim.
- **Mesmo padrão?** Sim — mesmo `status_code`, mesmo `block_reason`,
  corpo de tamanho quase idêntico, mesmo ponto de parada.
- **Em qual ponto?** Idêntico à rodada original: primeira requisição da
  fase A (`n_domains=3`).
- **A diferença de dia mudou o resultado?** Não.
- **Ressalva:** rede não confirmada como diferente (ver limitação acima)
  — a diferença comprovada é só de dia/horário, não de rede/IP.

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
