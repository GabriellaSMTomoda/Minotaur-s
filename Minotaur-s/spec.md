# Especificação Técnica — Feature "Verificar Notícia" (iOS)

**Versão:** 0.5
**Status:** Implementado (Fases 1–6 concluídas). A auditoria histórica de 10/08/2026 permanece registrada na seção 7.3. Em 26/08/2026, a validação incremental de privacidade passou com 149 testes Swift + 8 testes de UI e build Release arm64 sem assinatura. A distribuição permanece bloqueada pelo provisioning de Siri, pela URL pública da política para a ficha da App Store e pelas validações listadas na seção 7.3.
**Escopo:** especificação e manutenção de UMA feature dentro de um app iOS com múltiplas funcionalidades.

---

## 0. Contexto do projeto (importante para o Claude Code)

O app já existe e possui **múltiplas funcionalidades**. Esta spec cobre **exclusivamente** a feature "Verificar Notícia". Nenhuma outra funcionalidade do app deve ser lida, alterada, refatorada ou "melhorada" como efeito colateral desta implementação.

**Estado atual (pós-reconstrução, Fases 1–6 concluídas):** a feature usa Tavily via proxy Cloudflare Workers já implantado e um pipeline on-device de embeddings + NLI (chunking → similaridade de cosseno → NLI → agregação) — sem `FoundationModels` e sem scraping do DuckDuckGo. A lógica vive separada por responsabilidade em `Services/Verificador/` e `Models/Verificador/` (DT-17). O NLI atual é o BERTimbau-base de três classes treinado no Spike 9, que substituiu tanto o MiniLM problemático quanto o BERTimbau-large que reprovou RAM/latência. Restam riscos de qualidade residuais e pendências de distribuição, mas a troca do modelo não está mais bloqueada.

**Estado anterior (motivação original da reconstrução, já destruído — DT-15):** antes desta spec, a feature estava implementada de forma ineficaz num único arquivo, `Verificador.swift`, que:
- fazia scraping do DuckDuckGo;
- enviava o artigo inteiro para o `FoundationModels` analisar de uma vez, sem chunking, sem embeddings, sem NLI.

Essa abordagem antiga errava com frequência, o que motivou a reconstrução completa desta spec (ver seção 6, DT-01, DT-15).

**O que PODE evoluir:** o design visual e a estrutura de UI do verificador, desde que os critérios de apresentação, acessibilidade, aviso e atribuição sejam preservados.

**O que NÃO pode voltar:** scraping de buscador, análise com `FoundationModels` ou lógica de negócio concentrada na View. O pipeline desta spec é a arquitetura vigente.

**Fora dos limites desta tarefa:** qualquer outra tela, feature, model, service ou utilitário do app que não pertença exclusivamente ao fluxo de "Verificar Notícia". Se durante a implementação for necessário tocar em código compartilhado (ex: um design system, um helper de rede genérico), isso deve ser sinalizado antes de alterar, não decidido silenciosamente.

## 1. Objetivo

Manter a feature "Verificar Notícia" capaz de determinar se uma afirmação digitada pelo usuário é **confirmada, contradita ou não coberta** por artigos de veículos de imprensa previamente definidos como confiáveis.

**Problema que resolve:** hoje o usuário precisa buscar manualmente, abrir vários sites e ler artigos inteiros para saber se uma informação que recebeu (ex: mensagem de WhatsApp) bate com o que a imprensa publicou. Esta feature automatiza busca, leitura e comparação semântica — substituindo a versão antiga, que analisava o artigo inteiro via `FoundationModels` sem estrutura e errava com frequência.

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
- RF-01.6 — Após consultar um resultado, o usuário deve conseguir voltar diretamente ao campo
  de entrada, editar a afirmação preservada e iniciar outra verificação sem sair da feature nem
  retornar à tela inicial do app.
- RF-01.7 — Na primeira entrada no Verificador, uma sheet não dispensável deve informar, antes de qualquer requisição, que somente a primeira frase limitada a `SearchQueryBuilder.maxQueryLength` é enviada ao proxy e à Tavily. Somente “Entendi e continuar” registra o reconhecimento; uma versão nova do aviso deve reapresentá-lo.
- RF-01.8 — A política de privacidade completa deve permanecer acessível offline por um botão `hand.raised` no toolbar, inclusive depois do reconhecimento do aviso.

### RF-02 — Geração da query de busca
- RF-02.1 — O app deve enviar como query somente a primeira frase da entrada, limitada a 200 caracteres; o texto completo nunca é enviado ao buscador.
- RF-02.2 — Estratégia definitiva: extrair a primeira frase da afirmação, truncada em 200 caracteres. Resolvido — descartado o saco-de-palavras: os vazamentos de domínio observados no Spike 5 concentraram-se em buscas dominadas por termo genérico isolado. Ver DT-22.
- RF-02.3 — A query deve ser restrita aos domínios da allowlist usando o parâmetro `include_domains` da API de busca (Tavily), com a lista completa de domínios em uma única chamada. Não é necessário construir `site:`/`OR` manualmente — a restrição é nativa da API.

### RF-03 — Allowlist de domínios confiáveis
- RF-03.1 — A fonte de verdade atual é `TrustedDomain.allowlist`, fora da UI. A lista final possui **31 strings para os mesmos 30 veículos** da curadoria original: os 4 domínios bloqueados no Spike 3 (`uol.com.br`, `espn.com.br`, `reuters.com`, `ibge.gov.br`) foram removidos; hosts incorretos foram corrigidos (`www.band.com.br`, `www.agencialupa.org`, `gauchazh.clicrbs.com.br`); e `agenciagov.ebc.com.br` ganhou entrada própria. Ver DT-28.
- RF-03.2 — A allowlist é um `Set<String>` estático em `Models/Verificador/TrustedDomain.swift`. Busca, filtro e extração não acessam nenhuma `View` para obter os domínios.
- RF-03.3 — Cada fonte permanece identificável por seu domínio. `displayName` ainda não existe; a UI exibe o domínio como nome da fonte (item 23 da seção 7.3).
- RF-03.4 — A lista **não é editável pelo usuário** nem atualizada remotamente.
- RF-03.5 — Resultados de busca cujo domínio não esteja na allowlist devem ser descartados, mesmo que retornados pelo buscador. **Este filtro é obrigatório, não defesa em profundidade**: o Spike 5 confirmou empiricamente que `include_domains` da Tavily não é um filtro 100% rígido — vazou domínios fora da allowlist em 4/20 buscas de teste (20%), incluindo 2 casos onde 100% dos resultados retornados eram de fora da lista (Wikipédia, dicionários online, sites sem relação jornalística).
- RF-03.6 — A fonte de dados deve permanecer fora de `VerificadorView` (migração já concluída; ver DT-17/DT-28).

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
- RF-07.5 — Limiar mínimo de confiança do NLI: **0,50**. O valor foi preservado na troca para BERTimbau-base; não deve ser reajustado para mascarar os dois erros adversariais residuais sem nova calibração e reabertura de DT-25.

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
- RF-09.3 — Cada fonte deve oferecer um botão explícito e destacado, seguindo componentes e
  cores semânticas do iOS, para abrir o artigo original no navegador (`SFSafariViewController`).
- RF-09.4 — Exibir um trecho curto (máx. 300 caracteres) do chunk que motivou o rótulo, com atribuição explícita ao veículo e link para o original.
- RF-09.5 — Exibir aviso permanente e visível: o resultado é uma análise automatizada, pode conter erros, e não substitui leitura das fontes.
- RF-09.6 — Listar quais domínios foram consultados naquela verificação. Exposto via `VerificationResult.consultedDomains` (ver DT-32 e seção 3.5) — presente mesmo em `NAO_ENCONTRADO` (CA-02).

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
| Deployment target atual | iOS 17.0, fixado no projeto Xcode e em `project.yml` |
| Inferência de ML | Core ML (on-device) |
| Tokenização | `swift-transformers`/XLM-R para embeddings; implementação WordPiece própria para NLI |
| Parsing de HTML | SwiftSoup |
| Rede | `URLSession` (async/await) |
| Álgebra vetorial | Accelerate framework (similaridade de cosseno) |
| Conversão de modelos | Python + `coremltools` + `transformers` (offline, fora do app) |
| Proxy de API (proteção de chave) | Cloudflare Workers (serverless, tier gratuito) — ver DT-21 |

Versões mínimas configuradas na integração (DT-30): SwiftSoup 2.9.6; `swift-transformers` 1.3.3 (produto `Tokenizers`). O `Package.resolved` local pode apontar uma versão compatível mais recente do SwiftSoup.

### 3.2 Modelos de ML
- **Modelo de embeddings (definitivo):** `paraphrase-multilingual-MiniLM-L12-v2`, convertido para `.mlpackage`, quantizado INT8 (~113 MB). Validado em PT-BR no Spike 1; conversão validada no Spike 2 (cos=0,9999 vs. PyTorch); latência em device físico = 7 ms (Spike 2, medição com Xcode completo), bem abaixo de NF-01.
- **Modelo de NLI definitivo, revisado 3ª vez — Spike 9:** BERTimbau-base (108.925.443 parâmetros), fine-tune próprio de três classes em PLUE/MNLI, rodando em **`.cpuOnly`**. O MLProgram INT8/FP16 mede ~104 MB e recebe `input_ids`, `attention_mask` e `token_type_ids` produzidos pelo `BERTTokenizer` WordPiece. A ordem `[entailment, neutral, contradiction]` foi confirmada empiricamente, não inferida apenas do `id2label`. Ver DT-18 (revisada 3ª vez), DT-35, DT-36 e DT-37.
  - **Qualidade real:** 13/15 em pares adversariais extraídos de artigos, 6/6 nos casos críticos de Terra plana e vacina, sem `entailment` indevido nesses seis casos. Os dois erros residuais envolvem a alegação “Brasileiro encontrou cura do câncer”, que exige distinguir tratamento, remissão e fala atribuída de uma cura geral. A estabilidade a pequenas redações de claims curtos ficou em 2/3 famílias.
  - **Paridade e integração:** tokenização Swift/Hugging Face e saídas Core ML/PyTorch passaram; a suíte documentada registrou 145/145 testes no simulador e 28/28 testes focados no iPhone 16. O build Release arm64 sem assinatura também passou.
  - **RAM e latência:** no gate físico do Spike 9, o modelo base atingiu no máximo 383,7 MB residentes e 66,5 ms aquecidos a 512 tokens, resolvendo a reprovação do BERTimbau-large. A medição direta no iPhone 13 ainda é uma validação de release recomendada.
  - **Histórico:** `mDeBERTa-v3-base-xnli` convertia e preservava logits, mas não executava em aparelhos reais; `multilingual-MiniLMv2-L6-mnli-xnli` era rápido, porém confirmava desinformação em texto jornalístico real; BERTimbau-large melhorou a qualidade, mas violou os limites de RAM e latência no Spike 8. O fine-tune base preservou a base linguística PT-BR com custo operacional viável.
  - **Lição estrutural:** “converte sem erro” ≠ “executa em device”, e “acerta pares limpos” ≠ “acerta texto real”. Toda troca futura exige aparelho físico, paridade, métricas de recurso e pares adversariais reais.
- Suporte a português: **resolvido.** Embeddings e NLI foram validados em PT-BR e executam em aparelho físico.
- Ambos os modelos são embarcados no bundle do app. Nenhum download de modelo em runtime nesta fase.
- Tamanho combinado dos modelos (embeddings + NLI, INT8): aproximadamente **113 + 104 = 217 MB**. O tokenizer de embeddings ocupa ~16 MB e o WordPiece do NLI ~0,7 MB. O app Release sem assinatura mediu 262 MiB descompactados; o tamanho final de distribuição continua pendente em NF-05.



### 3.3 Performance
- NF-01 — Inferência de embeddings de um chunk: < 150 ms em iPhone 13 ou superior.
- NF-02 — Inferência de NLI de um par (chunk, afirmação): < 1 s em iPhone 13 ou superior. **Atendido no gate disponível:** o BERTimbau-base mediu 66,5 ms aquecido a 512 tokens no iPhone 16. A confirmação direta no iPhone 13 permanece recomendada antes do lançamento.
- NF-03 — Tempo total de uma verificação (busca + download + análise), com rede estável: < 15 s. O custo de NLI caiu para a faixa de dezenas de milissegundos por par no gate físico; o tempo total continua dependente da busca e do download dos artigos e deve ser acompanhado em testes ponta a ponta.
- NF-04 — O download e o parsing de artigos ocorrem concorrentemente; nenhuma operação bloqueia a main thread.
- NF-05 — Tamanho total do app após otimização dos modelos: alvo < 500 MB. **Parcialmente validado em 10/08/2026:** o `.app` Release arm64 sem assinatura mediu 267.536 KiB (261 MiB) descompactados. [EM ABERTO] — medir archive/`.ipa` assinado e tamanho estimado pela App Store após corrigir o provisioning.
- NF-06 — Uso de RAM em pico durante a análise: < 1 GB. **Atendido no gate do Spike 9:** 383,7 MB residentes máximos no iPhone 16 com o BERTimbau-base, contra 1.224 MB do BERTimbau-large descartado. A medição em aparelho de 4 GB continua desejável, mas o modelo atual recuperou margem substancial sob o teto.

### 3.4 Segurança e privacidade
- NF-07 — Nenhum backend próprio stateful: o único endpoint próprio é o proxy serverless da Tavily, sem KV, D1, cache de conteúdo ou logging explícito do corpo. O texto completo não é armazenado nem enviado remotamente; a Tavily pode reter a query reduzida conforme sua política.
- NF-08 — **Resolvido em 26/08/2026:** o texto do usuário só sai do dispositivo na forma da primeira frase limitada a 200 caracteres, enviada como query ao proxy/Tavily. O aviso de primeira execução e a política informam o contrato, e um teste de integração inspeciona o corpo HTTP real antes do proxy.
- NF-09 — **Resolvido:** a chave de API da Tavily é protegida por um proxy serverless (Cloudflare Workers, tier gratuito — ver DT-21). O app nunca embarca a chave nem a envia diretamente à Tavily; toda chamada de busca passa pela URL do Worker, que injeta a chave e repassa a resposta.
- NF-10 — Todo o tráfego via HTTPS. ATS (App Transport Security) mantido com configuração padrão, sem exceções de domínio.
- NF-11 — Política de privacidade acessível dentro do app e por URL pública na ficha da loja. **[PARCIALMENTE RESOLVIDO em 26/08/2026]** A política offline está permanentemente acessível no toolbar e o manifesto próprio está no bundle; ainda falta publicar uma URL pública para o App Store Connect.

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
  "consultedDomains": ["exemplo.com.br", "outroexemplo.org"],
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

### CA-12 — Nova verificação na mesma sessão
**Dado** que uma verificação foi concluída e o resultado está visível,
**quando** o usuário volta para a entrada, toca no campo, edita a afirmação e verifica novamente,
**então** a segunda verificação é iniciada com o novo texto sem retornar à tela inicial do app.

### CA-13 — Privacidade na primeira entrada e acesso permanente
**Dado** uma instalação nova ou uma versão do aviso ainda não reconhecida,
**quando** o usuário entra no Verificador,
**então** o aviso não dispensável aparece antes de qualquer requisição, a política completa pode ser lida sem registrar reconhecimento, somente “Entendi e continuar” persiste a versão e o botão de política continua acessível após o relançamento sem reapresentar o aviso reconhecido.

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
| DT-06 (revisada) | Tokenização em Swift: XLM-R via `swift-transformers` para embeddings e WordPiece próprio para NLI | O modelo BERT do Spike 9 exige montagem de par e `token_type_ids`; a implementação dedicada tem fixture de paridade com Hugging Face |
| DT-07 | Chunking por parágrafo com sobreposição de 1 frase | Equilíbrio entre preservar contexto e manter relevância da similaridade |
| DT-08 | Top-3 chunks por artigo para o NLI | O chunk mais similar isolado pode não conter a informação decisiva |
| DT-09 | Similaridade de cosseno como métrica de relevância | Padrão para `sentence-transformers`; implementável com Accelerate |
| DT-10 (revisada) | Allowlist embarcada e fixa em `TrustedDomain.allowlist`, fora da camada de UI | Preserva a curadoria e separa dados de negócio da View, alinhado a DT-17 |
| DT-11 (revisada 2ª vez) | **Tavily** como provedor de busca, substituindo o scraping do DuckDuckGo | O scraping do DDG bloqueou de forma sistemática em 2 clientes HTTP diferentes (Python e Swift/URLSession — Spikes 4 e 4b), inclusive em uso leve. As 3 alternativas originalmente pesquisadas (Bing, Brave, Google Custom Search) estão inviabilizadas: Bing foi descontinuada (ago/2025), Brave eliminou o tier gratuito (fev/2026, exige cartão sem teto de gasto), Google Custom Search está fechada para novos clientes desde 2025. Tavily oferece 1.000 créditos/mês grátis sem cartão, com `include_domains` nativo, validado tecnicamente no Spike 5 (100% de disponibilidade em 20 buscas, latência média 1,62s, sem nenhum sinal de bloqueio) |
| DT-12 | Vereditos referenciam as fontes, nunca afirmam verdade absoluta | Reduz risco de dano informacional e de rejeição na revisão da App Store |
| DT-13 | Nenhum servidor próprio tradicional ou histórico de verificações; transmissão limitada à query reduzida | Simplicidade, custo zero e minimização de dados. Exceção pontual: DT-21 (proxy serverless da Tavily) — o proxy não persiste conteúdo, mas a query reduzida é transmitida à Cloudflare/Tavily e pode ser retida pela Tavily conforme sua política |
| DT-14 | Trechos citados limitados e sempre com link para o original | Reduz risco de violação de direitos autorais e de rejeição pela guideline 5.2 |
| DT-15 | A antiga lógica monolítica de `Verificador.swift` foi descartada e reconstruída | A versão que enviava o artigo inteiro a `FoundationModels` errava com frequência; a lógica atual está nos serviços e no coordenador |
| DT-16 | Design visual/estrutura de UI da tela atual pode ser reaproveitado quando razoável | Não há problema identificado na UI, só na lógica de verificação; evita retrabalho desnecessário |
| DT-17 | A nova lógica deve ser separada em arquivo(s) próprio(s), não deve viver inteira em `Verificador.swift` | O problema original inclui estar "totalmente implementada no mesmo arquivo"; separar responsabilidades (busca, extração, embeddings, NLI, agregação) evita repetir esse defeito estrutural |
| DT-18 (revisada 3ª vez) | Modelo de NLI definitivo: BERTimbau-base com fine-tune próprio de três classes em PLUE/MNLI, `.cpuOnly`, MLProgram INT8/FP16 ~104 MB | Substitui o MiniLM que falhava em texto real e o BERTimbau-large que violava NF-02/NF-06. Spike 9: 13/15 pares adversariais, 6/6 casos críticos, 383,7 MB residentes máximos e 66,5 ms aquecidos a 512 tokens no iPhone 16. Requer WordPiece e `token_type_ids`; ordem empírica `[entailment, neutral, contradiction]` |
| DT-19 | Solicitar mais resultados da API do que o necessário (8-10) e truncar para 5 depois do filtro de allowlist | Reduz a taxa de vazamento de domínios fora da allowlist observada no Spike 5 (evidência: mesma busca vazou 4/5 com max_results=5, mas retornou 10/10 corretos com max_results=10) |
| DT-20 | Domínios `*.gov.br` na allowlist continuam validando por sufixo, incluindo subdomínios de prefeituras/órgãos menores, não só o portal federal | Decisão consciente do stakeholder: simplicidade da regra de correspondência sobrepõe o risco de incluir órgãos públicos menores, que ainda são fontes governamentais legítimas |
| DT-21 | Proteção da chave da Tavily via proxy serverless (Cloudflare Workers) | Chave embarcada no binário é extraível por engenharia reversa (consenso técnico, inclusive de post do DTS da Apple); proxy é a única proteção real. Cloudflare Workers: tier gratuito de 100.000 req/dia, sem custo, manutenção mínima (função stateless, não é servidor 24/7 tradicional) — não contradiz o espírito de DT-13 (evitar backend pesado) |
| DT-22 | `SearchQueryBuilder`: primeira frase da afirmação, truncada em 200 caracteres | Saco-de-palavras testado empiricamente (Spike 5) concentra os vazamentos de domínio em termo genérico isolado; primeira frase preserva contexto sintático da afirmação |
| DT-23 | `ArticleExtractor`: porte tipo Readability sobre SwiftSoup (pontuação por bloco), com o campo `content` da Tavily como fallback — nunca substituto — quando a extração própria resultar em <200 chars | Pontuação por bloco resolve armadilhas do Spike 3 que a heurística por denylist não cobria; fallback resgata fontes com extração difícil sem enfraquecer RF-05.3 como regra padrão |
| DT-24 | Limiar de similaridade de cosseno: 0,25 | Calibrado com dados reais de similaridade por par do Spike 2c (pares decisivos 0,31–0,86; neutros 0,09–0,17) |
| DT-25 | Limiar de confiança do NLI: 0,50 | Calibrado na reconstrução e preservado na troca de modelo; qualquer mudança exige dados adicionais e não pode servir apenas para ajustar fixtures residuais |
| DT-26 | Regra de desempate na agregação (RF-08.3): neutro não vota; E>C→CONFIRMADO, C>E→CONTRADITO, E=C>0→DIVERGENTES, E+C=0→NÃO_ENCONTRADO/SEM_INFORMACAO conforme o caso. **Sem piso mínimo de fontes válidas** | Fecha RF-08.3 sem introduzir veredito novo; decisão de produto explícita de não exigir mínimo de fontes válidas para emitir veredito |
| DT-27 | Retry: uma tentativa extra apenas na chamada de busca (Tavily), para erro 5xx e timeout, nunca para 401/429. Retry por artigo individual permanece em aberto (item 14) | Erro transitório de rede na busca é ponto único de falha para toda a verificação; retry por artigo é decisão de fase futura (RF-05) |
| DT-28 | 4 entradas da allowlist corrigidas para o host real que serve o conteúdo (`band.uol.com.br`→`www.band.com.br`, `lupa.uol.com.br`→`www.agencialupa.org`, `gzh.com.br`→`gauchazh.clicrbs.com.br`, Agência Gov ganha entrada própria `agenciagov.ebc.com.br` além de `agenciabrasil.ebc.com.br`). Lista final: 31 strings para 30 veículos. `AllowlistFilter` normaliza o prefixo `www.` dos dois lados da comparação (domínio armazenado e host do resultado) | Correção de bug de correspondência (Fase 3): o valor antigo nunca bateria via `include_domains`/sufixo; mesmos 30 veículos representados, sem nova curadoria |
| DT-29 | RF-07.3 — regra de vitória do rótulo por artigo: neutro não compete quando algum chunk produz `entailment`/`contradiction` acima do limiar (RF-07.5) | Medição real (Fase 3): chunk distrator deu `neutral` 0,9930 e chunk relevante deu `entailment` 0,9883 no mesmo artigo; a leitura literal da RF-07.3 (maior probabilidade entre todos os chunks) escolheria o distrator e rotularia o artigo como neutro. NLI tende a ser extremamente confiante ao declarar neutralidade sobre chunk fora do assunto, e RF-06.6 sempre envia até 3 chunks — sem essa regra, o pipeline colapsaria para SEM_INFORMACAO na maioria dos artigos reais |
| DT-30 | Dependências SPM integradas: SwiftSoup 2.9.6 e `swift-transformers` 1.3.3 (produto `Tokenizers`) | Nenhuma dependência de terceiros existia no projeto antes da Fase 3; necessárias para RF-05.2 (extração) e RF-06.3/RF-07.1 (tokenização, DT-06). `swift-transformers` traz 12 pacotes transitivos (swift-nio, swift-crypto, EventSource etc.) — peso maior que o esperado, ver item aberto 20 |
| DT-31 (revisada) | `spikes/09-nli-base-search/export_app_assets.py` exporta tokenizer WordPiece, labels e fixture do checkpoint selecionado; `scripts/sync-models.sh` copia os `.mlpackage` de embeddings (~113 MB) e NLI base (~104 MB) dos Spikes 2 e 9 | Os pesos não são versionados por excederem o limite do GitHub. Em máquina nova, sincronizar modelos antes do build; regenerar assets somente a partir do checkpoint validado e confirmar com `TokenizerParityTests` |
| DT-32 | `VerificationResult` carrega `consultedDomains: [String]`, em vez de o coordenador expor essa lista separadamente | RF-09.6/CA-02 exigem exibir os domínios consultados independente do veredito (inclusive em `NAO_ENCONTRADO`); manter no mesmo modelo evita a View gerenciar dois retornos distintos do pipeline por uma única lista |
| DT-33 | Chunks sem valor proposicional são descartados antes do NLI: comprimento mínimo, ausência de verbo, e padrões de byline/navegação/legenda/título de página. Artigo cujo único chunk seja desse tipo não vira fonte válida. As regras de estrutura de página rodam **por parágrafo, dentro do `TextChunker`**; comprimento e verbo rodam no chunk montado | Investigação pós-Fase 5 encontrou premissas como "Navegue direto pelo app Por Giulia Vidale — São Paulo 27/04/2023 15h57" e uma fonte inteira cujo único chunk era o título de um Web Story, que votou `entailment`. A separação por etapa existe porque a sobreposição de 1 frase (RF-06.1) faz linha de navegação vazar como prefixo do chunk seguinte — filtrar só a saída do chunker descartaria o parágrafo legítimo junto |
| DT-34 | **Verificação por negação descartada** (opção B avaliada no Spike 7): não rodar o par com a afirmação negada como hipótese | Resultado negativo e conclusivo. Leitura por simetria **nunca disparou** (0 vezes em 4 modelos × 5 limiares × 2 fontes de negação) — a premissa "o chunk sustenta tanto X quanto ¬X" é empiricamente falsa: os modelos são confiantemente assimétricos mesmo quando erram (Terra plana no `inferbr`: P(ent\|X)=1,000, P(ent\|¬X)=0,007, rótulo direto errado). Leitura diferencial **nunca superou** o argmax direto em nenhum modelo. Além disso, gerar negação em PT-BR on-device com `NLTagger` acerta só 8/14, falhando justamente em "Vacina da gripe causa infarto." ("causa" não é marcado como verbo, é homógrafo do substantivo) |
| DT-35 | **Fine-tune próprio executado:** BERTimbau-base de 3 classes treinado em PLUE/MNLI | O Spike 8 provou que BERT-large não cabia. A arquitetura base reduziu RAM/latência e manteve qualidade adversarial superior aos modelos públicos avaliados; não existia checkpoint público equivalente de três classes |
| DT-36 | **Ordem de gates para o fine-tune**: medir RAM e latência da *arquitetura* (BERTimbau-base convertido com cabeça de 3 classes **não treinada**) **antes** de gastar tempo de GPU no treino | RAM e latência dependem da arquitetura e do shape, não dos valores dos pesos. Se a arquitetura não couber na NF-06/NF-02, o treino seria desperdiçado. Extensão natural da lição do Spike 2c (gate de execução antes de qualidade) para o caso em que a "qualidade" custa dias de trabalho |
| DT-37 | Integração do checkpoint BERTimbau-base selecionado no Spike 9, preservando os limiares, agregação e contrato de UI existentes | A troca passou paridade, gates adversariais, 145 testes no simulador, 28 testes físicos e build Release sem assinatura. Não houve migração de dados nem alteração dos vereditos; o rollback é de código e assets |
| DT-38 | Aviso do Verificador reconhecido por versão inteira em `UserDefaults.standard`, política offline no app e manifesto próprio com `Other User Content`, `Search History` e motivo `CA92.1` para UserDefaults | Reapresenta mudanças materiais sem manter histórico de verificações; alinha o bundle ao envio real da query reduzida. O proxy continua stateless, mas a política distingue o possível processamento técnico da Cloudflare e a retenção declarada pela Tavily |

---

## 7. Riscos e Pontos em Aberto

### 7.1 Riscos técnicos

| Risco | Impacto | Mitigação proposta |
|---|---|---|
| Modelos NLI/embeddings terem desempenho ruim em português | Alto — inviabiliza o núcleo do produto | Validar em PT-BR antes de qualquer trabalho de UI; testar modelos multilíngues |
| **[MITIGADO, pós-Spike 9] O NLI antigo confirmava notícias comprovadamente falsas** — “A Terra é plana” e “Vacina da gripe causa infarto” produziam confirmações indevidas | Crítico no modelo anterior; não reproduzido nos seis pares críticos do modelo atual | Causa raiz era o julgamento do MiniLM sobre texto jornalístico que repete uma alegação para refutá-la, agravado por chunks de ruído. A limpeza DT-33 e o BERTimbau-base DT-18/DT-37 produziram 6/6 nos casos críticos. O risco geral de erro de NLI permanece: o modelo atual erra 2/15 pares adversariais e exige aviso, evidência e link sempre visíveis |
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

### 7.3 Pontos resolvidos e pendências de release/evolução

1. ~~Modelos específicos com suporte comprovado a PT-BR~~ — resolvido: embeddings = `paraphrase-multilingual-MiniLM-L12-v2`; NLI = BERTimbau-base com fine-tune próprio PLUE/MNLI, em `.cpuOnly`. Ver DT-18 (revisada 3ª vez) e seção 3.2.
2. ~~Provedor de busca~~ — decidido (2ª revisão): **Tavily**, substituindo o DDG por bloqueio sistemático confirmado (DT-11 revisada 2ª vez, evidência no Spike 5).
3. ~~Como proteger a chave de API da Tavily sem backend próprio~~ — resolvido: proxy serverless via Cloudflare Workers (DT-21). O app chama a URL do Worker, nunca a Tavily diretamente nem embarca a chave.
4. ~~Composição inicial e critério editorial da allowlist~~ — resolvido: conteúdo migrado para `TrustedDomain.allowlist`, um `Set<String>` estático fora da UI (RF-03.1/RF-03.2).
5. ~~Estratégia de extração de palavras-chave para a query de busca~~ — resolvido: primeira frase truncada em 200 caracteres (RF-02.2, DT-22).
6. ~~Limiar mínimo de similaridade de cosseno para selecionar chunks~~ — resolvido: 0,25 (RF-06.7, DT-24).
7. ~~Limiar mínimo de confiança do NLI para aceitar um rótulo~~ — resolvido: 0,50 (RF-07.5, DT-25).
8. ~~Regra de desempate na agregação quando há neutros misturados~~ — resolvido (RF-08.3, DT-26).
9. ~~Deployment target do projeto~~ — configurado em iOS 17.0. **[EM ABERTO, release]** Confirmar por teste em aparelho/simulador iOS 17 que todos os caminhos usados são compatíveis antes da distribuição.
10. ~~Mecanismo de persistência local~~ — resolvido: não há persistência de verificações nesta feature (ver Fora de Escopo, seção 5).
11. **[PARCIALMENTE RESOLVIDO]** Em 10/08/2026, o `.app` Release arm64 sem assinatura mediu 267.536 KiB (261 MiB), abaixo do alvo de 500 MB, e continha exatamente os dois modelos compilados esperados. Ainda falta medir archive/`.ipa` assinado e a estimativa final da App Store.
12. **[EM ABERTO]** Política de conformidade com `robots.txt`.
13. ~~Existência de dataset de validação em PT-BR para calibrar os limiares~~ — resolvido: os dados de similaridade por par do Spike 2c serviram de base para RF-06.7/RF-07.5 (DT-24, DT-25), com validação adicional recomendada em spike futuro sobre chunks de artigo real.
14. **[PARCIALMENTE EM ABERTO]** Retry em caso de erro HTTP 5xx transiente — resolvido para a chamada de busca (uma tentativa extra, DT-27); retry por artigo individual (achado no Spike 3, `camara.leg.br`) continua em aberto para evolução de `ArticleExtractor`/RF-05.
15. ~~Biblioteca/abordagem de extração de texto em Swift para RF-05.2~~ — resolvido: porte tipo Readability sobre SwiftSoup (RF-05.2, DT-23).
16. ~~Se o campo `content` da Tavily substitui, complementa, ou é ignorado~~ — resolvido: usado apenas como fallback quando a extração própria falhar (RF-05.3, DT-23).
17. **[EM ABERTO]** Testar `search_depth="advanced"` da Tavily (2 créditos/chamada) — não avaliado se muda a taxa de vazamento de domínio (RF-03.5) ou a qualidade dos resultados o suficiente para justificar o custo.
18. **[EM ABERTO]** Formato do erro de cota esgotada e de rate-limit da Tavily (RF-10.2) — não observado nos spikes; só o erro 401 de chave inválida foi documentado.
19. **[EM ABERTO]** Paywall parcial (artigo com preview aberto + resto bloqueado) não foi testado empiricamente — RF-05.3 provavelmente cobre o caso (texto curto), mas não foi comprovado.
20. **[EM ABERTO]** Peso das dependências transitivas do `swift-transformers` (12 pacotes: swift-nio, swift-crypto, EventSource etc., ver DT-30) — o NLI já não depende desse pacote para tokenização, mas embeddings ainda dependem; avaliar o custo no archive real antes de substituir.
21. ~~Peso duplicado dos tokenizers~~ — resolvido pela migração do NLI para WordPiece: `EmbeddingsTokenizer.json` ocupa ~16 MB e `NLITokenizer.json` ~0,7 MB, cerca de 17 MB no total em vez de 34 MB.
22. ~~Deploy do proxy Cloudflare Workers~~ — resolvido: o Worker foi implantado e `TavilySearchService.proxyEndpoint` contém a URL de produção. A chave permanece somente no secret `TAVILY_API_KEY`.
23. **[EM ABERTO, não bloqueia]** RF-09.2 exibe o `domain` como nome do veículo, já que RF-03.3 não exige `displayName`. Melhoria de produto possível em fase futura (nomes amigáveis por veículo), não é requisito atual.
24. ~~Como corrigir a confirmação de notícias falsas do MiniLM~~ — resolvido pela limpeza de chunks (DT-33) e pela integração do BERTimbau-base (DT-18/DT-37). O modelo atual passou 6/6 nos casos críticos; o risco geral de classificação incorreta permanece declarado.
25. **[PARCIALMENTE EM ABERTO, não bloqueia]** Robustez a afirmações curtas: o BERTimbau-base ficou estável em 2/3 famílias, contra 3/3 do large descartado. Manter como conjunto de regressão e não compensar silenciosamente com threshold.
26. **[EM ABERTO, não bloqueia]** Erro residual do BERTimbau-base: dois dos 15 pares, ligados a “Brasileiro encontrou cura do câncer”, ainda perdem quantificador, modalidade ou atribuição de fala. Possível margem entre `entailment` e `contradiction` só pode ser avaliada com dados adicionais e reabertura explícita de DT-25/DT-29; não ajustar para fazer o fixture passar.
27. ~~RAM e latência que bloqueavam a Fase 6~~ — resolvido pelo fine-tune BERTimbau-base (DT-35/DT-36): 383,7 MB residentes máximos e 66,5 ms aquecidos a 512 tokens no iPhone 16. **[EM ABERTO, release]** Repetir o gate no iPhone 13/4 GB para validar diretamente o aparelho-alvo mais antigo.
28. ~~Contaminação de medições por pouco espaço em disco~~ — transformada em regra operacional: todo gate físico deve registrar o espaço livre e exigir preflight confortável. A integração do Spike 9 foi executada com 2.636 MB livres.
29. **[EM ABERTO — BLOQUEIA DISTRIBUIÇÃO ASSINADA]** Em 10/08/2026, o archive falhou com `Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the Siri capability.` e `doesn't include the com.apple.developer.siri entitlement.` Ação mínima: autenticar no Xcode a conta da equipe `2DK23BZ7KB` e regenerar/baixar o profile de `com.julia.fatoufarsa2025` com Siri; não remover Siri ou entitlements.
30. **[PARCIALMENTE RESOLVIDO — AINDA BLOQUEIA PREPARAÇÃO DE LOJA]** Em 26/08/2026, NF-08 e a parte local de NF-11 foram implementadas: aviso versionado e não dispensável, política offline permanente e `PrivacyInfo.xcprivacy` próprio na raiz do bundle. Falta publicar a política em uma URL pública para o App Store Connect.
31. **[AUDITORIA FINAL 10/08/2026]** RF-01–RF-10 e CA-01–CA-12 têm cobertura automatizada e passaram (143 testes Swift + 6 UI). Lacunas não comprovadas nesta execução: CA-01/NF-03 ponta a ponta com rede real abaixo de 15 s, paywall parcial, respostas reais de cota/rate-limit, iOS 17 runtime e gate direto no iPhone 13. ATS permaneceu padrão sem exceções, AppIcon 1024×1024 e versão 1.0/build 1 foram compilados, e a varredura de segredos de aplicação nos arquivos versionados não encontrou credenciais.
32. **[VALIDAÇÃO INCREMENTAL 26/08/2026]** 149/149 testes Swift Testing e 8/8 testes de UI passaram no iPhone 16e Simulator/iOS 18.6. Foram comprovados: instalação nova e versionamento do aviso, reconhecimento explícito, relançamento, acesso permanente à política, limite de 200 caracteres no corpo enviado ao proxy, conteúdo obrigatório da política, manifesto exato, modo claro/escuro, Dynamic Type de acessibilidade XXXL e rótulos acessíveis básicos. `plutil` aprovou o manifesto-fonte e o manifesto copiado sem alteração para a raiz do `.app`; o build Release arm64 sem assinatura passou e mediu 268.516 KiB. A URL pública continua fora do repositório e pendente.

### 7.4 Ordem obrigatória para futuras trocas estruturais

1. Validar desempenho dos modelos em PT-BR (Python, no desktop).
2. Validar conversão para Core ML e medir latência real em dispositivo.
3. Validar extração de texto em amostra dos domínios candidatos.
4. Definir provedor de busca e testar restrição por domínio.
5. Só então integrar a mudança ao app e repetir a suíte completa.

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
