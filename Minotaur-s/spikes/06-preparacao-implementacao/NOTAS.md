# Notas de Preparação — Observações Órfãs dos Spikes 3, 4, 4b e 5

**Data:** 2026-07-26
**Objetivo:** listar, sem decidir nada, as observações técnicas que
ficaram registradas nos `RESULTADO.md` dos Spikes 3, 4, 4b e 5 como
"pendência/observação para quem implementar", mas que ainda não viraram
requisito formal em `spec.md`. Nenhum item aqui foi decidido por este
documento — cada um precisa de uma decisão explícita de quem mantém a
spec antes de virar RF/NF/DT.

Este documento não implementa nada, não edita `spec.md`, não toca em
`Verificador.swift`.

---

## 1. Do Spike 4b (`spikes/04b-ddg-urlsession/RESULTADO.md`)

### 1.1 Decodificação de URL de redirecionamento do DDG
O spike registrou como pendência: as respostas de `html.duckduckgo.com`
envolvem cada link em uma URL de redirecionamento própria
(`//duckduckgo.com/l/?uddg=<url-real-codificada>&...`), e seria
necessário decodificar o parâmetro `uddg` para obter o domínio real e
aplicar o filtro de allowlist (RF-03.5) corretamente.

**Status: não se aplica mais.** Confirmado no Spike 5
(`spikes/05-tavily-validacao/RESULTADO.md`, seção "Formato de resposta
disponível"): o campo `url` da resposta da Tavily é "URL direta (não é
redirecionador, diferente do DDG)". Com o provedor definitivo sendo a
Tavily (conforme contexto desta tarefa), esta pendência específica pode
ser descartada — não há URL de redirecionador a decodificar no fluxo
ativo.

---

## 2. Do Spike 3 (`spikes/03-extracao-texto/RESULTADO.md`)

### 2.1 Redução da allowlist de 34 para 30 domínios — decisão já aplicada ao código-fonte, mas nunca registrada como DT/RF na spec
O Spike 3 testou os 34 domínios então existentes em `trustedDomains` e
recomendou (sem decidir) **reavaliar** 4 domínios que falharam 100% por
bloqueio de bot no download (não por qualidade de extração):
`uol.com.br`, `espn.com.br`, `reuters.com`, `ibge.gov.br`.

Verifiquei o `trustedDomains` atual em
[`Minotaur-s/Views/Verificador.swift:61-92`](../../Minotaur-s/Views/Verificador.swift) —
**os 4 domínios já não estão na lista** (30 domínios hoje, exatamente
os 34 menos esses 4). Ou seja, a recomendação do Spike 3 já foi
aplicada na prática ao arquivo-fonte, mas:
- `spec.md` não tem nenhuma menção a essa redução (nenhuma ocorrência de
  "34" ou "30 domínios", nenhuma DT sobre o assunto);
- RF-03.1 diz que o conteúdo de `trustedDomains` "não muda nesta
  reconstrução" — o que é tecnicamente verdade em relação ao estado
  *atual* do arquivo, mas a spec nunca documentou que uma mudança de
  conteúdo (remoção desses 4) já aconteceu em algum momento antes desta
  tarefa.

Fica como observação, não como decisão: pode valer a pena a spec
registrar formalmente essa remoção (por que motivo, quando) para não
parecer uma divergência entre "spec diz que o conteúdo não muda" e "o
conteúdo já mudou uma vez, silenciosamente, antes desta spec existir".

### 2.2 `camara.leg.br` com falha intermitente (HTTP 500 em 1 de 3 URLs)
Registrado como instabilidade pontual de servidor, não bloqueio de bot
— mas nenhuma RF trata explicitamente de retry em caso de erro 5xx
transiente vs. descarte definitivo da fonte (RF-05.4 só cobre timeout
de 8s, não erro HTTP explícito seguido de possível sucesso em nova
tentativa). Fica como observação para quem implementar RF-05.

### 2.3 Biblioteca/abordagem de extração para Swift ainda não decidida
O spike comparou duas abordagens em **Python** (`trafilatura` venceu
57/86 comparações vs. heurística manual). O próprio `RESULTADO.md` é
explícito: isso não decide a biblioteca Swift real (SwiftSoup +
heurística própria, porte de algoritmo tipo Readability, ou outra
abordagem) — RF-05.2 permanece sem uma decisão de implementação
concreta sobre *como* extrair o texto principal em Swift, só que é
*viável* fazê-lo em HTML estático.

Vale registrar os 3 tipos de armadilha reais encontrados na heurística
manual (para quem for escrever a versão Swift, caso opte por heurística
própria em vez de portar uma lib):
1. Classes utilitárias de tema na tag raiz (`<html>`/`<body>`) batendo
   em denylist por substring (ex: `share`) e apagando a página inteira.
2. Nomes de classe enganosos (`-paywall-parent` no Estadão é o
   contêiner do conteúdo **gratuito**, não do conteúdo pago).
3. Wrappers de menu mobile que envolvem `<body>` inteiro
   (`navigation-menu__wrapper`, `js-mmenu-container`) — sem correção
   encontrada; nesses casos a heurística manual retorna vazio onde
   `trafilatura` funciona.

### 2.4 Paywall parcial (artigo com preview aberto + resto bloqueado) não testado
A amostra do Spike 3 (2-3 URLs por domínio, todas de matérias abertas)
não cobriu o caso de paywall parcial por artigo — `valor.globo.com` e
`estadao.com.br` têm paywall conhecido em parte do conteúdo, mas
nenhuma das URLs testadas disparou os sinais de paywall/JS deste spike.
RF-05.3 (descarte se texto < 200 caracteres) provavelmente cobre o caso
na prática (texto cortado no preview tende a ser curto), mas isso não
foi comprovado empiricamente — é uma suposição razoável, não um dado
medido.

---

## 3. Do Spike 4 (`spikes/04-ddg-scraping/RESULTADO.md`)

Este spike é sobre o provedor descartado (DDG) — as observações abaixo
são majoritariamente históricas, mantidas por transparência, não como
pendência ativa:

### 3.1 Seção "Alternativas ao DuckDuckGo (proposta)" — pesquisa comparativa não usada
O spike pesquisou (sem testar) Bing Web Search, Brave Search API e
Google Programmable Search como alternativas ao DDG, caso a decisão
fosse reabrir DT-11. Como a Tavily foi escolhida por pesquisa de mercado
fora deste repositório (conforme contexto desta tarefa), essa seção
ficou puramente histórica — nenhuma das 3 alternativas pesquisadas foi
adotada nem precisa ser reavaliada, a menos que a Tavily seja
descartada no futuro.

### 3.2 Limite prático de domínios por query `site:`/`OR` nunca foi determinado
A Fase A do spike (rampa 3→30 domínios) bloqueou no primeiro valor
testado (`n_domains=3`) e nunca determinou se havia um limiar de
tamanho de query. **Não se aplica ao fluxo ativo** — a Tavily usa
`include_domains` (lista estruturada), não concatenação textual de
`site:`/`OR`, então esse limite de tamanho de query por caracteres não
é uma preocupação equivalente. Mantido aqui só para registro histórico.

---

## 4. Do Spike 5 (`spikes/05-tavily-validacao/RESULTADO.md`)

### 4.1 Campo `content` da resposta da Tavily pode ou não substituir a extração própria de RF-05.2 — decisão pendente
O spike documentou que `content` (snippet/trecho, 100 a ~2.200
caracteres observados) está disponível em toda resposta, mas **não
decidiu** se isso substitui, complementa, ou é ignorado em favor da
extração própria via `URLSession` + parsing de HTML (RF-05.1/RF-05.2).
Isso afeta diretamente se RF-05 completo (download do HTML do
artigo) ainda é necessário para todo artigo, ou só como
fallback/complemento. Decisão em aberto, não resolvida por este spike
nem por este documento.

### 4.2 `search_depth="advanced"` nunca foi testado
Todas as chamadas do Spike 5 usaram `search_depth="basic"` (1 crédito
documentado por chamada, a opção mais barata). O modo `"advanced"`
(2 créditos/chamada) não foi testado — não há dado sobre se o
comportamento de vazamento de domínio (item 4.4 abaixo) é diferente
nesse modo, nem se a qualidade/relevância dos resultados muda o
suficiente para justificar o custo dobrado.

### 4.3 Consumo de créditos não é exposto pela API em nenhuma resposta
Nenhum header (`credit`, `usage`, `limit`, `remaining`) nem campo no
corpo JSON expõe consumo de cota em nenhuma das ~29 chamadas feitas.
Monitoramento de cota em produção precisaria ser feito manualmente no
painel da Tavily (`app.tavily.com`), não programaticamente a partir da
resposta da API. Isso é relevante para RF-10.2 ("quota esgotada") — o
app não tem como se antecipar consultando a própria API; só vai
descobrir a cota esgotada quando uma chamada de busca falhar por causa
disso (o formato desse erro específico de "cota esgotada", diferente
do erro 401 de chave inválida documentado na Fase 4, **não foi
observado nem documentado** — não ocorreu naturalmente dentro da cota
gratuita usada nesta sessão).

### 4.4 Sugestão (não decisão) de pedir mais resultados e truncar localmente
O spike sugere pedir `max_results` entre 8-10 e truncar para 5
localmente **depois** do filtro de allowlist (RF-03.5), em vez de pedir
`max_results=5` diretamente — dado observacional de que isso reduziu o
vazamento de domínio em pelo menos 1 caso testado (repetição da busca
que vazou 4/5 com `max_results=10` + `wikipedia.org` liberado resultou
em 10/10 dentro da allowlist). O próprio spike é explícito: **"fica
como observação para quem implementar RF-04, não como decisão"**, e
**não foi testado de forma controlada o bastante para afirmar
causalidade** (dois fatores mudaram ao mesmo tempo: `max_results` e a
lista de domínios).

> Nota de verificação: o contexto desta tarefa afirma que esta
> observação já foi promovida a decisão registrada em `RF-04.3`
> ("solicitar 8-10 resultados via `max_results`, truncar para 5 DEPOIS
> de aplicar o filtro de allowlist"). Ao reler `spec.md` (RF-04.3, linha
> 62), o texto atual ainda diz apenas "O app recupera no máximo 5
> resultados por verificação" — **não reflete essa regra de
> pedir-mais-e-truncar**. Ver relatório de consistência desta tarefa
> para o detalhamento completo; não decido nada aqui, só sinalizo que a
> observação do spike e o texto vigente da spec parecem estar
> dessincronizados.

### 4.5 Subdomínios `*.gov.br` passam no filtro por regra de sufixo — inclusive prefeituras pequenas
Observação incidental: no teste de exclusão (Fase 2), um resultado veio
de `ilhabela.sp.gov.br` (site de prefeitura), contado como "dentro da
allowlist" porque a regra de correspondência usada no spike é por
sufixo (`host.endswith(".gov.br")`) e `gov.br` está na allowlist.
Tecnicamente correto perante RF-03.3, mas significa que **qualquer**
subdomínio `*.gov.br` passa — não só o portal federal, que
provavelmente era a intenção original de ter `gov.br` na lista. O
spike não decide nada, só sinaliza.

> Nota de verificação: o contexto desta tarefa trata isso como já
> decidido ("Domínios `*.gov.br` continuam validando por sufixo
> (aceito, DT-20)"). Não encontrei nenhuma `DT-20` em `spec.md` — a
> tabela de Decisões Técnicas (seção 6) termina em DT-18. Mesma
> dessincronização do item 4.4: se a decisão foi tomada, o texto da
> spec ainda não foi atualizado para refleti-la.

### 4.6 Comportamento de "zero resultados" (RF-04.4) provavelmente menos frequente na prática do que o desenho da spec presume
O motor de busca da Tavily pareceu fazer correspondência
semântica/por-palavra-chave permissiva — só retornou 0 resultados
quando a query não continha **nenhuma** palavra real. Para afirmações
reais de usuário (que sempre têm palavras reais), é provável que o
caminho `NÃO ENCONTRADO` (RF-04.4) seja acionado com menos frequência
via Tavily do que presumido, e que o filtro de relevância de fato acabe
recaindo mais sobre a etapa de similaridade de embeddings (RF-06) do
que sobre "buscador não achou nada". Isso é uma observação de
comportamento observado, não uma decisão de arquitetura — mas pode
valer a pena calibrar a expectativa de RF-04.4/RF-06.7 (limiar de
similaridade) levando isso em conta.

### 4.7 Rate limit da Tavily nunca foi testado deliberadamente
Não ocorreu naturalmente dentro das ~29 chamadas desta sessão (dentro
da cota gratuita de 1.000/mês). O formato do erro de rate-limit (código
HTTP, corpo) para fins de RF-10 não foi documentado — só o erro de
chave inválida (401) foi.

### 4.8 `include_answer` e `include_raw_content` nunca foram testados
Parâmetros da API não exercitados neste spike — `raw_content` apareceu
sempre `null` porque `include_raw_content` não foi pedido. Se
`raw_content` (texto completo da página, se existir) puder ser relevante
para a decisão do item 4.1 acima (substituir ou não a extração própria),
isso ainda não foi explorado.

---

## Resumo — itens que seguem sem decisão após este levantamento

| # | Origem | Item | Ainda em aberto? |
|---|---|---|---|
| 2.1 | Spike 3 | Redução de 34→30 domínios nunca virou DT/RF formal | Sim — aplicado ao código, não à spec |
| 2.2 | Spike 3 | Retry em erro 5xx transiente vs. descarte definitivo | Sim |
| 2.3 | Spike 3 | Biblioteca/abordagem de extração em Swift | Sim |
| 2.4 | Spike 3 | Paywall parcial por artigo | Sim (não testado) |
| 4.1 | Spike 5 | `content` da Tavily substitui RF-05.2? | Sim |
| 4.2 | Spike 5 | `search_depth="advanced"` | Sim (não testado) |
| 4.3 | Spike 5 | Formato do erro de cota esgotada (RF-10.2) | Sim (não observado) |
| 4.4 | Spike 5 | `max_results` 8-10 truncado para 5 | Ver nota — pode já estar decidido, mas não está no texto da spec |
| 4.5 | Spike 5 | Regra de sufixo `*.gov.br` inclui qualquer subdomínio | Ver nota — pode já estar decidido, mas não há DT-20 na spec |
| 4.6 | Spike 5 | Frequência esperada de `NÃO ENCONTRADO` via Tavily | Sim (observação de comportamento) |
| 4.7 | Spike 5 | Formato do erro de rate-limit (RF-10) | Sim (não testado) |
| 4.8 | Spike 5 | `include_answer`/`include_raw_content` | Sim (não testado) |

Itens **resolvidos/descartados** por este levantamento (não precisam de
decisão adicional):
- 1.1 — decodificação de URL de redirecionamento do DDG: não se aplica
  à Tavily.
- 3.1 — pesquisa de alternativas ao DDG (Bing/Brave/Google CSE): histórico,
  substituído pela escolha da Tavily.
- 3.2 — limite de tamanho de query `site:`/`OR`: não se aplica ao
  esquema `include_domains` da Tavily.
