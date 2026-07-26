# SPIKE 4b — Resultado: `URLSession` (device físico) contorna o bloqueio do Spike 4?

**Data:** 2026-07-25
**Objetivo:** repetir a MESMA requisição que bloqueou no Spike 4 original
(cliente Python `requests`) usando `URLSession` puro em Swift, rodando no
**iPhone físico** — para descartar (ou confirmar) a hipótese de que o
bloqueio observado no Spike 4 era específico do fingerprint TLS/HTTP do
cliente Python, não do app real.

Código descartável, isolado do app iOS (app SwiftUI mínimo, não é o app
principal). Não decide DT-11, não implementa nada do app.

---

## Veredito rápido

> **Resultado parcial, não um "sim" nem um "não" limpo.** A requisição
> crítica (fase A, `n_domains=3`, a mesma query que bloqueou
> imediatamente no Spike 4 em Python) **NÃO bloqueou** via `URLSession`
> no iPhone físico — `HTTP 200`, 10 resultados, 0,84s. As duas
> requisições seguintes da fase A (`n_domains=5` e `n_domains=8`)
> também tiveram sucesso. Mas a **quarta requisição da sessão**
> (`n_domains=12`, query de 323 caracteres) **bloqueou**, com a
> **mesma assinatura exata** do bloqueio do Spike 4 original: `HTTP
> 202`, corpo pequeno e anômalo (14.814 bytes), 0 resultados
> parseáveis. O script parou imediatamente ali, como instruído. Fase B
> não chegou a rodar.

---

## Ambiente e metodologia

- **Device:** iPhone físico (`br-NKHFRW9FDY`, iPhone 16, **iOS
  26.3.1**) — não simulador. Build assinado com o mesmo team
  (`2DK23BZ7KB`) e fluxo (`xcodegen` + `xcodebuild` + `devicectl`) já
  usados em `spikes/02c-nli-executavel/run_bench_device.sh`.
- **Cliente HTTP:** `URLSession.shared` puro — sem
  `URLSessionConfiguration` customizada, sem headers adicionais (sem
  `User-Agent`, sem `Accept-Language` etc.), refletindo o que o app
  real faria por padrão com uma chamada `URLSession.shared.data(from:)`.
  Código em [`Sources/DDGSpike.swift`](./Sources/DDGSpike.swift).
- **Endpoint e query:** idênticos ao Spike 4 —
  `https://html.duckduckgo.com/html/?q=...`. A allowlist de 30 domínios
  ([`Sources/DDGData.swift`](./Sources/DDGData.swift)) e as 20
  afirmações + heurística de `extractKeywords` são cópia byte-a-byte de
  `spikes/04-ddg-scraping/domains.py` e `queries.py`. A primeira query
  gerada é **idêntica** à do Spike 4:
  `Governo federal anuncia isenção imposto renda quem ganha
  site:g1.globo.com OR site:oglobo.globo.com OR site:folha.uol.com.br`
  (124 caracteres, `n_domains=3`).
- **Critérios de bloqueio:** os mesmos do Spike 4 (`looksBlocked` em
  `DDGSpike.swift`, espelhando `looks_blocked` do Python) — status fora
  de 200 (403/429/503 explícitos ou qualquer outro ≠ 200), marcador
  textual de captcha/bloqueio no corpo, ou corpo suspeito pequeno (<1.500
  bytes).
- **Fluxo:** ao primeiro bloqueio, para imediatamente (implementado no
  próprio loop da fase A/B — nenhuma tentativa adicional, nenhuma
  variação de header/User-Agent foi feita, conforme instruído).

---

## O que de fato aconteceu

| # | Fase | `n_domains` | `query_len` | Status | Corpo | Resultados | Tempo |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | A | 3 | 124 | **200** | 41.749 bytes | **10** | 0,84s |
| 2 | A | 5 | 172 | **200** | 40.120 bytes | **10** | 0,79s |
| 3 | A | 8 | 240 | **200** | 39.710 bytes | **10** | 0,78s |
| 4 | A | 12 | 323 | **202** | 14.814 bytes | **0** | 0,10s |

A fase A parou no passo 4 (`n_domains=12`). A fase B (20 buscas
temáticas) **não chegou a rodar**. Resultado bruto completo em
[`results.json`](./results.json), log de console do device em
[`device_run.log`](./device_run.log).

### Nota sobre `result_hosts` nas requisições OK

Nos 3 passos com sucesso, `result_hosts` mostra `duckduckgo.com` 10
vezes em vez dos domínios reais dos artigos. Isso é uma limitação do
parsing simplificado deste spike, não um sinal de bloqueio: o HTML de
resultados do DuckDuckGo envolve cada link em uma URL de redirecionamento
própria (`//duckduckgo.com/l/?uddg=<url-real-codificada>&...`), e a
extração ingênua de `URL.host` deste spike pega o host do redirecionador,
não o destino final decodificado. O corpo tinha tamanho normal
(39-42 KB, mesma ordem de grandeza de uma página de resultados de
verdade) e 10 ocorrências de `class="result__a"` — sinais inequívocos de
página de resultados bem-sucedida, não de bloqueio. **Fica registrado
como pendência para quem implementar RF-04 de verdade:** será preciso
decodificar o parâmetro `uddg` da URL de redirecionamento para obter o
domínio real e aplicar o filtro de allowlist (RF-03.5) corretamente —
este spike não faz isso porque só testa o sinal de bloqueio/não-bloqueio,
não a extração final de URLs.

---

## Comparação byte-a-byte com o Spike 4 (Python)

| Campo | Spike 4 (Python, 2 rodadas) | Spike 4b (`URLSession`, iPhone físico) |
|---|---|---|
| Query bloqueada | `n_domains=3` (1ª requisição da sessão) | `n_domains=12` (4ª requisição da sessão) |
| `status_code` no bloqueio | 202 | 202 |
| `body_len` no bloqueio | 14.439 / 14.445 bytes | 14.814 bytes |
| `result_count` no bloqueio | 0 | 0 |
| `block_reason` | "HTTP 202 inesperado" | "HTTP 202 inesperado" |
| Requisições que passaram antes do bloqueio | 0 | 3 (`n_domains=3, 5, 8`, todas HTTP 200 com 10 resultados) |

A assinatura do bloqueio em si é **a mesma** (status 202 + corpo pequeno
sem `result__a` + 0 resultados), consistente com Spike 3 e as duas
rodadas do Spike 4 — é a mesma "página de challenge" de bot-detection.
O `body_len` (14.814 bytes) é próximo, mas **não byte-idêntico**, ao das
duas rodadas do Python (14.439 e 14.445 bytes) — diferença de ~370-375
bytes, plausivelmente o mesmo tipo de conteúdo dinâmico (token/timestamp
de challenge) já observado entre as duas rodadas do Spike 4 original
(que diferiram entre si em 6 bytes). Não afirmo que é a mesma página
byte-a-byte perfeita, mas é a mesma classe de resposta.

**A diferença relevante não é o padrão do bloqueio — é o ponto onde ele
ocorre.** No Python, bloqueou na 1ª requisição da sessão, com query de
apenas 3 domínios. No `URLSession`, a requisição idêntica passou, e
mais duas depois dela também passaram; o bloqueio só apareceu na 4ª
requisição, com uma query maior (12 domínios, 323 caracteres).

---

## Análise: por que bloqueou na 4ª e não na 1ª?

Duas hipóteses, nenhuma confirmável com um único ponto de dados nesse
limite:

1. **Tamanho da query / número de domínios no `site:` `OR`.** O
   bloqueio apareceu exatamente quando a query cresceu de 8 para 12
   domínios (240 → 323 caracteres). Pode haver um limiar de tamanho de
   query ou de cláusulas `OR` que dispara triagem antibot,
   independente do cliente.
2. **Contagem de requisições / padrão de sessão.** O bloqueio ocorreu
   na 4ª requisição desta sessão, com ~18-24s de espaçamento entre
   elas — pode ser um limiar de "N requisições em M minutos", não
   relacionado ao tamanho da query em si.

Não dá para isolar qual fator pesou mais sem outro spike dedicado
(ex.: repetir várias queries pequenas em sequência vs. uma query grande
isolada) — e este spike foi instruído a parar no primeiro sinal de
bloqueio, então não investiguei mais fundo.

O que **dá** para afirmar com razoável confiança:

- **`URLSession` não reproduz o bloqueio imediato de 1ª requisição** que
  o cliente Python (`requests`) mostrou de forma consistente em duas
  rodadas do Spike 4. Isso é evidência a favor da hipótese de
  fingerprint de cliente HTTP levantada no Spike 4 — pelo menos para a
  primeira interação.
- **`URLSession` não é imune ao bot-detection do DuckDuckGo.** O mesmo
  tipo de bloqueio (202 + corpo anômalo) apareceu dentro da mesma
  sessão, cedo (4ª requisição), assim que a query cresceu.
- **Implicação prática relevante para RF-02.3/RF-04:** a spec usa
  `site:` `OR` sobre a allowlist inteira (30 domínios) por padrão, não
  uma rampa gradual de 3→30 como este spike fez para fins de teste. Uma
  query real do app, se enviar todos os 30 domínios de uma vez (ou algo
  próximo disso), está numa faixa de tamanho **maior** que a que já
  bloqueou aqui (`n_domains=12`, 323 caracteres) — ou seja, o cenário de
  uso real do app pode estar mais perto do regime que bloqueou do que do
  regime que passou. Isso não foi testado diretamente (o script parou
  no primeiro bloqueio, como instruído) — é uma inferência a partir do
  ponto onde o bloqueio ocorreu, não um resultado medido.

---

## Conclusão objetiva

**Nem "URLSession contorna o bloqueio" nem "URLSession sofre o mesmo
bloqueio" descreve o resultado com precisão. É um resultado parcial:**
`URLSession` **adia** o bloqueio (sobrevive à requisição que derrubou o
cliente Python na primeira tentativa, e a mais duas depois dela), mas
**não o elimina** — o mesmo padrão de bot-detection apareceu poucas
requisições depois, e a implicação prática é que ele provavelmente
apareceria ainda mais cedo se a query já nascesse do tamanho que o app
real usaria (allowlist completa, não uma rampa de 3 domínios).

---

## Recomendação (não decido DT-11 por você)

O resultado não corresponde a nenhum dos dois cenários binários
previstos na tarefa, então adapto as duas recomendações originais para
esse meio-termo:

- **Se a leitura for "o fingerprint de cliente importa, e isso já é
  bom sinal suficiente":** o `URLSession` claramente se comporta melhor
  que o Python nas primeiras requisições — isso sustenta manter DT-11
  (DDG) **com mitigação adicional necessária**, não como estava: cache
  de resultados por sessão (já previsto em §7.1 do `spec.md`), e
  principalmente **reconsiderar o tamanho da query** — ex. dividir a
  allowlist em sub-buscas menores, ou testar (em outro spike) se
  manter as queries abaixo de ~8-10 domínios evita o bloqueio de forma
  mais consistente. Isso é uma mudança de design sobre RF-02.3, não
  simples aceitação do risco original.
- **Se a leitura for "o bloqueio ainda está lá, só adiado, e o app
  real usaria queries do tamanho que já bloqueou aqui":** a evidência
  não é forte o suficiente para declarar DDG viável para produção como
  está especificado — reforça considerar as alternativas já
  pesquisadas no Spike 4 (Bing, Brave, Google CSE), reabrindo DT-11.
- **Terceira opção, não estava nas duas originais, mas decorre direto
  deste resultado:** rodar um **spike adicional e mais barato** antes
  de decidir entre as duas acima — testar especificamente se o limiar é
  de **tamanho de query** ou de **contagem de requisições por sessão**
  (ex.: repetir várias queries de 3 domínios em sequência vs. uma
  query de 30 domínios isolada). Isso reduziria a incerteza que restou
  aqui a um custo baixo (poucas requisições adicionais), antes de
  comprometer a arquitetura com uma allowlist fatiada ou trocar de
  provedor.

Não escolhi nenhuma dessas por conta própria — a decisão sobre DT-11
continua sendo sua.

---

## O que este spike NÃO fez

- Não determinou se o gatilho do bloqueio foi tamanho de query ou
  contagem de requisições — apenas observou onde ocorreu.
- Não completou a fase A (parou em `n_domains=12` de 8 valores
  planejados) nem a fase B (20 buscas temáticas não rodaram).
- Não tentou nenhuma forma de contorno além da troca de cliente HTTP
  (Python → `URLSession`) — sem headers customizados, sem
  `URLSessionConfiguration` especial, sem retry, sem rotação de nada.
- Não decodificou as URLs de redirecionamento do DuckDuckGo
  (`duckduckgo.com/l/?uddg=...`) para obter os domínios reais dos
  resultados — ficou registrado como pendência acima, não é uma decisão
  de implementação de RF-04.
- Não rodou no simulador iOS — a tarefa pediu especificamente device
  físico por essa ser a variável em teste (stack de rede do device real
  vs. host macOS do simulador); não havia necessidade de rodar no
  simulador também já que o device físico esteve disponível a tempo.
- Não editou `spec.md` nem decidiu o destino de DT-11.

---

## Como reproduzir

Requer Xcode, `xcodegen` (`brew install xcodegen`), conta Apple logada
no Xcode (assinatura automática) e um iPhone físico conectado, desbloqueado
e com "Confiar neste computador" já aceito.

```bash
cd spikes/04b-ddg-urlsession
./run_device.sh                 # usa o device br-NKHFRW9FDY por padrão
./run_device.sh <OUTRO_DEVICE_ID>
```

O script faz `xcodegen generate`, `xcodebuild` (device físico, assinatura
automática com o team `2DK23BZ7KB`), `devicectl device install` e
`devicectl device process launch --console`, salvando o log completo em
`device_run.log` neste diretório.

Aviso: rodar de novo é uma nova tentativa de scraping real contra
`html.duckduckgo.com` — trate com o mesmo cuidado dos spikes anteriores
(não usar em rajada, parar ao primeiro sinal de bloqueio — o próprio
script já faz isso automaticamente).

Fontes: [`Sources/DDGData.swift`](./Sources/DDGData.swift) (allowlist +
claims + extração de keywords, cópia do Spike 4),
[`Sources/DDGSpike.swift`](./Sources/DDGSpike.swift) (lógica de busca e
detecção de bloqueio), [`Sources/ContentView.swift`](./Sources/ContentView.swift)
e [`Sources/DDGSpikeApp.swift`](./Sources/DDGSpikeApp.swift) (app SwiftUI
mínimo). Resultado bruto em [`results.json`](./results.json), log de
device em [`device_run.log`](./device_run.log).
