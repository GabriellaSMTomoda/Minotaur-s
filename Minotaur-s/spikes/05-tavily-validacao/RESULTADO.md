# SPIKE 5 — Resultado: Validação Técnica da Tavily como Provedor de Busca

**Data:** 2026-07-26
**Objetivo:** confirmar, com chamadas reais à API, se a Tavily
(https://tavily.com) se comporta como a documentação promete, antes de
autorizar a troca de DT-11/RF-02.3/RF-04 na spec — substituindo o
scraping de `html.duckduckgo.com`, que bloqueou de forma sistemática em
2 clientes HTTP diferentes (Python `requests` e `URLSession`/Swift em
device físico — ver [`spikes/04-ddg-scraping/RESULTADO.md`](../04-ddg-scraping/RESULTADO.md)
e [`spikes/04b-ddg-urlsession/RESULTADO.md`](../04b-ddg-urlsession/RESULTADO.md)).

**Este NÃO é um spike de decisão de provedor** — a Tavily já foi
escolhida fora deste repositório (pesquisa de mercado). Este spike só
valida tecnicamente. Não decide arquitetura de proteção de chave de
API, não implementa nada do app principal, não edita `spec.md`.

Reusa a allowlist de 30 domínios e as 20 afirmações de teste dos Spikes
3/4 ([`domains.py`](./domains.py), [`queries.py`](./queries.py) — cópias
byte-a-byte de `spikes/04-ddg-scraping/`, nenhum dataset novo).

---

## Veredito rápido

> **Viável para produção, com uma ressalva importante confirmada
> empiricamente: `include_domains` não é um filtro 100% rígido.** Em
> 4 das 20 buscas da Fase 1 (20%), a Tavily retornou resultados de fora
> da allowlist mesmo com `include_domains` restrito aos 30 domínios —
> em 2 dessas 4 buscas, **100% dos resultados retornados vieram de fora
> da allowlist** (Wikipédia, dicionários online, sites institucionais
> não relacionados). Isso não invalida a Tavily como provedor — mas
> confirma que o RF-03.5 da spec ("resultados fora da allowlist devem
> ser descartados, mesmo que retornados pelo buscador") **não é
> redundância defensiva, é um requisito obrigatório** para este
> provedor especificamente. Fora esse ponto, os demais resultados são
> fortes: tempo de resposta médio de 1,6s, formato de resposta rico
> (título, URL, snippet, score), tratamento de erro limpo (401 JSON
> para chave inválida), e "zero resultados" é um estado real e
> alcançável (não testado com sucesso pelo Spike 4 em nenhum provedor
> até agora).

---

## Metodologia

Script único ([`search_tavily.py`](./search_tavily.py)), 4 fases + 1
teste adicional, todas com `search_depth="basic"` (a opção mais barata,
1 crédito documentado por chamada) e `max_results` igual ao que RF-04.3
especifica para o app (5), exceto onde indicado:

1. **Fase 1** — 20 buscas, uma por afirmação de `queries.py`, cada uma
   com `include_domains` = allowlist completa (30 domínios de uma vez —
   o caso exato que bloqueou o DDG no Spike 4/4b). Query enviada = texto
   integral da afirmação (todas têm menos de 200 caracteres, então
   RF-02.1 não se aplica a nenhuma delas — nenhuma extração de keywords
   foi necessária ou usada aqui, diferente do Spike 4).
2. **Fase 2** — teste de exclusão: 3 buscas com um domínio **fora** da
   allowlist (`wikipedia.org`, `cnn.com`, `reuters.com` — escolhidos por
   não serem substring/superstring de nenhum dos 30 domínios da
   allowlist, evitando falso positivo de subdomínio) adicionado a
   `include_domains` junto dos 30, `max_results=10`. Para cada uma, uma
   busca de controle isolada (`include_domains=[domínio_extra]` sozinho,
   `max_results=5`) confirma que o domínio tem conteúdo indexável sobre
   o tema — sem esse controle, "o domínio não apareceu" poderia
   significar só "não havia conteúdo relevante lá", não "foi excluído
   de verdade".
3. **Fase 3** — teste de "nenhum resultado" (RF-04.4): uma busca com uma
   frase sem sentido mas contendo palavras reais em português, e uma
   segunda busca (adicionada depois de ver o resultado da primeira) com
   string puramente aleatória, sem nenhuma palavra real, para isolar o
   comportamento.
4. **Fase 4** — uma busca com chave de API inválida, para documentar o
   formato do erro de autenticação (relevante para RF-10).

Autenticação usada: header `Authorization: Bearer <chave>` **e** campo
`api_key` no corpo JSON simultaneamente (compatibilidade defensiva com
variações de versão documentadas pela Tavily) — a chave real nunca foi
impressa em nenhum log ou nesta documentação.

⚠️ **Nota de processo, não de resultado:** durante a preparação do
ambiente (antes de qualquer chamada à API), um comando de depuração meu
(`grep` no arquivo de perfil do shell) imprimiu o valor completo da
chave no terminal por engano, expondo-a nesta sessão de trabalho. O
usuário foi avisado imediatamente e optou por manter a mesma chave em
vez de rotacioná-la. Registrado aqui por transparência, não afeta os
resultados técnicos abaixo.

---

## Fase 1 — 20 buscas com allowlist completa (30 domínios)

| Métrica | Resultado |
|---|---|
| Buscas com HTTP 200 | 20/20 (100%) |
| Buscas com pelo menos 1 resultado | 20/20 (100%) |
| Total de resultados retornados | 99 (19 buscas com 5, 1 busca com 4) |
| Buscas com **algum** resultado fora da allowlist | **4/20 (20%)** |
| Resultados individuais fora da allowlist | **18/99 (18,2%)** |
| Buscas com **100%** dos resultados fora da allowlist | 2/20 (10%) |
| Tempo de resposta | min 1,20s / méd 1,62s / máx 2,41s |

### As 4 buscas com vazamento de domínio

| Afirmação (resumida) | Resultados totais | Fora da allowlist | Hosts fora |
|---|---:|---:|---|
| "Governo federal anuncia isenção de imposto de renda..." | 5 | 4 | `en.wikipedia.org`, `governo.it`, `youtube.com`, `collinsdictionary.com` |
| "Inflação medida pelo IPCA acelera..." | 5 | 4 | `portal-da-inflacao-ibre.fgv.br`, `br.investing.com`, `debit.com.br`, `pt.wikipedia.org` |
| "União Europeia fecha acordo comercial com o Mercosul..." | 5 | **5** | `dictionary.cambridge.org`, `pt.wikipedia.org`, `linguee.com.br`, `dicio.com.br`, `sinonimos.com.br` |
| "Papa faz visita oficial ao Brasil..." | 5 | **5** | `papa.com`, `app.papa.com` (2x), `en.wiktionary.org`, `youtube.com` |

**Padrão observado:** as 4 buscas que vazaram têm em comum uma palavra
de alta frequência/genérica na afirmação ("governo", "inflação",
"união", "papa") que também é uma palavra de dicionário comum ou nome
de empresa/produto não relacionado (`papa.com` é uma empresa de
transporte de idosos nos EUA, não tem relação com o Papa). A hipótese
mais plausível, **não confirmada com certeza por este spike**: quando a
Tavily não encontra resultados suficientes e bem pontuados dentro dos
domínios restritos para preencher `max_results`, ela preenche as vagas
restantes com conteúdo de fora da restrição (definições de dicionário,
Wikipédia, sites institucionais) em vez de retornar menos resultados.

### Evidência a favor da hipótese "preenchimento por falta de resultados suficientes"

Repeti a mesma afirmação que vazou 4/5 na Fase 1 ("Governo federal
anuncia isenção...") na Fase 2, mas com `include_domains` = 30 domínios
**+ `wikipedia.org`** e `max_results=10` (em vez de 5). Resultado:
**10/10 resultados vieram de dentro dos 30 domínios da allowlist**
(`exame.com`, `camara.leg.br`, `correiobraziliense.com.br`,
`oglobo.globo.com`, `www1.folha.uol.com.br`, `www12.senado.leg.br` —
`wikipedia.org`, apesar de explicitamente permitido, nem apareceu).
Ou seja: com uma janela de resultados maior, a mesma consulta encontrou
resultado genuíno suficiente dentro da allowlist e não precisou
"completar" com conteúdo externo. **Isso não foi testado de forma
controlada o bastante para afirmar causalidade** (mudei dois fatores ao
mesmo tempo — `max_results` e a lista de domínios), mas é consistente
com a hipótese acima e é um dado acionável: **pedir mais resultados do
que os 5 finais desejados (RF-04.3) e truncar localmente depois do
filtro do RF-03.5 pode reduzir a taxa de vazamento** — fica registrado
como observação para quem implementar RF-04, não como decisão.

---

## Fase 2 — Teste de exclusão explícita

| Domínio extra testado | Apareceu no misto (30 + extra, max=10)? | Resultado do controle isolado (só o domínio extra) |
|---|---|---|
| `wikipedia.org` | **Não** | 5/5 resultados de `pt.wikipedia.org` — domínio tem conteúdo indexado sobre o tema |
| `cnn.com` | **Não** | 5/5 resultados de `cnnespanol.cnn.com` — domínio tem conteúdo indexado sobre o tema |
| `reuters.com` | **Não** | 5/5 resultados de `reuters.com` — domínio tem conteúdo indexado sobre o tema |

**Confirmado: quando um domínio é explicitamente restrito de
`include_domains`, ele não aparece — 0/3 vazamentos**, e o controle
isolado confirma que a ausência é uma restrição real, não falta de
conteúdo. Isso é aparentemente contraditório com a Fase 1 (onde
domínios *nem sequer mencionados* em `include_domains`, como
`wikipedia.org`, apareceram) — a leitura mais consistente com os dados
das duas fases é que o vazamento da Fase 1 não é sobre "domínios fora
da lista vazarem por padrão", e sim sobre **preenchimento de vagas
quando `max_results` não é atingido com matches genuínos dentro do
domínio restrito** (ver hipótese acima). Domínio explicitamente
presente em `include_domains` (Fase 2) parece competir normalmente pelo
ranking; domínio ausente (Fase 1) só aparece como "última opção" de
preenchimento.

**Observação incidental (fora do escopo desta tarefa, registrada para
quem implementar RF-03.5):** no teste com `reuters.com`, um dos hosts
retornados foi `ilhabela.sp.gov.br` (site de uma prefeitura), contado
como "dentro da allowlist" pela minha função de matching porque
`gov.br` está na allowlist e a regra de correspondência é por sufixo
(`host.endswith("." + "gov.br")`). Isso é tecnicamente correto perante
RF-03.3, mas significa que **qualquer subdomínio `*.gov.br` — inclusive
de uma prefeitura pequena — passa no filtro da allowlist**, o que pode
não ser a intenção original de ter `gov.br` na lista (provavelmente
pensado para o portal federal). Não é um problema da Tavily, é uma
característica da allowlist herdada de `trustedDomains`; sinalizo sem
decidir nada.

---

## Fase 3 — Teste de "nenhum resultado" (RF-04.4)

| Tentativa | Query | Resultado |
|---|---|---|
| 1ª | Frase sem sentido, mas com palavras reais em português ("teste deliberado sem nenhuma noticia correspondente...") | **5 resultados retornados** — a Tavily encasou nas palavras reais da frase ("teste", "notícia") e trouxe artigos genuínos porém irrelevantes ao propósito do teste (ex: notícia de Fórmula 1 contendo a palavra "teste") |
| 2ª (ajuste) | String puramente aleatória, sem nenhuma palavra real (`zzxqvbnmqwpfjtlorkhsdcbgy 9284710583 xkcvbnmqwertyuiopasdfghjklzx...`) | **0 resultados, HTTP 200, `results: []`** |

**Confirmado: "zero resultados" é um estado real e alcançável** —
`status_code=200` com `results` vazio, não um erro. Isso é
estruturalmente fácil de mapear para RF-04.4 (`NÃO ENCONTRADO`).

**Achado relevante para RF-04.4 na prática:** o motor da Tavily parece
fazer correspondência semântica/por palavra-chave bastante permissiva —
uma consulta "sem sentido" só produziu zero resultados quando **nenhuma
palavra real** estava presente. Para afirmações de usuário reais (que
sempre terão palavras reais), é provável que o caminho `NÃO ENCONTRADO`
seja acionado com menos frequência via Tavily do que seria fazendo uma
correspondência mais literal — o filtro de relevância de fato pode
acabar recaindo mais sobre a etapa de similaridade de embeddings
(RF-06) do que sobre "buscador não achou nada". Isso é uma observação
de comportamento, não uma decisão de arquitetura.

---

## Fase 4 — Chave de API inválida

Uma chamada com chave inválida (`tvly-INVALID-TEST-KEY-...`):

```json
{
  "status_code": 401,
  "error_payload": {
    "detail": { "error": "Unauthorized: missing or invalid API key." }
  }
}
```

**Erro limpo, estruturado, HTTP-status correto (401) e mensagem
inequívoca** — fácil de distinguir de "sem resultados" ou "sem rede"
para fins de RF-10. Rate limit **não foi testado deliberadamente**
(instrução explícita da tarefa para não forçar isso além do razoável) —
não ocorreu naturalmente durante as ~29 chamadas desta sessão, dentro
da cota gratuita de 1.000/mês.

---

## Formato de resposta disponível

Campos no nível raiz da resposta: `query`, `answer` (null — só
preenchido se `include_answer=true` for pedido, não testado aqui),
`follow_up_questions`, `images`, `request_id`, `response_time`,
`results`.

Campos em cada item de `results`:

| Campo | Disponível? | Observação |
|---|---|---|
| `title` | Sim | Título da página/artigo |
| `url` | Sim | URL direta (não é redirecionador, diferente do DDG — ver Spike 4b) |
| `content` | Sim | Snippet/trecho — tamanho variável observado: 100 a ~2.200 caracteres |
| `score` | Sim | Score de relevância (0–1) atribuído pela Tavily |
| `raw_content` | Presente mas `null` em 100% das respostas | Só preenchido se `include_raw_content=true` for pedido — não testado neste spike |

**Isto é só um registro do que está disponível — não decide se
`content` substitui a extração própria de RF-05.2.** Fica para decisão
futura, como instruído.

---

## Créditos consumidos

A API **não expõe consumo de créditos em nenhum header de resposta**
(verificado em todas as ~29 chamadas — nenhum header com `credit`,
`usage`, `limit` ou `remaining` no nome apareceu) nem no corpo JSON.
Não há como instrumentar consumo de créditos a partir da própria
resposta da API — monitoramento real de cota precisa ser feito no
painel da Tavily (`app.tavily.com`), não programaticamente.

Chamadas realizadas nesta sessão (todas `search_depth="basic"`, a
opção mais barata segundo a documentação pública da Tavily — 1 crédito
por chamada básica, 2 por `advanced`):

| Fase | Chamadas |
|---|---:|
| Smoke test inicial (validação de autenticação) | 1 |
| Fase 1 (20 afirmações) | 20 |
| Fase 2 (3 mistas + 3 isoladas) | 6 |
| Fase 3 (2 variantes de "sem resultado") | 2 |
| Fase 4 (chave inválida) | 1 (provavelmente não cobrado — falhou na autenticação antes de qualquer busca) |
| **Total com chave válida** | **29** |

Com a cota de 1.000 créditos/mês gratuitos, 29 chamadas é ~2,9% da
cota mensal — folga enorme para uma segunda rodada de validação, se
necessário. **Número exato de créditos efetivamente debitados não foi
confirmado por este spike** (a API não expõe isso) — recomendo
conferir o painel da Tavily para ter o número real antes de projetar
custo por verificação em produção.

---

## Respostas diretas às perguntas da tarefa

- **Taxa de sucesso das 20 buscas:** 20/20 (100%) retornaram HTTP 200
  com pelo menos 1 resultado.
- **`include_domains` restringe de verdade?** **Não 100% das vezes.**
  Confirmado com exclusão explícita (Fase 2: 0/3 vazamentos quando o
  domínio é conhecido e deliberadamente deixado de fora), mas **20% das
  buscas da Fase 1 vazaram** domínios que nem estavam no radar da
  allowlist, aparentemente como preenchimento quando não há matches
  suficientes dentro do domínio restrito. **RF-03.5 (filtro local
  obrigatório) é indispensável com este provedor, não apenas defesa em
  profundidade.**
- **Tempo de resposta médio:** 1,62s (Fase 1, 20 chamadas
  back-to-back), variando de 1,20s a 2,41s. Bem dentro do orçamento de
  NF-03 (< 15s para o fluxo completo).
- **Créditos consumidos por chamada:** não exposto pela API; documentação
  pública da Tavily indica 1 crédito por busca `basic`. ~29 chamadas
  nesta sessão, dentro da cota gratuita de 1.000/mês.
- **Formato de resposta:** título, URL, snippet (`content`), score de
  relevância — ver seção acima.
- **Nenhum resultado (RF-04.4):** estado real e alcançável
  (`status_code=200`, `results: []`) — mas só ocorre de forma confiável
  quando a query não contém nenhuma palavra real; para afirmações reais
  de usuário, é provável que a Tavily quase sempre retorne algo.
- **Chave inválida:** erro 401 limpo e estruturado.
- **Rate limit:** não testado deliberadamente; não ocorreu
  naturalmente no volume desta sessão.

---

## Recomendação final

**Viável para produção**, com uma condição que já está coberta pela
spec, mas que este spike eleva de "boa prática" para "requisito
obrigatório confirmado empiricamente":

> RF-03.5 ("resultados de busca cujo domínio não esteja na allowlist
> devem ser descartados, mesmo que retornados pelo buscador") **deve
> ser implementado e testado como parte central do pipeline**, não como
> filtro cosmético — sem ele, 1 em cada 5 verificações (baseado nesta
> amostra de 20) poderia apresentar fontes fora da allowlist ao
> usuário, incluindo casos onde 100% das "fontes" seriam, na prática,
> verbetes de dicionário ou sites sem relação com jornalismo.

Fora esse ponto, todos os outros aspectos testados (disponibilidade,
tempo de resposta, formato de dados, tratamento de erro, estado de
"zero resultados", exclusão explícita de domínios, custo) se
comportaram de forma previsível e dentro do que a spec precisa. Não
houve nenhum bloqueio, CAPTCHA ou sinal de anti-bot — diferença radical
em relação aos Spikes 4/4b.

**Sugestão de próximo passo (não decidida aqui):** considerar pedir
`max_results` maior que 5 na chamada à API (ex: 8–10) e truncar
localmente para 5 **depois** do filtro de allowlist (RF-03.5), em vez
de pedir `max_results=5` diretamente — a Fase 1 sugere que isso reduz a
chance de a Tavily preencher vagas com conteúdo fora do escopo. Fica
como observação para quem implementar RF-04, não como decisão deste
spike.

---

## O que este spike NÃO fez

- Não testou `search_depth="advanced"` (mais caro, 2 créditos/chamada) —
  não foi pedido, e o comportamento de vazamento observado pode ser
  diferente nesse modo. Fica como pergunta em aberto para quem for
  implementar.
- Não confirmou o número exato de créditos debitados no painel da
  Tavily — a API não expõe isso; só documentou a contagem de chamadas
  feitas.
- Não testou rate limit deliberadamente.
- Não testou `include_answer` nem `include_raw_content`.
- Não decidiu se o campo `content` da resposta substitui a extração
  própria de RF-05.2 — apenas documentou que ele existe e seu tamanho
  típico.
- Não implementou nada do app principal, não editou `spec.md`, não
  decidiu arquitetura de proteção de chave de API.

---

## Como reproduzir

```bash
cd spikes/05-tavily-validacao
python3 -m venv .venv && source .venv/bin/activate
pip install requests
export TAVILY_API_KEY=sua_chave_aqui   # NUNCA cole a chave em código ou commit
python3 search_tavily.py               # roda as 4 fases -> results.json
```

Scripts: [`domains.py`](./domains.py) (allowlist de 30 domínios, cópia
do Spike 4), [`queries.py`](./queries.py) (20 afirmações, cópia do
Spike 4), [`search_tavily.py`](./search_tavily.py) (as 4 fases + teste
de exclusão). Resultado bruto completo (todas as chamadas, incluindo o
teste adicional de gibberish puro) em [`results.json`](./results.json),
log de execução em [`run_log.txt`](./run_log.txt).
