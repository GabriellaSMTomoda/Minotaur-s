# Especificação do Verificador de Notícias — v0.6

Atualizada em 24/11/2026. A v0.6 substitui a agregação "qualquer voto" da v0.5, que devolvia DIVERGENTE em 77 de 120 afirmações do conjunto dev (inclusive fatos triviais), pela **política de evidência v3**: NLI por frase, portões de relevância por passagem e soma por origem independente. Também acrescenta a Wikipédia PT como fonte gratuita. Os números de desenvolvimento estão em `evaluation/IMPLEMENTATION_STATUS.md`; vêm de um conjunto **dev, não-gold**, e não atestam precisão geral. Continua sem API de LLM, com Core ML local e busca dentro da cota gratuita. As evidências históricas permanecem em `spikes/` e no Git.

## 1. Escopo e arquitetura

Apenas o fluxo Verificador, em Swift/SwiftUI e iOS 17+, para público leigo brasileiro. Preservar quiz, Pergunta do Dia, Siri, Atalhos, bundle ID/equipe e `VerificadorView()` sem argumentos.

Fluxo: `ClaimAnalyzer → plano de consultas → busca/leitura concorrentes (+ Wikipédia PT em paralelo) → artigo com metadados → janelas de recuperação → BM25 + embeddings → frases-premissa → NLI → EvidenceScorer (portões por passagem) → VerdictAggregator (soma por origem) → resultado`.

`VerificationPipeline` é o único coordenador. Serviços dependem de protocolos; ViewModel apresenta seleção/progresso/erros e usa `VerificationRunner` actor. Core ML e extração ficam fora da main thread. Textos/resultados vivem somente em memória da sessão.

Proibidos: API de LLM, FoundationModels, scraping de buscador, geração automática de negação, contorno de paywall, logs/histórico de consultas, envio de resultados/telemetria. Os únicos serviços de busca são a API oficial Tavily e a API pública da Wikipédia PT, ambas via Worker.

## 2. Requisitos funcionais

### Entrada e contexto

RF-01: campo de 15–1.000 caracteres, validação próxima ao campo, cancelamento e edição posterior preservados. Reconhecer frases sem reescrever atribuição, negação, números ou sujeitos. Várias frases exigem escolha explícita; referências dependentes e certas conjunções ambíguas exigem reformulação. Não há promessa de decomposição linguística perfeita. A frase escolhida é a mesma hipótese usada em busca/recuperação/NLI. Hipótese muito longa para preservar 64 tokens de premissa exige reformulação.

RF-02: plano de uma a três consultas, até 200 caracteres cada, sem negação gerada. Consulta principal descritiva; complemento contextual para texto longo/situação atual e busca de checagens quando necessário. Datas relativas são resolvidas com referência em America/Sao_Paulo. Distinguir contexto atemporal, histórico, recente e atual; data de publicação é uma pista, nunca prova da data do evento. Fonte sem data em claim temporal não decide sozinha por presunção de atualidade.

### Busca e fontes

RF-03: allowlist fixa e embarcada, 31 entradas; metadados identificam nome, tipo, especialidade e origem editorial. Mesmos critérios no proxy. HTTPS e filtro local obrigatórios antes de seleção; conferir URL final/canônica após redirecionamento. A pertença à allowlist não transforma qualquer texto em evidência.

RF-03.1 (v0.6): Wikipédia PT como fonte enciclopédica gratuita, pela rota `POST /wiki` do Worker (o IP do usuário não chega à Wikimedia; não consome crédito Tavily nem D1). Disparada em paralelo à primeira busca com as palavras de conteúdo da afirmação, até duas páginas, texto integral até 6.000 caracteres. `pt.wikipedia.org` fica fora da allowlist enviada à Tavily e tem tipo `encyclopedia` e origem editorial própria. Falha da Wikipédia só remove essa fonte; nunca vira busca vazia. Para afirmações atuais ou recentes, a enciclopédia vale como leitura parcial: reforça, não decide sozinha.

RF-04: solicitar até 20 candidatos, ranquear relevância/diversidade e ler até oito artigos, no máximo quatro downloads simultâneos. Consultas complementares sobrepõem leitura inicial quando há poucos candidatos/origens, conteúdo parcial ou período incerto. Reservar slots de leitura para complementos pendentes. Filtro de idioma português imposto no provedor. Até três chamadas ao provedor **incluindo retries**, compartilhadas entre consultas. Timeout do cliente de até 6 s (proxy permite 4,5 s upstream), sempre limitado pelo prazo compartilhado de 11 s. Um retry em busca para 5xx/timeout; nunca 401/429. Sem conexão, quota, rate-limit, falha de busca e busca vazia permanecem distintos.

### Extração e recuperação

RF-05: `ExtractedArticle` inclui parágrafos, título/autoria, URL final/canônica, publicação/atualização, procedência, parcialidade e atribuição original quando disponível. Ler JSON-LD antes de remover scripts. Extração Readability sobre SwiftSoup; corpo estruturado só quando público e a extração visível não bastar. `isAccessibleForFree=false` impede recuperar o corpo oculto como alternativa ao paywall. Snippet só como contexto parcial. Mínimo utilizável 200 caracteres; HTML limitado a 3 MiB após download. Até duas tentativas de quatro segundos, limitadas pelo orçamento de rede, para falhas transitórias de artigos. A extração não renderiza JavaScript.

RF-06: recuperação em janelas de até 128 tokens de embeddings, com contagem real e divisão adicional pelo orçamento WordPiece. Remover navegação/byline; ausência do recurso de marcação lexical PT não significa ausência de verbos. BM25 preserva nomes/números/unidades e combina ranking com embeddings por RRF. Para artigos longos, limitar cálculo semântico a 48 janelas lexicais e até 16 distribuídas. Top três janelas por artigo.

RF-06.1 (v0.6): premissas NLI são **frases**, não janelas. Candidatas: título e frases das janelas selecionadas e da janela seguinte a cada uma (onde costuma vir a refutação de um boato citado). Frase que começa por pronome/conector leva a anterior. Remover créditos de foto, chamadas de canal, migalhas e sufixos de site; descartar perguntas e alternativas de múltipla escolha. Ranquear por similaridade de embedding + BM25 e manter quatro por artigo. Sem embeddings por frase, cai na expansão por vizinhos da v0.5. Deduplicar contextos, calcular embedding da hipótese uma vez e reutilizar embeddings somente em memória.

RF-07: NLI BERTimbau-base do Spike 9, `.cpuOnly`, limite total 512 tokens, entradas `input_ids`, `attention_mask`, `token_type_ids`; ordem empírica `[entailment, neutral, contradiction]`. Devolver probabilidades completas, logits brutos e passagem. Aplicar temperatura da política compatível com a versão do modelo. Até 48 pares curtos por verificação (premissas de frase custam bem menos que janelas de 440 tokens). Probabilidades completas são preservadas por passagem. Um segundo NLI (MiniLMv2-L6, Spike 10) foi convertido e avaliado em ensemble no harness e **não foi adotado**: nenhuma combinação melhorou o acerto e todas aumentaram os erros de direção oposta.

### Decisão e apresentação

RF-08 (v0.6, evidência v3): votos só de evidências compatíveis com o período e não duplicadas; republicações agrupadas por URL canônica, shingles e atribuição original. O NLI sozinho lê "mesmo enquadramento, outro fato" como contradição; por isso cada passagem passa por `EvidenceScorer` antes de votar:

- **Apoio**: entailment ≥ 0,60 com margem ≥ 0,30, cobertura ≥ 50% dos termos da afirmação, todos os nomes (correspondência exata) e números presentes, e uma "âncora" (as duas palavras mais específicas que não são nomes, pela surpresa do unigrama XLM-R) ou entailment ≥ 0,97. Bloqueado quando a frase desmente, relata o que circula ("circula nas redes…") ou traz posição de ranking contra um superlativo.
- **Refutação**: contradição ≥ 0,70 com margem ≥ 0,40 e similaridade ≥ 0,45, em uma de três formas: mesmo sujeito (nomes, números e âncoras, com o sujeito antes do predicado) ou negação direta; mesmo predicado completo com outro sujeito nomeado ("Júpiter é o maior planeta" refuta "Marte…"); ou mesmos nomes com outro número. Negação explícita não hesitante multiplica por 1,3. Ranking contra superlativo refuta com 0,8.
- **Checagens**: título de agência que desmente ou nega a afirmação zera o apoio daquela fonte (o "apoio" é o boato citado); a citação do boato com os mesmos nomes vira refutação de 0,8.

Por fonte fica só o lado mais forte, salvo os dois ≥ 0,9. Por origem editorial fica o maior valor ponderado (enciclopédia/primária 1,0; agência de checagem 1,1; jornalismo 0,8; leitura parcial × 0,5). **DIVERGENTE exige um lado oposto real**: o lado mais fraco ≥ 0,9, ≥ 60% do mais forte e com ≥ 2 origens; ou um empate (≥ 85%) entre fontes completas. Caso contrário vence o lado dominante. Decidir exige soma ≥ 0,6, ao menos uma fonte completa no lado vencedor e, com origem única, ≥ 0,68. Snippet ou leitura parcial nunca decide sozinho. Neutros não votam. Afirmação histórica datada aceita matérias posteriores ou sem data: o elemento contestado é a própria data.

`evaluation/harness/evidence.py` é a implementação de referência; `EvidenceParityTests` confere o Swift contra ela em passagens reais.

Preservar cinco vereditos: CONFIRMADO, CONTRADITO, DIVERGENTE, SEM_INFORMACAO, NAO_ENCONTRADO. O último é reservado à busca concluída sem candidatos; fonte encontrada mas ilegível gera erro de leitura, e fontes relacionadas insuficientes geram SEM_INFORMACAO. Prazo/cota/falha parcial devem acompanhar o resultado disponível.

RF-09: exibir a afirmação selecionada, período, contagens encontrado/lido/usado/origens, procedência parcial, duplicações e limitações. Evidência textual com até 300 caracteres por trecho, atribuição e link Safari explícito. Sem porcentagem bruta de softmax apresentada como probabilidade de verdade. Texto explicativo determinístico; nunca geração de explicação por LLM. Aviso automatizado e falível fica fixo fora da rolagem.

RF-10: categoria e mensagem para sem rede, falha de busca, cota mensal, rate-limit, prazo, leitura incompleta e modelos indisponíveis. Cancelamento não é erro; interrompe rede e próximas inferências. IDs de execução impedem callbacks antigos de sobrescrever nova verificação.

## 3. Recursos, cota e privacidade

NF-01/02/03: embeddings <150 ms/chunk, NLI <1 s/par, verificação até 15 s em rede estável. Um relógio monotônico compartilha prazo; encerrar rede em 11 s e reservar o restante para análise. Core ML síncrono não pode ser interrompido no meio de uma chamada: verificar cancelamento/prazo antes de cada previsão e medir o limite no hardware real. Não prometer um limite rígido universal antes desse gate.

NF-04/05/06: rede concorrente, ML serial, main thread livre, app alvo <500 MB e pico RAM <1 GB. Referência histórica do modelo base: 383,7 MB e 66,5 ms aquecido no iPhone 16; não se aplica automaticamente à nova recuperação ou ao iPhone 13.

NF-07/08/09: Worker com D1 apenas para contadores, sem conteúdo persistente ou identificação de usuário. 800 buscas produção + 200 avaliação/mês, com reserva atômica por tentativa; 30 chamadas/minuto. Mês UTC deve coincidir com ciclo do provedor, reconciliando consumo anterior ao deploy. Chave Tavily só como secret; avaliação exige secret próprio fora do app. Conta deve continuar Free sem cobrança por excedente. D1 indisponível bloqueia busca. Nada é enviado a API de inferência.

NF-10/11: ATS padrão. Aviso de privacidade v3 (menciona a Wikipédia/Wikimedia) com reconhecimento explícito e apenas esse estado em UserDefaults; política offline acessível pelo toolbar. Explica até três consultas derivadas de partes da entrada, a consulta de palavras-chave à Wikipédia, processamento por Cloudflare/Tavily/Wikimedia e políticas externas. Manifesto declara UserDefaults e tempo monotônico para controle local. Conteúdo da consulta transmitido ao provedor é declarado para funcionalidade; não há tracking.

NF-12–15: apenas trechos curtos, atribuição e link; sem vínculo com veículos, contorno de paywall ou publicação integral de matérias. Política automatizada de robots.txt ainda não implementada; verificar permissões de acesso/termos dos veículos antes de distribuição. Distribuição assinada/Siri e URL pública de privacidade para loja permanecem itens externos.

## 4. Catálogo, avaliação e promoção

Catálogo embarcado aceita apenas entradas revisadas por dois revisores independentes, correspondência exata de afirmação normalizada/entidades/ano histórico e URL permitida. As duas entradas iniciais estão `pending_project_review` e não decidem resultados. Checagens antigas não são reaproveitadas como afirmações atuais.

`evaluation/` contém importador, validador/particionador, métricas, treino local retomável, exportação de logits, temperature scaling, seleção conjunta de política e gate de promoção. Estado inicial: 204 candidatos públicos não revisados; zero claims gold; 15 pares conhecidos de regressão. Em 24/11/2026 foi acrescentado `data/dev_claims.jsonl` (120 afirmações **dev, não-gold**, `pending_user_review`) e o harness offline `evaluation/harness/`, que roda os mesmos `.mlmodelc` sobre buscas e páginas cacheadas para medir e depurar regras sem gastar créditos. Esse conjunto orienta o desenvolvimento; não é teste cego nem métrica de promoção. Alvo 1.200 (600/300/300) exige curadoria humana real. Proibido inventar revisores, métricas ou preencher com paráfrases para declarar conclusão.

Isolar eventos/famílias/fontes entre partições; casos já conhecidos não são teste cego. Anotar trechos e conjuntos de evidências suficientes. Métricas: macro-F1 de vereditos, precisão de apoio/refutação com evidência correta, cobertura total e solucionável, recuperação, erros confiantes, latência/créditos, matriz e intervalos de confiança. Reportar falhas e ausências; nunca removê-las do denominador.

Metas experimentais: precisão direcional ≥90%, cobertura solucionável ≥70%. A seleção de política falha se não atender as duas. Baseline mantém temperatura 1 e piso 0,50, **sem calibração nova**; não ajustar para fazer os dois exemplos de câncer passarem.

Promoção exige teste cego congelado com 300 claims, melhora de veredito+evidência, perda de cobertura ≤3 pp, paridade tokenizador/Core ML e regressões críticas. Gates físicos: iPhone 13 e mais recente, preflight de disco, testes frios/repetidos, RAM <1 GB e p95 de verificação ≤15 s. Versionar pesos, tokenizadores, labels, política, manifesto de hashes e evidências juntos; manter conjunto anterior para rollback. Novas conversões devem trazer `model_version` no Core ML compatível com `EvidencePolicy` e `VerificationModelManifest` do bundle. O compilado legado recuperado não tinha esse metadado: sua identidade é fixada pelos hashes do manifesto e pelo identificador baseline.

## 5. Critérios de aceitação

- Entrada composta exige seleção/reformulação sem rede; seleção usa uma única hipótese em todas as etapas.
- Consultas ≤200 caracteres, chamadas ≤3 incluindo retries, artigos ≤8 (+2 da Wikipédia), downloads simultâneos ≤4 e pares ≤48.
- Atribuição, modalidade, negação, números/unidades/datas e ressalvas preservados; resultados de épocas diferentes não votam como se fossem contemporâneos.
- Snippet, preview e matéria republicada não produzem consenso independente artificial.
- Conflitos reais entre origens independentes são visíveis; uma passagem fora do tema, ou uma única origem discordante e fraca contra várias concordantes, não produz DIVERGENTE.
- Busca vazia, quota, rate-limit, falha de leitura e prazo permanecem distinguíveis.
- Cancelamento aborta tarefas pendentes; nenhum callback antigo publica resultado após nova execução.
- UI mostra contexto/limitações, trechos ≤300, links e aviso fixo; softmax não aparece como percentual de verdade.
- Worker força parâmetros de custo e ausência de respostas LLM; concorrência nunca ultrapassa os tetos; falha do contador impede upstream.
- Métricas recusam amostra incompleta, evidência sem trecho/URL, revisores ausentes e vazamento de partição.

## 6. Decisões reabertas e pendências

DT-13/21: proxy antes stateless agora guarda **somente contadores** em D1. DT-19/22: de consulta única/top cinco para plano adaptativo/top 20 candidatos e oito leituras. DT-23: snippets não equivalem ao corpo completo. DT-24/25: ranking híbrido e calibração somente com dados separados, mantendo o piso baseline. DT-26/29: consenso por evidência independente substitui maioria simples/maior score; na v0.6, "conflito válido" passa a exigir relevância por passagem e um lado oposto com força e origens comparáveis (RF-08). DT-27: retry por artigo passa a ser permitido dentro do prazo. DT-31/37: manifesto de versões e gates de promoção/rollback.

Pesos Core ML recuperados e verificados por hash; compilação bloqueia ausência/corrupção no fonte ou bundle. Pendências desta cópia: recuperar checkpoint PyTorch para novo treino; obter revisão independente e ampliar corpus; executar treino/calibração/teste cego e gates físicos. Código/instrumentação não significam metas de qualidade já atingidas.

## 7. Implantação verificada em 04/11/2026

Proxy v2 ativo na URL já usada pelo app, versão `b5c751d7-1d30-4353-aeca-825fa65f5b30` em 100% do tráfego. D1 criado e migrado, com orçamento reconciliado conservadoramente. Plano da própria chave do Worker confirmado como Researcher/1.000 créditos, sem consumo pay-as-you-go. Produção e avaliação foram testadas ao vivo: HTTP 200, um crédito por chamada e ausência de resposta gerada mesmo quando o cliente pediu advanced/LLM. Um GET administrativo autenticado permite conferir somente plano/uso agregado; não expõe a chave nem textos de consultas. Compatibilidade dos filtros legados country=brazil/general e time_range=year/news preservada. Testes locais do proxy: 11 aprovados.
