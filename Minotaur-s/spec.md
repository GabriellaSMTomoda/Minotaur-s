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
- RF-02.2 — Estratégia de extração de palavras-chave: [EM ABERTO] — opções consideradas: (a) remoção de stopwords + top-N termos por frequência, (b) primeiras N palavras da afirmação, (c) modelo local leve.
- RF-02.3 — A query deve ser restrita aos domínios da allowlist usando o operador `site:` com `OR`.

### RF-03 — Allowlist de domínios confiáveis
- RF-03.1 — A composição da lista de domínios confiáveis já existe hoje como `trustedDomains`, em `VerificadorView`, e deve ser preservada como fonte da verdade do conteúdo (os domínios em si não mudam nesta reconstrução).
- RF-03.2 — O formato de armazenamento/estrutura de dados é livre para a reconstrução — não precisa continuar como propriedade da `VerificadorView`. Fica a critério da implementação (ex: struct/enum dedicado, arquivo JSON no bundle, etc.), desde que a lógica de verificação (busca, filtragem, extração) não dependa de acessar a `View` para obter os domínios.
- RF-03.3 — Cada domínio precisa continuar identificável por seu `domain` (string usada no filtro/`site:`). Campos adicionais (`displayName`, `enabled`, etc.) podem ser adicionados na migração se ajudarem a estrutura, mas não são obrigatórios caso não existam hoje.
- RF-03.4 — Nesta fase, a lista **não é editável pelo usuário** e não é atualizada remotamente — apenas migrada de lugar/formato, não de conteúdo.
- RF-03.5 — Resultados de busca cujo domínio não esteja na allowlist devem ser descartados, mesmo que retornados pelo buscador.
- RF-03.6 — Migrar `trustedDomains` para fora da `VerificadorView` faz parte da reconstrução (ver DT-17): a `View` não deve ser dona da fonte de dados usada pela lógica de negócio.

### RF-04 — Busca de artigos
- RF-04.1 — O app consulta um provedor de busca web restrito à allowlist.
- RF-04.2 — Provedor de busca: scraping de `html.duckduckgo.com`. Sem uso de API externa paga nesta fase. Ver DT-11 (revisada) e riscos associados em 7.2/7.3.
- RF-04.3 — O app recupera no máximo 5 resultados por verificação.
- RF-04.4 — Se nenhum resultado for retornado, o app exibe o veredito `NÃO ENCONTRADO` (ver RF-08) sem executar as etapas seguintes.
- RF-04.5 — Falha de rede na busca deve produzir mensagem de erro distinta de "não encontrado".

### RF-05 — Download e extração do conteúdo do artigo
- RF-05.1 — Para cada URL aprovada, o app baixa o HTML via `URLSession`.
- RF-05.2 — O app extrai o texto principal do artigo, descartando menu, rodapé, anúncios, comentários e blocos de "leia também".
- RF-05.3 — Se o texto extraído tiver menos de 200 caracteres, a fonte é considerada inválida e descartada (indica paywall, conteúdo via JavaScript ou falha de extração).
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
- RF-06.7 — Valor do limiar mínimo de similaridade: [EM ABERTO] — a calibrar empiricamente.

### RF-07 — Pipeline de análise: NLI
- RF-07.1 — Para cada chunk selecionado, executar o modelo NLI on-device com `premissa = chunk` e `hipótese = afirmação do usuário`.
- RF-07.2 — A saída do modelo é a distribuição de probabilidade entre `entailment`, `contradiction` e `neutral`.
- RF-07.3 — O resultado por artigo é o rótulo com maior probabilidade entre todos os chunks daquele artigo, com o respectivo score.
- RF-07.4 — Rótulos com confiança abaixo de um limiar mínimo são rebaixados para `neutral`.
- RF-07.5 — Valor do limiar mínimo de confiança do NLI: [EM ABERTO] — a calibrar empiricamente.

### RF-08 — Agregação e veredito final
- RF-08.1 — O veredito é agregado a partir dos rótulos por artigo, segundo as regras:
  - Nenhuma fonte válida analisada → `NÃO ENCONTRADO`
  - Maioria `entailment` → `CONFIRMADO PELAS FONTES`
  - Maioria `contradiction` → `CONTRADITO PELAS FONTES`
  - Todas `neutral` → `SEM INFORMAÇÃO SUFICIENTE`
  - Empate entre `entailment` e `contradiction` → `FONTES DIVERGENTES`
- RF-08.2 — O veredito nunca usa linguagem de verdade absoluta ("verdadeiro"/"falso"). Sempre referencia as fontes.
- RF-08.3 — Regra de desempate quando há empate parcial com neutros presentes: [EM ABERTO]

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

### 3.2 Modelos de ML
- Modelo de embeddings: `sentence-transformers/all-MiniLM-L6-v2` (ou equivalente), convertido para `.mlpackage`.
- Modelo NLI: modelo tipo `bart-large-mnli` / `roberta-large-mnli`, convertido para `.mlpackage` e quantizado (INT8 ou palettização).
- Suporte a português: [EM ABERTO] — modelos citados são majoritariamente treinados em inglês. É necessário validar desempenho em PT-BR ou selecionar alternativas multilíngues (ex: variantes XNLI / paraphrase-multilingual).
- Ambos os modelos são embarcados no bundle do app. Nenhum download de modelo em runtime nesta fase.

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
- NF-09 — N/A nesta fase: sem API de busca paga, não há chave a proteger. Reavaliar se o provedor mudar no futuro.
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
| DT-11 (revisada) | Scraping de `html.duckduckgo.com`, sem API externa | Decisão explícita do stakeholder nesta fase: custo zero e independência de chave de API. Risco de instabilidade e bloqueio aceito conscientemente (ver 7.2) |
| DT-12 | Vereditos referenciam as fontes, nunca afirmam verdade absoluta | Reduz risco de dano informacional e de rejeição na revisão da App Store |
| DT-13 | Nenhum servidor próprio; sem coleta de dados | Simplicidade, custo zero, menor exigência regulatória |
| DT-14 | Trechos citados limitados e sempre com link para o original | Reduz risco de violação de direitos autorais e de rejeição pela guideline 5.2 |
| DT-15 | `Verificador.swift` atual é destruído e reconstruído do zero na parte de lógica/análise | Implementação atual (artigo inteiro para `FoundationModels`) erra com frequência; não é base confiável para evolução incremental |
| DT-16 | Design visual/estrutura de UI da tela atual pode ser reaproveitado quando razoável | Não há problema identificado na UI, só na lógica de verificação; evita retrabalho desnecessário |
| DT-17 | A nova lógica deve ser separada em arquivo(s) próprio(s), não deve viver inteira em `Verificador.swift` | O problema original inclui estar "totalmente implementada no mesmo arquivo"; separar responsabilidades (busca, extração, embeddings, NLI, agregação) evita repetir esse defeito estrutural |

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
| Bloqueio/rate-limit do scraping do DDG (sem API oficial, risco aceito — DT-11 revisada) | Médio-Alto | Cachear resultados de busca por sessão; degradar com mensagem clara em vez de crash |
| Throttling térmico em verificações consecutivas | Baixo | Limitar número de chunks processados; NLI é leve o suficiente |
| Reconstrução da feature afetar acidentalmente outras partes do app por acoplamento no `Verificador.swift` atual | Médio | Mapear todas as dependências/chamadas de/para `Verificador.swift` antes de deletar; separar em arquivos próprios (DT-17) |

### 7.2 Riscos de produto e conformidade

| Risco | Impacto | Mitigação proposta |
|---|---|---|
| Falso positivo/negativo levar o usuário a conclusão errada | Alto | Vereditos sempre referenciados às fontes; aviso de limitação visível; exibir sempre os trechos e links |
| Rejeição na App Store por agregação de conteúdo de terceiros (guideline 5.2) | Médio | Trechos curtos, atribuição clara, valor agregado evidente (análise, não republicação) |
| Rejeição por app incompleto se o scraping falhar com frequência (guideline 2.1) | Médio | Garantir degradação elegante e mensagens claras em vez de tela vazia |
| Violação de ToS ou `robots.txt` dos veículos consultados | Médio | Definir política de conformidade antes do lançamento |
| Critério de escolha da allowlist ser percebido como enviesado | Médio | Documentar publicamente o critério dentro do app |

### 7.3 Pontos em aberto (bloqueiam decisões de implementação)

1. **[EM ABERTO]** Modelos específicos com suporte comprovado a PT-BR (embeddings e NLI).
2. ~~Provedor de busca~~ — decidido: scraping de `html.duckduckgo.com` (DT-11 revisada).
3. **[EM ABERTO]** Como proteger a chave de API sem backend próprio.
4. ~~Composição inicial e critério editorial da allowlist~~ — resolvido: reaproveita o conteúdo já existente em `trustedDomains` (RF-03.1). Formato de armazenamento é livre (RF-03.2).
5. **[EM ABERTO]** Estratégia de extração de palavras-chave para a query de busca.
6. **[EM ABERTO]** Limiar mínimo de similaridade de cosseno para selecionar chunks.
7. **[EM ABERTO]** Limiar mínimo de confiança do NLI para aceitar um rótulo.
8. **[EM ABERTO]** Regra de desempate na agregação quando há neutros misturados.
9. **[EM ABERTO]** Versão mínima do iOS — a resolver por spike técnico (RD-01), não por suposição.
10. ~~Mecanismo de persistência local~~ — resolvido: não há persistência de verificações nesta feature (ver Fora de Escopo, seção 5).
11. **[EM ABERTO]** Viabilidade do tamanho do app após quantização; plano B se exceder o alvo.
12. **[EM ABERTO]** Política de conformidade com `robots.txt`.
13. **[EM ABERTO]** Existência de dataset de validação em PT-BR para calibrar os limiares acima.

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
