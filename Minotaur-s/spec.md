# Especificação Técnica — Feature "Verificar Notícia" (iOS)

**Versão:** 0.2
**Status:** Pré-implementação
**Escopo:** reconstrução de UMA feature dentro de um app iOS já existente e em produção/desenvolvimento.

---

## 0. Contexto do projeto (importante para o Claude Code)

O app já existe e possui **múltiplas funcionalidades**. Esta spec cobre **exclusivamente** a feature "Verificar Notícia". Nenhuma outra funcionalidade do app deve ser lida, alterada, refatorada ou "melhorada" como efeito colateral desta implementação.

A feature "Verificar Notícia" está **atualmente implementada de forma ineficaz** em um único arquivo, `Verificador.swift`, que hoje:
- faz scraping do DuckDuckGo;
- envia o artigo inteiro para o `FoundationModels` analisar de uma vez, sem chunking, sem embeddings, sem NLI.

Essa abordagem atual erra com frequência e **a lógica de verificação deve ser completamente destruída e reconstruída do zero** segundo esta spec (ver seção 6, DT-01).

**O que PODE ser reaproveitado:** o design visual/estrutura de UI da tela atual do verificador, na medida em que for razoável (layout, componentes visuais, fluxo de navegação já existente).

**O que NÃO pode ser reaproveitado:** qualquer lógica de scraping, parsing, chamada ao FoundationModels, ou qualquer decisão de arquitetura da análise em si. Isso deve ser reescrito seguindo o pipeline desta spec.

**Fora dos limites desta tarefa:** qualquer outra tela, feature, model, service ou utilitário do app que não pertença exclusivamente ao fluxo de "Verificar Notícia". Se durante a implementação for necessário tocar em código compartilhado (ex: um design system, um helper de rede genérico), isso deve ser sinalizado antes de alterar, não decidido silenciosamente.

## 1. Objetivo

Reconstruir a feature "Verificar Notícia" do app para que, dada uma afirmação/notícia digitada pelo usuário, o sistema determine se ela é **confirmada, contradita ou não coberta** por artigos de veículos de imprensa previamente definidos como confiáveis.

**Problema que resolve:** hoje o usuário precisa buscar manualmente, abrir vários sites e ler artigos inteiros para saber se uma informação que recebeu (ex: mensagem de WhatsApp) bate com o que a imprensa publicou. Esta feature automatiza busca, leitura e comparação semântica — substituindo a versão atual, que analisa o artigo inteiro via `FoundationModels` sem estrutura e erra com frequência.

**Público-alvo:** usuário leigo brasileiro que recebe notícias por redes sociais e quer uma checagem rápida contra fontes jornalísticas.

**O que a feature NÃO é:** não é um verificador de verdade absoluta. Ela responde "as fontes confiáveis que encontrei confirmam/contradizem/não falam sobre isso", nunca "isso é verdade" ou "isso é mentira".

---

## 2. Requisitos Funcionais

### RF-01 — Entrada da afirmação
- RF-01.1 — Tela com campo de texto multilinha onde o usuário digita ou cola a notícia/afirmação.
- RF-01.2 — Validação: mínimo de 15 caracteres e máximo de 1.000 caracteres. Fora desse intervalo, o botão "Verificar" fica desabilitado e uma mensagem indica o motivo.
- RF-01.3 — Botão "Verificar notícia" dispara o fluxo completo.
- RF-01.4 — Durante o processamento, exibir indicador de progresso por etapa (buscando → lendo fontes → analisando).
- RF-01.5 — Botão de cancelar disponível durante todo o processamento; cancelar aborta requisições de rede em andamento.

### RF-02 — Geração da query de busca
- RF-02.1 — Se a entrada tiver mais de 200 caracteres, o app deve extrair uma query reduzida (palavras-chave) em vez de enviar o texto inteiro ao buscador.
- RF-02.2 — Estratégia definitiva: extrair a primeira frase da afirmação, truncada em 200 caracteres. Resolvido — descartado o saco-de-palavras: os vazamentos de domínio observados no Spike 5 concentraram-se em buscas dominadas por termo genérico isolado. Ver DT-22.
- RF-02.3 — A query deve ser restrita aos domínios da allowlist usando o parâmetro `include_domains` da API de busca (Tavily), com a lista completa de domínios em uma única chamada. Não é necessário construir `site:`/`OR` manualmente — a restrição é nativa da API.

### RF-03 — Allowlist de domínios confiáveis
- RF-03.1 — A composição da lista de domínios confiáveis já existe hoje como `trustedDomains`, em `VerificadorView`, e deve ser preservada como fonte da verdade do conteúdo, **com uma exceção autorizada**: os 4 domínios identificados no Spike 3 como bloqueados por bot-blocking (`uol.com.br`, `espn.com.br`, `reuters.com`, `ibge.gov.br` — HTTP 401/403/202 vazio, não é falha de extração) devem ser **removidos** da lista. Fora dessa exceção, nenhum outro domínio é adicionado ou removido nesta reconstrução. **Correção técnica adicional (Fase 3):** 4 entradas tinham o valor de `domain` desatualizado em relação ao host real que serve o conteúdo (`band.uol.com.br`→`www.band.com.br`, `lupa.uol.com.br`→`www.agencialupa.org`, `gzh.com.br`→`gauchazh.clicrbs.com.br`, e o veículo da Agência Gov, que precisou de **entrada própria** `agenciagov.ebc.com.br` — não casa por sufixo com a entrada existente `agenciabrasil.ebc.com.br` (achado só na integração real, Fase 3). A lista final tem **31 strings para os mesmos 30 veículos** (a Agência Gov agora tem 2 entradas). Não é nova curadoria, é correção de bug de correspondência que impedia essas fontes de retornar qualquer artigo via `include_domains`. Ver DT-28.
- RF-03.2 — O formato de armazenamento/estrutura de dados é livre para a reconstrução — não precisa continuar como propriedade da `VerificadorView`. Fica a critério da implementação (ex: struct/enum dedicado, arquivo JSON no bundle, etc.), desde que a lógica de verificação (busca, filtragem, extração) não dependa de acessar a `View` para obter os domínios.
- RF-03.3 — Cada domínio precisa continuar identificável por seu `domain` (string usada no filtro/`site:`). Campos adicionais (`displayName`, `enabled`, etc.) podem ser adicionados na migração se ajudarem a estrutura, mas não são obrigatórios caso não existam hoje.
- RF-03.4 — Nesta fase, a lista **não é editável pelo usuário** e não é atualizada remotamente — apenas migrada de lugar/formato, não de conteúdo.
- RF-03.5 — Resultados de busca cujo domínio não esteja na allowlist devem ser descartados, mesmo que retornados pelo buscador. **Este filtro é obrigatório, não defesa em profundidade**: o Spike 5 confirmou empiricamente que `include_domains` da Tavily não é um filtro 100% rígido — vazou domínios fora da allowlist em 4/20 buscas de teste (20%), incluindo 2 casos onde 100% dos resultados retornados eram de fora da lista (Wikipédia, dicionários online, sites sem relação jornalística).
- RF-03.6 — Migrar `trustedDomains` para fora da `VerificadorView` faz parte da reconstrução (ver DT-17): a `View` não deve ser dona da fonte de dados usada pela lógica de negócio.

### RF-04 — Busca de artigos
- RF-04.1 — O app consulta um provedor de busca web restrito à allowlist.
- RF-04.2 — Provedor de busca: **Tavily** (https://tavily.com), API oficial com contrato/ToS, tier gratuito de 1.000 créditos/mês sem cartão de crédito. Ver DT-11 (revisada 2ª vez) e evidência no Spike 5. O app **não chama a Tavily diretamente** — chama um proxy serverless (Cloudflare Workers, DT-21) que injeta a chave e repassa a requisição/resposta.
- RF-04.3 — O app solicita 8–10 resultados por verificação à API (`max_results`), aplica o filtro de allowlist (RF-03.5) e trunca para os 5 primeiros resultados dentro da allowlist. Pedir mais resultados do que o necessário e truncar depois do filtro reduz a taxa de vazamento observada no Spike 5 (evidência: a mesma busca que vazou 4/5 com `max_results=5` retornou 10/10 dentro da allowlist com `max_results=10`).
- RF-04.4 — Se nenhum resultado for retornado, o app exibe o veredito `NÃO ENCONTRADO` (ver RF-08) sem executar as etapas seguintes.
- RF-04.5 — Falha de rede na busca deve produzir mensagem de erro distinta de "não encontrado".
- RF-04.6 — Em caso de erro HTTP 5xx ou timeout na chamada de busca, o app tenta **uma única vez adicional** antes de reportar falha (RF-10). Erros 401/429 nunca são reafetados. Resolvido — ver DT-27. Retry por artigo individual permanece em aberto (item 14 da seção 7.3).

### RF-05 — Download e extração do conteúdo do artigo
- RF-05.1 — Para cada URL aprovada, o app baixa o HTML via `URLSession`.
- RF-05.2 — O app extrai o texto principal do artigo, descartando menu, rodapé, anúncios, comentários e blocos de "leia também". Abordagem definitiva: porte de algoritmo tipo Readability sobre SwiftSoup (pontuação por densidade de texto por bloco), não heurística por denylist simples. Ver DT-23, resolve item aberto 15.
- RF-05.3 — Se o texto extraído tiver menos de 200 caracteres, o app usa como fallback o campo `content` (snippet) retornado pela Tavily para aquela URL; só se esse fallback também tiver menos de 200 caracteres a fonte é considerada inválida e descartada (indica paywall, conteúdo via JavaScript ou falha de extração). O `content` da Tavily nunca substitui a extração própria quando esta é bem-sucedida — é usado apenas como último recurso. Ver DT-23, resolve item aberto 16.
- RF-05.4 — Timeout de 8 segundos por artigo. Artigo que estourar o timeout é descartado sem abortar o fluxo.
- RF-05.5 — Artigos que exigem renderização de JavaScript não são suportados nesta fase e serão descartados por RF-05.3.
- RF-05.6 — Todo o processamento de rede ocorre em paralelo entre artigos, não em série.

### RF-06 — Pipeline de análise: chunking + embeddings
- RF-06.1 — O texto extraído é dividido em chunks por parágrafo, com sobreposição de 1 frase entre chunks adjacentes.
- RF-06.2 — Chunks devem respeitar o limite de tokens do modelo NLI (512 tokens). Chunk que exceder é subdividido.
- RF-06.3 — Cada chunk é convertido em vetor de embedding por modelo Core ML rodando on-device.
- RF-06.4 — A afirmação do usuário é convertida no mesmo espaço vetorial.
- RF-06.5 — O app calcula similaridade de cosseno entre a afirmação e cada chunk.
- RF-06.6 — Os **top 3 chunks** de maior similaridade seguem para a etapa de NLI. Chunks com similaridade abaixo de um limiar mínimo são descartados.
- RF-06.7 — Valor definitivo do limiar mínimo de similaridade: **0,25** (cosseno). Calibrado a partir dos dados de similaridade por par do Spike 2c: pares decisivos (entailment/contradiction reais) variaram de 0,31 a 0,86; pares neutros ficaram em 0,09–0,17 (um outlier em 0,58). 0,25 preserva 15/15 pares decisivos e descarta 4/5 neutros do dataset. A validar num spike adicional sobre chunks de artigo real antes do lançamento. Ver DT-24.

### RF-07 — Pipeline de análise: NLI
- RF-07.1 — Para cada chunk selecionado, executar o modelo NLI on-device com `premissa = chunk` e `hipótese = afirmação do usuário`.
- RF-07.2 — A saída do modelo é a distribuição de probabilidade entre `entailment`, `contradiction` e `neutral`.
- RF-07.3 — **Resolvido nesta fase (leitura literal original não funciona — ver DT-29).** O resultado por artigo é determinado assim: entre os chunks selecionados (RF-06.6), **neutro não compete pela vitória do artigo**. O rótulo do artigo é o maior score entre `entailment` e `contradiction` (acima do limiar de RF-07.5) encontrado em qualquer chunk daquele artigo; só quando nenhum chunk produzir `entailment` ou `contradiction` acima do limiar o rótulo do artigo é `neutral`.
- RF-07.4 — Rótulos com confiança abaixo de um limiar mínimo são rebaixados para `neutral`.
- RF-07.5 — Valor definitivo do limiar mínimo de confiança do NLI: **0,50**. O único "erro perigoso" observado no MiniLMv2-L6 (Spike 1) teve confiança 0,66 — mesma faixa de um entailment correto, então nenhum limiar global de confiança isola esse caso sozinho; o par em questão tinha similaridade 0,09, abaixo do piso da RF-06.7, que o filtra antes de chegar ao NLI. Os dois limiares (RF-06.7 e RF-07.5) resolvem esse risco em conjunto. Ver DT-25.

### RF-08 — Agregação e veredito final
- RF-08.1 — O veredito é agregado a partir dos rótulos por artigo, segundo as regras:
  - Nenhuma fonte válida analisada → `NÃO ENCONTRADO`
  - Maioria `entailment` → `CONFIRMADO PELAS FONTES`
  - Maioria `contradiction` → `CONTRADITO PELAS FONTES`
  - Todas `neutral` → `SEM INFORMAÇÃO SUFICIENTE`
  - Empate entre `entailment` e `contradiction` → `FONTES DIVERGENTES`
- RF-08.2 — O veredito nunca usa linguagem de verdade absoluta ("verdadeiro"/"falso"). Sempre referencia as fontes.
- RF-08.3 — Regra de desempate definitiva: neutro não participa da votação. Sejam E = nº de fontes com rótulo `entailment` e C = nº de fontes com rótulo `contradiction` (após RF-07.4): E+C=0 → `NÃO ENCONTRADO`/`SEM_INFORMACAO` conforme o caso; E>C → `CONFIRMADO`; C>E → `CONTRADITO`; E=C>0 → `DIVERGENTES`. Fecha todos os casos de RF-08.1 sem introduzir veredito novo. Ver DT-26. **Decisão de produto explícita: sem piso mínimo de fontes válidas** — 1 fonte válida já é suficiente para emitir um veredito diferente de `NÃO ENCONTRADO`.

### RF-09 — Tela de resultado
*(Nota: o layout/design visual atual da tela de resultado pode ser reaproveitado onde fizer sentido — ver seção 0 e DT-15. Os requisitos abaixo descrevem o que a tela deve exibir, não como deve ser desenhada.)*
- RF-09.1 — Exibir o veredito agregado com destaque visual e ícone/cor correspondente.
- RF-09.2 — Listar as fontes analisadas, cada uma com: nome do veículo, título do artigo, rótulo individual, score de confiança e link para o artigo original.
- RF-09.3 — Ao tocar em uma fonte, abrir o artigo original no navegador (`SFSafariViewController`).
- RF-09.4 — Exibir um trecho curto (máx. 300 caracteres) do chunk que motivou o rótulo, com atribuição explícita ao veículo e link para o original.
- RF-09.5 — Exibir aviso permanente e visível: o resultado é uma análise automatizada, pode conter erros, e não substitui leitura das fontes.
- RF-09.6 — Listar quais domínios foram consultados naquela verificação.

### RF-10 — Tratamento de erros
- RF-10.1 — Sem conexão de rede → mensagem específica e opção de tentar novamente.
- RF-10.2 — Quota da API de busca esgotada → mensagem específica indicando limite diário atingido.
- RF-10.3 — Falha ao carregar modelo Core ML → mensagem de erro e bloqueio da funcionalidade (não deve travar o app).
- RF-10.4 — Todos os erros devem ser distinguíveis pelo usuário; nunca exibir erro genérico "algo deu errado" sem categoria.

---

## 3. Requisitos Não-Funcionais

### 3.1 Stack tecnológica
| Camada | Tecnologia |
|---|---|
| Linguagem | Swift |
| UI | SwiftUI |
| Versão mínima do iOS | A menor versão tecnicamente viável para os requisitos de Core ML deste projeto. Ver RD-01 — a confirmar por spike técnico, não por suposição a priori. |
| Inferência de ML | Core ML (on-device) |
| Tokenização | `swift-transformers` (Hugging Face) |
| Parsing de HTML | SwiftSoup |
| Rede | `URLSession` (async/await) |
| Álgebra vetorial | Accelerate framework (similaridade de cosseno) |
| Conversão de modelos | Python + `coremltools` + `transformers` (offline, fora do app) |
| Proxy de API (proteção de chave) | Cloudflare Workers (serverless, tier gratuito) — ver DT-21 |

Versões fixadas na integração real (Fase 3, DT-30): SwiftSoup 2.9.6; `swift-transformers` 1.3.3 (produto `Tokenizers`).

### 3.2 Modelos de ML
- **Modelo de embeddings (definitivo):** `paraphrase-multilingual-MiniLM-L12-v2`, convertido para `.mlpackage`, quantizado INT8 (~113 MB). Validado em PT-BR no Spike 1; conversão validada no Spike 2 (cos=0,9999 vs. PyTorch); latência em device físico = 7 ms (Spike 2, medição com Xcode completo), bem abaixo de NF-01.
- **Modelo de NLI (definitivo):** `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli` (ver DT-18 revisada), rodando em **`.cpuOnly`** (não `.all`). Convertido para `.mlpackage`, quantizado INT8 (~103 MB). Executa com logits corretos em device físico (cos=1,0 vs. PyTorch) tanto em `.cpuOnly` (2 ms) quanto em `.all` (10,5 ms) — `.cpuOnly` escolhido por ser mais rápido neste caso (shape dinâmico `RangeDim` não aproveita bem a ANE). Acurácia em PT-BR: **18/20 (90%)** no dataset do Spike 1, com o menor número de "erros perigosos" (classificar `neutral`/`entailment` como `contradiction`) entre os candidatos testados.
  - **Histórico da decisão:** o modelo originalmente escolhido, `mDeBERTa-v3-base-xnli` com `XSoftmax` patchado, teve 100% de acerto em PT-BR (Spike 1) e conversão para Core ML com saída idêntica ao original (Spike 2b), mas **não executa em nenhum device real testado** — crash de MPSGraph (`.all`) e erro BNNS (`.cpuOnly`), confirmado em 3 tentativas (Spike 2, medição com Xcode completo). "Converter sem erro" e "logits baterem em PyTorch" não garantiram execução real — lição estrutural do Spike 2c, que reordenou os filtros de validação (execução em device antes de qualidade PT-BR) para os candidatos seguintes.
  - Candidatos testados no Spike 2c, todos com execução confirmada em device físico: `MiniLMv2-L6` (escolhido, 90% PT-BR, 103 MB, 2ms), `MiniLMv2-L12` (85% PT-BR, 113 MB, 3ms — alternativa próxima), `symanto/xlm-roberta-base` (80% PT-BR, 266 MB, só roda em `.cpuOnly` — plano C). `ERNIE-M` reprovado (reproduziu o mesmo crash do mDeBERTa).
  - **Trade-off aceito conscientemente:** a acurácia PT-BR caiu de 100% (mDeBERTa, não executável) para 90% (MiniLMv2-L6, executável) — a escolha é entre um modelo que não roda e um que roda a ~90%.
  - **Dependência de manutenção:** nenhuma — `MiniLMv2-L6` usa atenção padrão, sem custom op, sem monkeypatch necessário no pipeline de conversão.
- Suporte a português: **resolvido.** Ambos os modelos foram validados com dataset real em PT-BR (Spike 1) e a conversão para Core ML foi confirmada como preservando a saída e executando corretamente em device físico (Spikes 2, 2b, 2c).
- Ambos os modelos são embarcados no bundle do app. Nenhum download de modelo em runtime nesta fase.
- Tamanho combinado (embeddings + NLI, INT8): **113 + 103 = 216 MB** — bem dentro do alvo NF-05 (<500 MB), com folga maior que a estimativa anterior (era ~389 MB com o mDeBERTa).



### 3.3 Performance
- NF-01 — Inferência de embeddings de um chunk: < 150 ms em iPhone 13 ou superior.
- NF-02 — Inferência de NLI de um par (chunk, afirmação): < 1 s em iPhone 13 ou superior.
- NF-03 — Tempo total de uma verificação (busca + download + análise), com rede estável: < 15 s.
- NF-04 — O download e o parsing de artigos ocorrem concorrentemente; nenhuma operação bloqueia a main thread.
- NF-05 — Tamanho total do app após otimização dos modelos: alvo < 500 MB. [EM ABERTO] — confirmar viabilidade após quantização; se exceder, reavaliar download sob demanda dos modelos.
- NF-06 — Uso de RAM em pico durante a análise: < 1 GB.

### 3.4 Segurança e privacidade
- NF-07 — Nenhum servidor próprio. O app não coleta, transmite nem armazena remotamente o texto digitado pelo usuário.
- NF-08 — O texto do usuário só sai do dispositivo na forma da query enviada ao provedor de busca. Isso deve ser informado explicitamente na política de privacidade e na primeira execução.
- NF-09 — **Resolvido:** a chave de API da Tavily é protegida por um proxy serverless (Cloudflare Workers, tier gratuito — ver DT-21). O app nunca embarca a chave nem a envia diretamente à Tavily; toda chamada de busca passa pela URL do Worker, que injeta a chave e repassa a resposta.
- NF-10 — Todo o tráfego via HTTPS. ATS (App Transport Security) mantido com configuração padrão, sem exceções de domínio.
- NF-11 — Política de privacidade publicada e acessível dentro do app (exigência da App Store).

### 3.5 Formatos de dados

Allowlist — exemplo ilustrativo de estrutura (o formato de armazenamento real fica a critério da implementação; ver RF-03.2/RF-03.6, conteúdo migrado de `trustedDomains`):
```json
{
  "version": 1,
  "sources": [
    { "domain": "exemplo.com.br", "displayName": "Exemplo", "enabled": true }
  ]
}
```

Resultado da verificação (modelo em memória, existe apenas durante a sessão — não persistido; ver Fora de Escopo, seção 5):
```json
{
  "id": "uuid",
  "claim": "texto digitado pelo usuário",
  "createdAt": "2026-07-23T14:00:00Z",
  "verdict": "CONFIRMADO | CONTRADITO | DIVERGENTE | SEM_INFORMACAO | NAO_ENCONTRADO",
  "sources": [
    {
      "url": "https://...",
      "domain": "exemplo.com.br",
      "title": "Título do artigo",
      "label": "entailment | contradiction | neutral",
      "confidence": 0.87,
      "similarity": 0.79,
      "excerpt": "trecho de até 300 caracteres"
    }
  ]
}
```

### 3.6 Conformidade e distribuição
- NF-12 — O app não republica artigos na íntegra. Apenas trechos curtos com atribuição e link para a fonte original.
- NF-13 — O provedor de busca escolhido deve ser usado dentro dos seus Termos de Serviço.
- NF-14 — O app deve deixar claro que não tem vínculo com os veículos consultados.
- NF-15 — Estratégia de conformidade com `robots.txt` dos sites de notícia: [EM ABERTO]

---

## 4. Critérios de Aceitação

### CA-01 — Verificação com afirmação confirmada
**Dado** que o usuário digitou uma afirmação de 50 caracteres cujo conteúdo é coberto por ao menos 2 artigos da allowlist,
**quando** ele toca em "Verificar notícia" com conexão estável,
**então** o app exibe o veredito `CONFIRMADO PELAS FONTES`, lista as fontes com seus rótulos individuais e scores, e o processo termina em menos de 15 segundos.

### CA-02 — Nenhum resultado encontrado
**Dado** que a busca nos domínios da allowlist não retorna nenhum resultado,
**quando** a verificação é executada,
**então** o app exibe `NÃO ENCONTRADO`, não executa as etapas de download e análise, e informa quais domínios foram consultados.

### CA-03 — Validação de entrada
**Dado** que o campo de texto contém menos de 15 caracteres,
**quando** o usuário observa a tela,
**então** o botão "Verificar notícia" está desabilitado e uma mensagem indica o mínimo de caracteres exigido.

### CA-04 — Filtragem por allowlist
**Dado** que o provedor de busca retornou um resultado de um domínio fora da allowlist,
**quando** o app processa os resultados,
**então** esse resultado é descartado e não aparece na lista de fontes analisadas.

### CA-05 — Artigo com paywall ou conteúdo via JavaScript
**Dado** que a extração de texto de um artigo retornou menos de 200 caracteres,
**quando** o pipeline processa esse artigo,
**então** o artigo é descartado, o fluxo continua com os demais, e o resultado final indica quantas fontes foram efetivamente analisadas.

### CA-06 — Timeout em uma fonte
**Dado** que um dos artigos não responde em 8 segundos,
**quando** o pipeline está executando,
**então** esse artigo é descartado sem abortar a verificação, e as demais fontes são analisadas normalmente.

### CA-07 — Seleção do trecho relevante
**Dado** um artigo com 10 chunks,
**quando** o pipeline de embeddings é executado,
**então** no máximo 3 chunks (os de maior similaridade acima do limiar) são enviados ao modelo NLI, e os demais não geram inferência de NLI.

### CA-08 — Ausência de conexão
**Dado** que o dispositivo está sem conexão de rede,
**quando** o usuário toca em "Verificar notícia",
**então** o app exibe uma mensagem específica de ausência de conexão, distinta da mensagem de "não encontrado", com opção de tentar novamente.

### CA-09 — Cancelamento
**Dado** que uma verificação está em andamento,
**quando** o usuário toca em "Cancelar",
**então** todas as requisições de rede pendentes são canceladas, nenhuma inferência adicional é executada e o app retorna à tela inicial com o texto preservado.

### CA-10 — Atribuição de conteúdo
**Dado** um resultado com fontes analisadas,
**quando** a tela de resultado é exibida,
**então** cada trecho citado tem no máximo 300 caracteres, exibe o nome do veículo e oferece link para o artigo original.

### CA-11 — Aviso de limitação
**Dado** qualquer veredito exibido,
**quando** a tela de resultado é renderizada,
**então** o aviso de que o resultado é automatizado e não substitui a leitura das fontes está visível sem necessidade de rolagem.

---

## 5. Fora de Escopo (nesta fase)

- Backend próprio, autenticação, contas de usuário ou sincronização entre dispositivos.
- LLM local (Phi-3, Llama, Gemma) e qualquer explicação em linguagem natural do veredito.
- Chamadas a APIs de LLM em nuvem (OpenAI, Anthropic, Google).
- Renderização de JavaScript / headless browser para artigos dinâmicos.
- Contorno de paywall de qualquer natureza.
- Edição da allowlist pelo usuário ou atualização remota da lista.
- Verificação de imagens, vídeos, áudios ou links compartilhados (apenas texto digitado).
- Share Extension / integração com o menu de compartilhamento do iOS.
- Histórico ou persistência de verificações anteriores, de qualquer forma (local, iCloud, etc.). Cada verificação é feita sob demanda e o resultado existe apenas em memória durante a sessão de uso.
- Suporte a idiomas além de português brasileiro.
- Versão iPad, macOS, Apple Watch ou widgets.
- Notificações push.
- Analytics, telemetria ou crash reporting de terceiros.
- Monetização de qualquer tipo.
- Detecção de sarcasmo, opinião, sátira ou contexto histórico.
- Ranqueamento ou avaliação de credibilidade dos veículos além da allowlist binária.
- Qualquer alteração em outras funcionalidades do app (não relacionadas ao verificador).
- Refatoração de código compartilhado (design system, helpers de rede, etc.) além do estritamente necessário para a feature — se for necessário, deve ser sinalizado antes, não decidido silenciosamente.
- Reaproveitamento de qualquer lógica de scraping, parsing ou análise do `Verificador.swift` atual. Apenas elementos de UI/design podem ser reaproveitados (ver seção 0 e DT-15).
- Migração ou reorganização de arquivos do app não relacionados à feature.

---

## 6. Decisões Técnicas Já Tomadas

| # | Decisão | Justificativa |
|---|---|---|
| DT-01 | App nativo iOS em Swift/SwiftUI | Requisito do projeto; necessário para Core ML on-device |
| DT-02 | Inferência 100% on-device via Core ML | Custo zero por uso, funciona sem depender de API de IA, privacidade do texto do usuário |
| DT-03 | Pipeline híbrido Embeddings → NLI | NLI tem limite de ~512 tokens; embeddings filtram o trecho relevante antes da inferência pesada |
| DT-04 | NLI em vez de LLM local | Menor tamanho, menor consumo de RAM, menor latência, resultado determinístico; explicação textual não é requisito |
| DT-05 | Conversão de modelos via `coremltools` em Python, offline | Python não roda no app; o pipeline de conversão é etapa de build, não de runtime |
| DT-06 | Tokenização em Swift via `swift-transformers` | Evita reimplementar tokenizer manualmente e garante paridade com o tokenizer usado no treino |
| DT-07 | Chunking por parágrafo com sobreposição de 1 frase | Equilíbrio entre preservar contexto e manter relevância da similaridade |
| DT-08 | Top-3 chunks por artigo para o NLI | O chunk mais similar isolado pode não conter a informação decisiva |
| DT-09 | Similaridade de cosseno como métrica de relevância | Padrão para `sentence-transformers`; implementável com Accelerate |
| DT-10 (revisada) | Allowlist embarcada e fixa, com conteúdo migrado de `trustedDomains` (hoje em `VerificadorView`) para fora da camada de UI | Preserva a curadoria já feita; separa dados de negócio da View, alinhado a DT-17 |
| DT-11 (revisada 2ª vez) | **Tavily** como provedor de busca, substituindo o scraping do DuckDuckGo | O scraping do DDG bloqueou de forma sistemática em 2 clientes HTTP diferentes (Python e Swift/URLSession — Spikes 4 e 4b), inclusive em uso leve. As 3 alternativas originalmente pesquisadas (Bing, Brave, Google Custom Search) estão inviabilizadas: Bing foi descontinuada (ago/2025), Brave eliminou o tier gratuito (fev/2026, exige cartão sem teto de gasto), Google Custom Search está fechada para novos clientes desde 2025. Tavily oferece 1.000 créditos/mês grátis sem cartão, com `include_domains` nativo, validado tecnicamente no Spike 5 (100% de disponibilidade em 20 buscas, latência média 1,62s, sem nenhum sinal de bloqueio) |
| DT-12 | Vereditos referenciam as fontes, nunca afirmam verdade absoluta | Reduz risco de dano informacional e de rejeição na revisão da App Store |
| DT-13 | Nenhum servidor próprio tradicional; sem coleta de dados | Simplicidade, custo zero, menor exigência regulatória. Exceção pontual: DT-21 (proxy serverless da Tavily) — não é um servidor mantido, mas tecnicamente um endpoint existe; o proxy é stateless (só repassa a requisição, não armazena nada) |
| DT-14 | Trechos citados limitados e sempre com link para o original | Reduz risco de violação de direitos autorais e de rejeição pela guideline 5.2 |
| DT-15 | `Verificador.swift` atual é destruído e reconstruído do zero na parte de lógica/análise | Implementação atual (artigo inteiro para `FoundationModels`) erra com frequência; não é base confiável para evolução incremental |
| DT-16 | Design visual/estrutura de UI da tela atual pode ser reaproveitado quando razoável | Não há problema identificado na UI, só na lógica de verificação; evita retrabalho desnecessário |
| DT-17 | A nova lógica deve ser separada em arquivo(s) próprio(s), não deve viver inteira em `Verificador.swift` | O problema original inclui estar "totalmente implementada no mesmo arquivo"; separar responsabilidades (busca, extração, embeddings, NLI, agregação) evita repetir esse defeito estrutural |
| DT-18 (revisada) | Modelo de NLI definitivo: `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli`, rodando em `.cpuOnly` | Substituiu o mDeBERTa patchado (DT-18 original): mDeBERTa convertia e batia logits com PyTorch, mas **não executava em nenhum device físico testado** (crash MPSGraph em `.all`, erro BNNS em `.cpuOnly` — Spike 2, medição com Xcode completo). MiniLMv2-L6 executa com cos=1,0 em device físico (Spike 2c), 90% (18/20) em PT-BR, 103 MB INT8, 2ms — menor número de erros perigosos entre os candidatos que de fato executam. Trade-off aceito: 90% executável > 100% não-executável |
| DT-19 | Solicitar mais resultados da API do que o necessário (8-10) e truncar para 5 depois do filtro de allowlist | Reduz a taxa de vazamento de domínios fora da allowlist observada no Spike 5 (evidência: mesma busca vazou 4/5 com max_results=5, mas retornou 10/10 corretos com max_results=10) |
| DT-20 | Domínios `*.gov.br` na allowlist continuam validando por sufixo, incluindo subdomínios de prefeituras/órgãos menores, não só o portal federal | Decisão consciente do stakeholder: simplicidade da regra de correspondência sobrepõe o risco de incluir órgãos públicos menores, que ainda são fontes governamentais legítimas |
| DT-21 | Proteção da chave da Tavily via proxy serverless (Cloudflare Workers) | Chave embarcada no binário é extraível por engenharia reversa (consenso técnico, inclusive de post do DTS da Apple); proxy é a única proteção real. Cloudflare Workers: tier gratuito de 100.000 req/dia, sem custo, manutenção mínima (função stateless, não é servidor 24/7 tradicional) — não contradiz o espírito de DT-13 (evitar backend pesado) |
| DT-22 | `SearchQueryBuilder`: primeira frase da afirmação, truncada em 200 caracteres | Saco-de-palavras testado empiricamente (Spike 5) concentra os vazamentos de domínio em termo genérico isolado; primeira frase preserva contexto sintático da afirmação |
| DT-23 | `ArticleExtractor`: porte tipo Readability sobre SwiftSoup (pontuação por bloco), com o campo `content` da Tavily como fallback — nunca substituto — quando a extração própria resultar em <200 chars | Pontuação por bloco resolve armadilhas do Spike 3 que a heurística por denylist não cobria; fallback resgata fontes com extração difícil sem enfraquecer RF-05.3 como regra padrão |
| DT-24 | Limiar de similaridade de cosseno: 0,25 | Calibrado com dados reais de similaridade por par do Spike 2c (pares decisivos 0,31–0,86; neutros 0,09–0,17) |
| DT-25 | Limiar de confiança do NLI: 0,50 | Único erro perigoso do MiniLMv2-L6 tinha confiança 0,66, mas similaridade 0,09 — já filtrado pelo piso da DT-24 antes de chegar ao NLI |
| DT-26 | Regra de desempate na agregação (RF-08.3): neutro não vota; E>C→CONFIRMADO, C>E→CONTRADITO, E=C>0→DIVERGENTES, E+C=0→NÃO_ENCONTRADO/SEM_INFORMACAO conforme o caso. **Sem piso mínimo de fontes válidas** | Fecha RF-08.3 sem introduzir veredito novo; decisão de produto explícita de não exigir mínimo de fontes válidas para emitir veredito |
| DT-27 | Retry: uma tentativa extra apenas na chamada de busca (Tavily), para erro 5xx e timeout, nunca para 401/429. Retry por artigo individual permanece em aberto (item 14) | Erro transitório de rede na busca é ponto único de falha para toda a verificação; retry por artigo é decisão de fase futura (RF-05) |
| DT-28 | 4 entradas da allowlist corrigidas para o host real que serve o conteúdo (`band.uol.com.br`→`www.band.com.br`, `lupa.uol.com.br`→`www.agencialupa.org`, `gzh.com.br`→`gauchazh.clicrbs.com.br`, Agência Gov ganha entrada própria `agenciagov.ebc.com.br` além de `agenciabrasil.ebc.com.br`). Lista final: 31 strings para 30 veículos. `AllowlistFilter` normaliza o prefixo `www.` dos dois lados da comparação (domínio armazenado e host do resultado) | Correção de bug de correspondência (Fase 3): o valor antigo nunca bateria via `include_domains`/sufixo; mesmos 30 veículos representados, sem nova curadoria |
| DT-29 | RF-07.3 — regra de vitória do rótulo por artigo: neutro não compete quando algum chunk produz `entailment`/`contradiction` acima do limiar (RF-07.5) | Medição real (Fase 3): chunk distrator deu `neutral` 0,9930 e chunk relevante deu `entailment` 0,9883 no mesmo artigo; a leitura literal da RF-07.3 (maior probabilidade entre todos os chunks) escolheria o distrator e rotularia o artigo como neutro. NLI tende a ser extremamente confiante ao declarar neutralidade sobre chunk fora do assunto, e RF-06.6 sempre envia até 3 chunks — sem essa regra, o pipeline colapsaria para SEM_INFORMACAO na maioria dos artigos reais |
| DT-30 | Dependências SPM integradas: SwiftSoup 2.9.6 e `swift-transformers` 1.3.3 (produto `Tokenizers`) | Nenhuma dependência de terceiros existia no projeto antes da Fase 3; necessárias para RF-05.2 (extração) e RF-06.3/RF-07.1 (tokenização, DT-06). `swift-transformers` traz 12 pacotes transitivos (swift-nio, swift-crypto, EventSource etc.) — peso maior que o esperado, ver item aberto 20 |
| DT-31 | Dois scripts distintos para assets gerados: `export_assets.py` produz tokenizers + `parity_fixture.json` a partir do Hugging Face Hub e **é versionado no git** (não muda a cada build); `scripts/sync-models.sh` copia os `.mlpackage` (113 MB + 103 MB) de builds já existentes em `spikes/02-coreml-latencia/build/` e `spikes/02c-nli-executavel/build/` — esses `.mlpackage` **não são versionados** (`.gitignore`) por excederem o limite de arquivo do GitHub | Quem clonar o repo com os spikes intactos só precisa rodar `sync-models.sh` antes do primeiro build; `export_assets.py` só precisa rodar de novo se houver suspeita de drift nos tokenizers (a validação é o `TokenizerParityTests` em Swift, não a existência do arquivo) |

---

## 7. Riscos e Pontos em Aberto

### 7.1 Riscos técnicos

| Risco | Impacto | Mitigação proposta |
|---|---|---|
| Modelos NLI/embeddings terem desempenho ruim em português | Alto — inviabiliza o núcleo do produto | Validar em PT-BR antes de qualquer trabalho de UI; testar modelos multilíngues |
| Conversão para Core ML falhar por operações não suportadas | Alto | Prototipar a conversão como primeira tarefa técnica, antes de qualquer código Swift |
| Tamanho do app ultrapassar limites razoáveis de download | Médio | Quantização agressiva; se insuficiente, avaliar download dos modelos sob demanda |
| Extração de texto principal falhar em muitos sites | Alto | Testar com amostra real dos domínios da allowlist antes de fixar a lista |
| Paywall e conteúdo via JavaScript reduzirem drasticamente as fontes utilizáveis | Alto | Selecionar domínios da allowlist priorizando sites com HTML estático acessível |
| ~~Bloqueio/rate-limit do scraping do DDG~~ — resolvido: substituído por Tavily (DT-11 revisada 2ª vez), sem sinal de bloqueio no Spike 5 | — | — |
| Vazamento de domínios fora da allowlist via `include_domains` da Tavily (confirmado no Spike 5, 20% das buscas de teste) | Médio | RF-03.5 como filtro obrigatório (não opcional) + RF-04.3 (over-fetch e truncar) |
| Throttling térmico em verificações consecutivas | Baixo | Limitar número de chunks processados; NLI é leve o suficiente |
| Reconstrução da feature afetar acidentalmente outras partes do app por acoplamento no `Verificador.swift` atual | Médio | Mapear todas as dependências/chamadas de/para `Verificador.swift` antes de deletar; separar em arquivos próprios (DT-17) |

### 7.2 Riscos de produto e conformidade

| Risco | Impacto | Mitigação proposta |
|---|---|---|
| Falso positivo/negativo levar o usuário a conclusão errada | Alto | Vereditos sempre referenciados às fontes; aviso de limitação visível; exibir sempre os trechos e links |
| Rejeição na App Store por agregação de conteúdo de terceiros (guideline 5.2) | Médio | Trechos curtos, atribuição clara, valor agregado evidente (análise, não republicação) |
| Rejeição por app incompleto se a extração de texto falhar com frequência (guideline 2.1) | Médio | Garantir degradação elegante e mensagens claras em vez de tela vazia |
| Violação de ToS ou `robots.txt` dos veículos consultados | Médio | Definir política de conformidade antes do lançamento |
| Critério de escolha da allowlist ser percebido como enviesado | Médio | Documentar publicamente o critério dentro do app |

### 7.3 Pontos em aberto (bloqueiam decisões de implementação)

1. ~~Modelos específicos com suporte comprovado a PT-BR~~ — resolvido: embeddings = `paraphrase-multilingual-MiniLM-L12-v2`; NLI = `MoritzLaurer/multilingual-MiniLMv2-L6-mnli-xnli` (rodando em `.cpuOnly`). Ver DT-18 (revisada) e seção 3.2.
2. ~~Provedor de busca~~ — decidido (2ª revisão): **Tavily**, substituindo o DDG por bloqueio sistemático confirmado (DT-11 revisada 2ª vez, evidência no Spike 5).
3. ~~Como proteger a chave de API da Tavily sem backend próprio~~ — resolvido: proxy serverless via Cloudflare Workers (DT-21). O app chama a URL do Worker, nunca a Tavily diretamente nem embarca a chave.
4. ~~Composição inicial e critério editorial da allowlist~~ — resolvido: reaproveita o conteúdo já existente em `trustedDomains` (RF-03.1). Formato de armazenamento é livre (RF-03.2).
5. ~~Estratégia de extração de palavras-chave para a query de busca~~ — resolvido: primeira frase truncada em 200 caracteres (RF-02.2, DT-22).
6. ~~Limiar mínimo de similaridade de cosseno para selecionar chunks~~ — resolvido: 0,25 (RF-06.7, DT-24).
7. ~~Limiar mínimo de confiança do NLI para aceitar um rótulo~~ — resolvido: 0,50 (RF-07.5, DT-25).
8. ~~Regra de desempate na agregação quando há neutros misturados~~ — resolvido (RF-08.3, DT-26).
9. **[EM ABERTO]** Versão mínima do iOS — a resolver por spike técnico (RD-01), não por suposição.
10. ~~Mecanismo de persistência local~~ — resolvido: não há persistência de verificações nesta feature (ver Fora de Escopo, seção 5).
11. **[EM ABERTO]** Viabilidade do tamanho do app após quantização; plano B se exceder o alvo.
12. **[EM ABERTO]** Política de conformidade com `robots.txt`.
13. ~~Existência de dataset de validação em PT-BR para calibrar os limiares~~ — resolvido: os dados de similaridade por par do Spike 2c serviram de base para RF-06.7/RF-07.5 (DT-24, DT-25), com validação adicional recomendada em spike futuro sobre chunks de artigo real.
14. **[PARCIALMENTE EM ABERTO]** Retry em caso de erro HTTP 5xx transiente — resolvido para a chamada de busca (uma tentativa extra, DT-27); retry por artigo individual (achado no Spike 3, `camara.leg.br`) continua em aberto, a tratar na fase de implementação de `ArticleExtractor`/RF-05.
15. ~~Biblioteca/abordagem de extração de texto em Swift para RF-05.2~~ — resolvido: porte tipo Readability sobre SwiftSoup (RF-05.2, DT-23).
16. ~~Se o campo `content` da Tavily substitui, complementa, ou é ignorado~~ — resolvido: usado apenas como fallback quando a extração própria falhar (RF-05.3, DT-23).
17. **[EM ABERTO]** Testar `search_depth="advanced"` da Tavily (2 créditos/chamada) — não avaliado se muda a taxa de vazamento de domínio (RF-03.5) ou a qualidade dos resultados o suficiente para justificar o custo.
18. **[EM ABERTO]** Formato do erro de cota esgotada e de rate-limit da Tavily (RF-10.2) — não observado nos spikes; só o erro 401 de chave inválida foi documentado.
19. **[EM ABERTO]** Paywall parcial (artigo com preview aberto + resto bloqueado) não foi testado empiricamente — RF-05.3 provavelmente cobre o caso (texto curto), mas não foi comprovado.
20. **[EM ABERTO]** Peso das dependências transitivas do `swift-transformers` (12 pacotes: swift-nio, swift-crypto, EventSource etc., ver DT-30) — avaliar se é aceitável ou se compensa isolar/trocar por implementação de tokenizer mais enxuta.
21. **[EM ABERTO]** Os dois `tokenizer.json` somam 34 MB versionados no repo (checksums diferentes, não deduplicáveis) — avaliar se cabe otimização (ex: strip de metadados) ou se fica assim.
22. **[EM ABERTO]** Deploy do proxy Cloudflare Workers (DT-21) — o código já existe (3 arquivos), mas não foi implantado. `TavilySearchService.proxyEndpoint` está vazio até o deploy acontecer; é ação do usuário (`wrangler login`/`wrangler deploy`), não do Claude Code.

### 7.4 Ordem sugerida de validação antes da implementação completa

1. Validar desempenho dos modelos em PT-BR (Python, no desktop).
2. Validar conversão para Core ML e medir latência real em dispositivo.
3. Validar extração de texto em amostra dos domínios candidatos.
4. Definir provedor de busca e testar restrição por domínio.
5. Só então iniciar a implementação do app.

---

## 8. Glossário

- **Chunk** — trecho de texto extraído do artigo, tratado como unidade de análise.
- **Embedding** — representação vetorial numérica do significado de um texto.
- **Similaridade de cosseno** — métrica de proximidade entre dois vetores; valores próximos de 1 indicam maior semelhança semântica.
- **NLI (Natural Language Inference)** — tarefa de classificar a relação entre uma premissa e uma hipótese como `entailment`, `contradiction` ou `neutral`.
- **Entailment** — a premissa sustenta a hipótese.
- **Contradiction** — a premissa contradiz a hipótese.
- **Neutral** — a premissa não permite concluir nada sobre a hipótese.
- **Allowlist** — lista fechada de domínios permitidos como fonte.
