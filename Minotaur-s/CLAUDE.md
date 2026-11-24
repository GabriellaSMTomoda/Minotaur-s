# Instruções para agentes de código neste projeto

Estado de 24/11/2026. Para o Verificador, ler `spec.md` v0.6 por inteiro. A v0.6 trocou a agregação "qualquer voto" (que dava DIVERGENTE até para fatos triviais) pela política de evidência v3 e acrescentou a Wikipédia PT; os contratos antigos de consulta única/maioria simples/stateless/"qualquer contradição é conflito" não são os requisitos atuais.

## Escopo

Alterações apenas no Verificador, seus testes/assets, proxy e ferramentas de avaliação. Preservar quiz, Pergunta do Dia, Siri/Atalhos, bundle ID, equipe e `VerificadorView()` instanciável sem argumentos. Não concentrar lógica na View. `VerificationPipeline` é o único coordenador; dependências por protocolos e inferência fora da main thread via runner actor.

Sem FoundationModels, API de LLM, scraping de buscador, negação automática, histórico de verificações ou logs de consultas. Não contornar paywalls. Vereditos sempre referenciados às fontes; trechos de até 300 caracteres com link e aviso fixo visível.

## Arquitetura vigente

ClaimAnalyzer → plano de até três consultas (+ Wikipédia PT em paralelo) → busca/leitura sobrepostas → artigo com metadados → janelas tokenizadas → BM25/embeddings → frases-premissa → NLI → `EvidenceScorer` → `VerdictAggregator` → resultado.

- Uma afirmação por vez; ambiguidades dependentes exigem reformulação.
- Três chamadas Tavily por verificação incluindo retries; `basic`, sem respostas LLM, até 20 candidatos por consulta.
- Até oito artigos, quatro downloads concorrentes, janela de rede de 11 s em orçamento total de 15 s, relógio monotônico.
- Até 48 pares NLI curtos (frases, não janelas). Verificar cancelamento/prazo entre inferências: Core ML síncrono não é interrompível no meio de uma previsão.
- Wikipédia PT só pela rota `POST /wiki` do Worker, nunca direto do app; não consome Tavily/D1; `pt.wikipedia.org` fica fora da allowlist Tavily. Para afirmações atuais/recentes ela não decide sozinha.
- Embedding da hipótese uma vez; cache só em memória da sessão. Contar tokens reais dos dois tokenizadores, reservando hipótese no limite NLI de 512.
- Snippet/preview e período incompatível/incerto não decidem. Não transformar falha de leitura em busca vazia.
- Preservar probabilidades/passagens contrárias. Republicações não são consenso independente. Uma passagem só vota depois dos portões de relevância de `EvidenceScorer` (nomes exatos, números, âncoras, forma da refutação). DIVERGENTE exige lado oposto real: ≥ 2 origens com força comparável, ou empate entre fontes completas.
- **Regras de evidência têm duas cópias que precisam ficar iguais**: `evaluation/harness/evidence.py` (referência) e `EvidenceScorer.swift`/`VerdictAggregator.swift`. Mudou uma, mude a outra, regenere `EvidenceParityFixtures.swift` com `export_parity_fixture.py` e rode `EvidenceParityTests`.
- Se marcação lexical PT estiver indisponível, não inferir que todo texto está sem verbo.
- Política baseline 0,50/temperatura 1, não calibrada. Ajustes exigem corpus separado e gate; não mascarar os erros de câncer conhecidos.

## Modelos e assets

Modelo atual continua BERTimbau-base do Spike 9 (três classes), INT8/FP16, CPU, WordPiece e `token_type_ids`; ordem empírica entailment/neutral/contradiction. Embeddings usam XLM-R; a tabela `EmbeddingsPieceScores.bin` (Float16, gerada por `scripts/export-piece-scores.py`) dá a raridade das palavras para as âncoras. Não reintroduzir BERTimbau-large: falhou RAM/latência no Spike 8. O MiniLMv2-L6 do Spike 10 foi avaliado em ensemble e rejeitado (não melhorou o dev e aumentou erros de direção); não embarcar sem nova evidência. O retreino `train_nli_v2.py`/`evaluation/nli_v2/` está pronto mas não foi executado.

Pesos versionados fatiados (partes de 45 MiB em `model-parts/`, por causa do limite de 100 MB do GitHub) e remontados por `scripts/sync-models.sh`, que a fase de build `Restore model weights` executa quando faltam; recuperados originalmente como `.mlmodelc` portáveis de uma instalação do app de 10/08/2026. Hash NLI idêntico ao gate do Spike 9; tokenizadores idênticos. Backup em `~/Library/Application Support/Minotaur-s/models/bertimbau-base-plue-spike9`; `scripts/sync-models.sh` restaura e verifica SHA-256 antes de substituir. Build phase obrigatório verifica fonte e bundle contra `VerificationModelManifest.json`; não entregar build sem pesos. Os 14 testes de inferência deixaram de ser condicionais. Em 04/11/2026, instalação, carregamento, paridade e pipeline com busca real passaram em iPhone 16 físico/iOS 27.2. Após o usuário habilitar automação de UI, o teste completo pela interface também passou no aparelho: um aprovado, zero falhas/skips, com screenshot do resultado. Isso valida execução, não precisão geral. Ver `evaluation/PHYSICAL_AVAILABILITY_2026-11-04.md`. Replay público e smoke de rede são opt-in. O checkpoint PyTorch para novo treino continua ausente. Não promover uma base sem cabeça treinada.

Ao mudar modelo: validar arquitetura/conversão em hardware, paridade de inputs/logits, RAM/latência e adversariais reais. Metadado Core ML `model_version`, `VerificationModelManifest.json` e `EvidencePolicy.json` precisam combinar. Manter conjunto anterior de código/assets para rollback.

## Avaliação

`evaluation/README.md` define o fluxo. Para medir mudanças use a skill `avaliar-verificador` (harness offline sobre `data/dev_claims.jsonl`, 120 afirmações **dev, não-gold**, revisão do usuário pendente) e o agente `analista-erros-verificador` para classificar erros. Coletas com rede gastam a faixa de avaliação (200/mês); reanálises não. Existem 204 candidatos públicos sem revisão e 15 regressões conhecidas; a base de 1.200 revisada ainda não existe. Não inventar revisores, rótulos gold, treino ou métricas. As duas entradas do catálogo também exigem duas revisões independentes antes de habilitar.

Treino/calibração/teste por evento/família/fonte (600/300/300); teste cego fora do treino. Acerto exige veredito e evidência corretos; publicar cobertura junto de precisão, com denominadores e intervalos. Metas 90%/70% não são resultados. Promoção exige melhora geral, regressões críticas, paridade e iPhone 13 físico + mais recente com preflight de disco e testes frios/repetidos.

## Proxy e privacidade

Chave Tavily só no secret do Worker, nunca app/config versionada/fixtures/logs. Worker controla modos, domínios e tamanho. D1 guarda apenas contadores: 800 produção + 200 avaliação/mês, com reserva atômica por tentativa e teto de rajada. D1 indisponível bloqueia upstream. Avaliação exige secret separado `EVALUATION_KEY`; não embarcar no app.

Proxy v2 implantado em 04/11/2026: versão `b5c751d7-1d30-4353-aeca-825fa65f5b30`, 100% do tráfego. D1 `minotaurs-search-budget`, migração aplicada. A própria chave do Worker confirmou plano Tavily Researcher, franquia 1.000 e sem consumo pay-as-you-go. O contador inicial considerou uma busca pré-migração conservadoramente. Preservar os contadores; não zerá-los no mês. O endpoint administrativo GET `/_admin/usage` exige `X-Evaluation-Key` e devolve apenas plano/contadores, sem consultar notícias ou consumir o orçamento de buscas. A credencial fica fora do Git, em `~/Library/Application Support/Minotaur-s/credentials/evaluation-key`, modo 0600. Antes de qualquer implantação futura, reconciliar consumo e preservar as duas secrets existentes. A rota `/wiki` (24/11/2026) está no código e em `npm test`, **ainda não implantada**: implantar só com confirmação do usuário. Até lá o app trata o 404 como "sem enciclopédia". Medida no dev em 24/11/2026: artigo inteiro 73/120 com 9 DIVERGENTE; introdução de 1.200 caracteres 75/120, mas "A Terra é plana" virou DIVERGENTE. Não promover sem introdução apenas, marcadores de descrédito enciclopédico e nova medição sem regressão crítica (`IMPLEMENTATION_STATUS.md`). A Wikimedia limita fortemente User-Agents sem contato (o harness recebeu 429 com Retry-After de 25 s); antes de implantar, o usuário decide qual contato do projeto pôr em `WIKI_USER_AGENT`; não usar e-mail pessoal sem pedido explícito.

Aviso de privacidade v3 (Wikipédia/Wikimedia) reconhecido explicitamente e política offline permanente. Só o reconhecimento fica em UserDefaults; resultado/texto não são persistidos. Fontes e provedor têm suas próprias políticas. Preservar manifesto de privacidade e declarar novas APIs requeridas quando necessário.

## Projeto e validação

Usar `Minotaur-s.xcodeproj` versionado. **Não executar `xcodegen generate`** sem antes reconciliar `project.yml`; isso perderia dependências/configurações válidas. Swift 5, iOS 17+, SwiftSoup e swift-transformers/Tokenizers. Grupos sincronizados incluem automaticamente novos Swift/assets nas pastas da feature.

Testes Swift Testing em `Minotaur-sTests/Verificador`, testes Worker via `npm test`, testes offline via `python3 -m unittest discover -s evaluation`. Não usar stubs de UI como prova de precisão. Registrar skips, ambiente, xcresult e limitações em `evaluation/IMPLEMENTATION_STATUS.md`.

Debug assinado compilou em 04/11/2026, preservando a equipe e as capacidades; validação de distribuição Release/Siri continua pendente para a equipe `2DK23BZ7KB` para `com.julia.fatoufarsa2025`; não remover capacidade/entitlement para contornar. URL pública de privacidade, política robots.txt e medições de distribuição ainda exigem validação externa. Manter README/spec/este arquivo coerentes com o código e com aquilo que foi de fato medido.
