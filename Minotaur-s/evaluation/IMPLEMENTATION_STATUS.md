# Estado da implementação — 04/11/2026

O código do plano foi implementado no verificador, proxy e ferramentas offline. **As metas de acerto ainda não foram medidas. O proxy v2 e o D1 foram implantados e verificados ao vivo em 04/11/2026.** Não houve substituição dos pesos por um modelo sem validação.

## Entregas no código

- Seleção de uma afirmação, preservação de atribuição/negação, contexto temporal e consultas curtas. ViewModel impede callbacks antigos de sobrescrever uma nova execução.
- Orçamento compartilhado: três chamadas ao buscador incluindo retries, oito artigos/quatro downloads concorrentes, coleta de rede em 11 s, prazo de análise em 15 s e 24 pares NLI. Core ML síncrono é cooperativo entre chamadas; o limite real depende do gate físico.
- Tavily basic, respostas geradas e parâmetros automáticos desativados, filtro de idioma português e allowlist controlada pelo servidor e conferida no aparelho.
- Extração estruturada: JSON-LD, autoria/datas/URLs, metadados de acesso e previews. Snippet não tem a mesma autoridade do corpo completo; paywall declarado não é recuperado pelo JSON-LD.
- BM25 + embeddings, contagem real de tokens, contexto adjacente, embedding da hipótese reutilizado e cache apenas em memória. Modelos não são invocados simultaneamente sobre a mesma instância durante cancelamento/reinício.
- Probabilidades completas/logits por passagem, conflitos preservados e votação por evidência elegível/origem. Republicações reutilizam evidência; mudanças em nomes, quantidades, negação/modalidade impedem reutilizar uma classificação indevida.
- UI com afirmação/período, contagens, origem parcial/republicações, explicações determinísticas, links e aviso fixo. Percentuais brutos de softmax removidos da apresentação de fontes.
- Privacidade v2 com reconhecimento explícito, acesso permanente à política e manifesto próprio. Verificações não são persistidas.
- Worker com reserva D1 atômica de 800 produção/200 avaliação, proteção de rajadas e falha fechada. Migração, configuração, dependências travadas e testes locais disponíveis.
- Ferramentas para importar/revisar/particionar o corpus, medir evidência + veredito, ajustar BERTimbau localmente com retomada, exportar logits, calibrar, selecionar política e bloquear promoções sem os gates.

## Validação executada

Ambiente: Xcode 27.0 (27A266a), iPhone 17 Pro Simulator com iOS 26.5. Node 25.1.0; Python 3.15 para ferramentas sem dependências de ML. O treino documentado usa ambiente separado Python 3.11/PyTorch/Transformers compatíveis com os spikes.

| Verificação | Resultado |
|---|---|
| Suíte Swift do target de testes | **161 aprovados, zero falhas, 2 opt-in não executados nesta rodada** |
| Regressão focada final de busca/extração/pipeline | **42 aprovados, zero falhas** (subconjunto, não somar à suíte geral) |
| Ferramentas de avaliação, Python | **15 aprovados** |
| Proxy com SQLite real em memória, sem rede | **11 aprovados** (incluindo compatibilidade legada e administração protegida) |
| Build Debug para simulador e build dos produtos de teste | Aprovados |
| Modelos reais + busca, suíte focada com smoke online habilitado | **36 aprovados, zero falhas, zero skips** |
| Debug arm64 assinado para iPhone | **Aprovado**, modelos e manifesto verificados no bundle |
| Inferência/paridade/pipeline físico, iPhone 16 iOS 27.2 | **Aprovados**, incluindo busca real; 161 testes locais aprovados após corrigir uma instabilidade no teste do NLTagger |
| Automação da interface física | **Um teste aprovado, zero falhas e zero skips**, após habilitar a automação no iPhone; captura no registro físico |
| Bloqueio de assets ausentes | Verificado: validação falha se pesos estão ausentes |
| Build Release arm64, assinatura desativada | Aprovado |
| Worker `wrangler deploy --dry-run` | Aprovado; seguido de upload de versão e implantação autenticada |
| Migração D1 e implantação do proxy | Concluídas; versão b5c751d7 em 100% do tráfego |
| Buscas reais de produção/avaliação | HTTP 200 nas duas faixas, um crédito cada, sem resposta LLM |
| Tipos do binding D1 | Gerados com Wrangler 4.157.0 |
| Manifesto próprio | `plutil` aprovado; presente na raiz do bundle Release |
| Whitespace/diff | `git diff --check` aprovado |

Os dois opt-in não executados na suíte geral são o replay de corpus e o smoke online. O smoke online foi habilitado e passou na rodada focada de 36 testes. Nenhum teste dos modelos foi pulado: paridade com PyTorch, inferência, seis casos críticos e pipeline com modelos reais passaram. A rodada online exercitou busca real, leitura de artigos e NLI; é uma prova funcional pontual, não avaliação de precisão geral.

O cliente de busca interrompia a chamada em 4 s, abaixo dos 4,5 s permitidos ao upstream no Worker. Uma sonda URLSession levou 4,98 s com HTTP 200. O cliente agora permite até 6 s, limitado pelo orçamento global de coleta de 11 s. Foram adicionados logs apenas de código de transporte/status/schema, sem textos ou consultas.

O aviso foi inspecionado visualmente em modo claro, modo escuro e Dynamic Type de acessibilidade máximo. O texto é rolável, a ação permanece acessível, o reconhecimento fecha a apresentação e o toolbar reabre a política com “Fechar”. O campo e a ação de verificar voltaram a ficar disponíveis após restauração dos modelos. A seleção da frase foi exercitada pela ViewModel; o smoke online confirmou resultado com artigos lidos e pares NLI reais.

O simulador não tinha marcação lexical PT utilizável: o filtro antigo descartava parágrafos jornalísticos como “sem verbo”. Foi corrigido para tratar indisponibilidade como desconhecida e preservar o texto; as regressões de ruído/navegação continuam passando.

Artefatos principais nesta máquina:

- Suíte: `/Users/henriquelacerdasilveira/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-a2fc194a4b2f/result-bundles/test_sim_2026-11-04T20-41-02-716Z_pid79793_8d113fac.xcresult`.
- Foco final: `/Users/henriquelacerdasilveira/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-a2fc194a4b2f/result-bundles/test_sim_2026-11-04T20-46-14-077Z_pid79793_477cb852.xcresult`.
- Build Release: `/tmp/minotaurs-verifier-release.log`.

O bundle Debug arm64 assinado com os modelos ocupa cerca de 262 MiB. Isso não valida RAM/p95 no aparelho nem distribuição Release. O tempo de 17,63 s do teste online inclui preparação fria do pipeline; a UI prepara os modelos ao abrir a tela. Não confundir essa duração com p95 de verificação em hardware.

## Etapas que dependem de recursos externos

1. **Pesos restaurados; checkpoint pendente:** os dois `.mlmodelc` foram recuperados de uma instalação antiga do app. Hash NLI coincide com a evidência do Spike 9; tokenizadores idênticos. Backup independente dos caches e restauração com SHA-256 implementados. O checkpoint PyTorch para novos treinos continua ausente. Ver [assets e procedência](../scripts/MODEL_ASSETS.md).
2. **Curadoria real:** há 204 candidatos pendentes, zero claims gold, 15 pares antigos de regressão. A base de 1.200 com revisões independentes ainda precisa ser formada. Os dois registros iniciais do catálogo também estão pendentes e não decidem resultados.
3. **Treino/calibração:** ferramentas implementadas, mas nenhum novo treino/calibração foi executado. A política permanece baseline 0,50/temperatura 1, explicitamente não calibrada. Seu critério de fonte única não foi aumentado arbitrariamente. Não afirmar que 90%/70% foram atingidos.
4. **Hardware e teste cego:** executar inferência/paridade, avaliação congelada e gates em iPhone 13 físico e mais recente. Não houve medição nova de RAM/p95. Houve smoke funcional com busca real, sem custo pago e sem estimativa de precisão. Após conexão por USB e desbloqueio, o iPhone 16 recebeu o app. Testes reais dos modelos, paridade e busca completa passaram. A rodada após correção do teste instável teve 161 testes locais aprovados; a automação inicialmente ficou bloqueada pelo modo de automação do iOS. Após habilitação pelo usuário e correção do seletor do campo no teste, o fluxo completo de UI passou, com captura da tela de resultado. Ver [registro físico](PHYSICAL_AVAILABILITY_2026-11-04.md).
5. **Cloudflare — concluído após renovação da sessão:** D1 criado/migrado e proxy v2 implantado. Plano Researcher/1.000 créditos confirmado com a secret do próprio Worker. Orçamento inicial incluiu uma busca pré-migração conservadoramente. As duas faixas responderam HTTP 200 e um crédito cada, sem respostas geradas; o contador passou a produção 2/avaliação 1. Administração sem credencial respondeu 404. A secret Tavily foi preservada e a de avaliação fica em arquivo privado fora do Git. Nenhum plano pago foi habilitado.
6. **Distribuição:** Debug assinado compilou com a equipe existente; a validação Release/Siri, publicação da política para App Store e política automatizada de robots.txt continuam pendentes. Nenhuma capacidade foi removida.

O fluxo reproduzível e os formatos de dados estão em [README da avaliação](README.md). Os dados da implantação concluída estão em [README do proxy](../proxy/README.md).


## Artefatos da correção de disponibilidade (04/11/2026)

- Suíte geral: `test_sim_2026-11-04T22-30-45-886Z_pid79793_feb8b8b7.xcresult` (161 aprovados, 2 opt-in).
- Modelos + rede real: `test_sim_2026-11-04T22-29-12-283Z_pid79793_8adc4e87.xcresult` (36 aprovados, zero skips).
- Ambos em `~/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-a2fc194a4b2f/result-bundles/`.
- Build físico assinado: `/tmp/minotaurs-device-derived/Build/Products/Debug-iphoneos/Minotaur-s.app`.
- Log do build: `/tmp/minotaurs-device-build.log`.

Uma sonda sintética adicional, combinando e reordenando frases sobre Terra plana, produziu apoio incorreto; não foi promovida a gold nem usada para ajustar limiares. A regressão do pipeline usa a passagem pública exata já coberta pelas sondas críticas. A recuperação dos pesos resolve disponibilidade, sem eliminar as limitações semânticas conhecidas de citação/refutação do modelo baseline.


A validação manual final pela tela (simulador, busca real) terminou com 37 artigos encontrados, oito lidos, cinco usados e cinco origens. Exibiu “Fontes divergentes”, com aviso de prazo/trechos parciais. Isso confirma execução e apresentação, não correção semântica para essa afirmação; o modelo baseline ainda produziu apoio indevido em parte das passagens sobre Terra plana. O bloqueio inicial CoreDevice 4016 foi resolvido conectando e desbloqueando o aparelho. A instalação e a execução física foram confirmadas posteriormente; o registro físico acima contém os resultados e a limitação da automação de UI.


Confirmação física final: teste `Minotaur_sUITests/testVerifierWithBundledModelsAndLiveSearch()` aprovado no iPhone 16, com rede e modelos reais; um aprovado, zero falhas/skips. Artefato `/tmp/minotaurs-physical-ui-run2.xcresult`. A versão final sem plugins de testes foi reinstalada e aberta, e o runner auxiliar foi removido. Esse teste valida execução/navegação, sem atestar precisão geral ou resolver as falhas semânticas conhecidas.
