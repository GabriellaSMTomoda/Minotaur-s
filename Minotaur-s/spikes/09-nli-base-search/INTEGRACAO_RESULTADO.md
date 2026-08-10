# Integração do BERTimbau-base NLI — resultado

Data: 2026-08-05  
Custo financeiro externo: **R$ 0**

## Resultado executivo

O checkpoint selecionado na Etapa 3 do Spike 9 foi integrado ao caminho NLI do app sem
alteração de UI, persistência ou contrato de veredito. A integração funcional está **PASS**:

- build e lançamento no simulador: PASS;
- suíte completa: **145/145** testes PASS;
- testes do NLI integrado no iPhone físico: **28/28** PASS;
- lançamento normal do app no iPhone: PASS;
- paridade WordPiece/Hugging Face e PyTorch/Core ML: PASS;
- seis casos críticos de Terra plana e vacina: PASS (nenhum `entailment`).

O build Release arm64 sem assinatura passou. O build Release **assinado** está bloqueado por
configuração externa: o perfil de provisioning disponível não inclui a capability Siri, e o
Xcode não possui uma conta capaz de atualizar o perfil. Nenhuma capability ou entitlement foi
removida para contornar o bloqueio.

`spec.md` e `CLAUDE.md` não foram alterados nesta integração. As mudanças de especificação
propostas continuam documentadas em `PLANO_INTEGRACAO_SDD.md`, aguardando autorização que não
conflite com a regra operacional vigente do `CLAUDE.md`.

## Implementação

### Runtime

- `BERTTokenizer.swift`: tokenizador WordPiece offline dedicado ao NLI;
- formato do par: `[CLS] premissa [SEP] hipótese [SEP]`;
- entradas Core ML: `input_ids`, `attention_mask` e `token_type_ids`;
- limite: 512 tokens, truncando a premissa antes da hipótese;
- `NLIService`: BERTimbau-base PLUE/MNLI INT8, compute FP16, `.cpuOnly`;
- `XLMRTokenizer`: permanece exclusivo do modelo de embeddings;
- orçamento do `VerificationPipeline`: três tokens especiais BERT, mantendo a RF-06.2.

Não houve mudança nos limiares, agregação por artigo, votação, RF/NF ou itens `[EM ABERTO]`.

### Assets

O export é reproduzível por `export_app_assets.py`. O script bloqueia a exportação se:

- `training_summary.json` não estiver `COMPLETE`;
- `checkpoint-best` não for o checkpoint selecionado por PLUE;
- a ordem índice→rótulo não estiver confirmada empiricamente.

| Artefato | Valor |
|---|---:|
| Modelo Core ML no bundle | `bertimbau_base_plue_dynamic512_int8.mlpackage` |
| Parâmetros | 108.925.443 |
| Package NLI | 109.493.216 bytes |
| `weight.bin` SHA-256 | `8153a2b3aace8be194a1dd5577191a9f24980947f6d382935c26bbccdd5e2ac2` |
| Tokenizador WordPiece | 678.041 bytes |
| Tokenizador SHA-256 | `a798785e1a91c93a634848b30705cae16b7a228303a899aca9997d77b6a53540` |
| Labels SHA-256 | `a0b2a0bd55032dd53ff755fe74032eaa3ee051a4afab303926aba7d0cc9cbdcf` |
| Ordem empírica | `[entailment, neutral, contradiction]` |

O conjunto `NLI.mlpackage + NLITokenizer.json` passou de 125.041.479 para 110.171.257
bytes: redução de **14.870.222 bytes** (aproximadamente 14,18 MiB). O modelo cresceu cerca de
1,53 MB, mas o WordPiece substituiu o tokenizador XLM-R de 17,08 MB.

O build Release arm64 sem assinatura mede 274.678.352 bytes de arquivos (262 MiB em disco).
Isso é tamanho descompactado do `.app`, não estimativa de download da App Store; portanto o
item NF-05 continua aberto.

## Validação

### Simulador

Ambiente: iPhone 17 Simulator, iOS 26.5.

1. Build + launch: PASS em 46,3 s, sem warning.
2. Testes focados de tokenizer, ML, pipeline e filtro: 55/55 PASS.
3. Duas primeiras suítes completas: 144 PASS e um falso `WaitTimeout` reproduzível.
4. O teste falho isolado: 11/11 PASS; o caso completou em 49 ms.
5. Causa: o helper usava cinco segundos de relógio de parede enquanto a preparação paralela
   dos modelos suspendia a task por 13–15 s.
6. Correção: contar 2.500 ciclos de espera efetivamente executados (2 ms cada). O teto lógico
   normal continua em aproximadamente cinco segundos.
7. Suíte completa final: **145 PASS, 0 FAIL, 0 SKIP**, 68,6 s.

Resultado final:

`~/Library/Developer/XcodeBuildMCP/workspaces/Minotaur-s-4fa58c3d372e/result-bundles/test_sim_2026-08-06T02-57-32-603Z_pid53886_f71442c0.xcresult`

### iPhone físico

| Campo | Valor |
|---|---:|
| Aparelho | iPhone 16 (`iPhone17,3`) |
| iOS | 26.3.1 (`23D771330a`) |
| Arquitetura | arm64 |
| Espaço livre no preflight | **2.636 MB** |
| Testes selecionados | 28 |
| PASS / FAIL / SKIP | **28 / 0 / 0** |

O primeiro comando físico foi bloqueado antes de instalar porque os targets de teste não
tinham equipe de assinatura explícita. A evidência foi preservada. A segunda tentativa usou a
mesma equipe do gate físico do Spike 9 (`DEVELOPMENT_TEAM=2DK23BZ7KB`) e passou sem alterar o
projeto.

Resultado físico:

`build/integration/device-nli-tests-attempt2.xcresult`

O conjunto físico inclui:

- paridade dos ids, máscara e segmentos BERT contra a fixture Hugging Face;
- paridade do rótulo e confiança Core ML contra PyTorch;
- modelos de embeddings e NLI carregados do bundle;
- todos os seis casos críticos de Terra plana e vacina;
- truncagem a 512 tokens e preservação da hipótese.

Após os testes, `com.julia.fatoufarsa2025` foi lançado normalmente no aparelho. O app não foi
desinstalado, pois isso apagaria seu container de dados. O harness descartável do Spike 9 foi
desinstalado.

## Build Release e bloqueio externo

PASS:

```bash
xcodebuild build -quiet \
  -project Minotaur-s.xcodeproj -scheme Minotaur-s -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/minotaur-integration-release-unsigned-dd \
  CODE_SIGNING_ALLOWED=NO
```

FAIL antes da compilação assinada:

- `No Accounts: Add a new account in Accounts settings.`
- `Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the Siri capability.`
- perfil sem o entitlement `com.apple.developer.siri`.

Para distribuir ou validar um build Release assinado, é necessário entrar no Xcode com a conta
Apple Developer correta e regenerar/baixar um perfil que contenha Siri. Isso é configuração de
conta externa; não deve ser resolvido removendo a capability sem decisão de produto.

## Reproduzir

```bash
# Exporta tokenizer, labels empíricos e fixture a partir do checkpoint selecionado
spikes/02-coreml-latencia/.venv/bin/python \
  spikes/09-nli-base-search/export_app_assets.py

# Copia embeddings e o NLI selecionado para os resources ignorados pelo Git
./scripts/sync-models.sh

# Teste físico focado (requer aparelho, perfil e equipe válidos)
xcodebuild test -quiet \
  -project Minotaur-s.xcodeproj -scheme Minotaur-s -configuration Debug \
  -destination 'platform=iOS,id=EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8' \
  -derivedDataPath /private/tmp/minotaur-integration-device-dd \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=2DK23BZ7KB CODE_SIGN_STYLE=Automatic \
  -only-testing:'Minotaur-sTests/TokenizerParityTests' \
  -only-testing:'Minotaur-sTests/MLServicesTests'
```

## Rollback

Não há migração de dados. O rollback é puramente de código e assets:

1. restaurar `NLIService` e o orçamento de par para XLM-R/L6;
2. restaurar os três assets NLI anteriores;
3. apontar `scripts/sync-models.sh` novamente para o artefato L6 do Spike 2c;
4. remover `BERTTokenizer.swift`;
5. rodar a suíte completa e o gate físico antes da entrega.

Nenhum rollback deve alterar o modelo de embeddings, limiares, dados do usuário ou os artefatos
de evidência do Spike 9.

## Limitações que permanecem

- o NLI compara afirmação e evidência; ele não conhece eventos recentes por memória própria;
- notícias como “Lula morreu hoje” dependem de busca/extração trazer fontes atuais e confiáveis;
- o grupo de claims curtos foi estável em 2/3 famílias no Spike 9;
- há erros adversariais residuais (13/15, não 15/15);
- drift de linguagem, fontes e padrões de desinformação exige monitoramento contínuo;
- o build Release assinado depende da correção externa do provisioning de Siri.

O plano de monitoramento, rollout gradual e rollback de produto está em
`PLANO_INTEGRACAO_SDD.md`.
