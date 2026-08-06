# Plano SDD proposto — integrar BERTimbau-base + PLUE

## Estado e limite desta proposta

O Spike 9 passou os gates técnicos: seleção PLUE, ordem empírica de rótulos,
avaliação A/B/C, conversão, paridade e device físico. Este documento **não é
autorização para integrar**. Não altera `spec.md`, não resolve itens em aberto
e não reabre nenhuma DT. A integração só começa após OK explícito do usuário.

O candidato é o checkpoint BERTimbau-base de 3 classes treinado em PLUE/MNLI,
convertido para MLProgram INT8/FP16 com `RangeDim(1...512)`. No iPhone 16
físico, `.cpuOnly`, ele marcou 13/15 pares reais, 6/6 casos críticos, 383,7 MB
residentes máximos e 66,5 ms aquecido a 512 tokens. A limitação conhecida é
estabilidade de claims curtos: 2/3 famílias, contra 3/3 no BERTimbau-large.

## Alterações de requisitos e decisões a propor ao usuário

Somente após aprovação, atualizar a especificação para:

1. revisar DT-18 e a descrição de 3.2 para o novo artefato BERTimbau-base +
   PLUE/MNLI, WordPiece e terceira entrada `token_type_ids`;
2. atualizar NF-05 com tamanho medido do archive do app integrado, não o
   tamanho isolado do `.mlpackage`;
3. registrar o resultado do item 27 como resolvido pela rota DT-35/DT-36, se o
   usuário entender que os gates e a limitação de claims curtos são aceitáveis;
4. manter RF-06.2 em 512: o Spike mediu viabilidade nesse teto e não autoriza
   reduzi-lo;
5. não resolver o item 26 nem criar margem/threshold novo. Os dois erros de
   câncer e a regressão de claim curto devem continuar declarados como risco.

## Arquivos do app que a integração afetaria

| Área | Arquivos prováveis | Mudança proposta |
|---|---|---|
| Inferência NLI | `Minotaur-s/Services/Verificador/NLIService.swift` | Carregar o MLProgram BERT e fornecer as três entradas, inclusive `token_type_ids`. Preservar `.cpuOnly`. |
| Tokenização NLI | `Minotaur-s/Services/Verificador/XLMRTokenizer.swift` ou um novo tokenizer WordPiece dedicado | Não reutilizar a montagem XLM-R para BERT. Codificar `[CLS] premissa [SEP] hipótese [SEP]`, atenção e segmentos 0/1, limitado a 512. |
| Recursos | `Minotaur-s/Resources/Tokenizers/NLITokenizer.json`, `NLITokenizerConfig.json`, `NLILabels.json` | Substituir pelos recursos produzidos do checkpoint selecionado e fixar a ordem empírica 0 entailment / 1 neutral / 2 contradiction. |
| Modelo embarcado | `Minotaur-s/Resources/Models/NLI.mlpackage` via `scripts/sync-models.sh` | Sincronizar apenas o `.mlpackage` selecionado, sem embarcar o checkpoint de treino ou modelos antigos desnecessariamente. |
| Fixtures/testes | `Minotaur-sTests/Verificador/NLIReferenceFixture.swift`, `TokenizerParityTests.swift`, `MLServicesTests.swift` | Trocar fixtures pela saída do novo checkpoint e cobrir a terceira entrada. |
| Build | `scripts/sync-models.sh` | Mudar a origem do NLI para o artefato versionado pelo Spike 9 e documentar hash/verificação. |

`VerificationPipeline.swift`, `TextChunker.swift`, agregação, UI e a allowlist
não devem mudar por esta troca, salvo um teste provar necessidade concreta.

## Migração do modelo

1. Validar SHA-256 do `model.safetensors`, `weight.bin` e tokenizer contra os
   artefatos do Spike 9.
2. Gerar, a partir do checkpoint selecionado, o pacote de recursos WordPiece e
   uma fixture com ids, máscara, segmentos, logits e argmax para as sondas.
3. Copiar o MLProgram para o bundle pelo script de sincronização, mantendo o
   nome de recurso esperado por `NLIService` ou alterando-o de forma atômica.
4. Trocar a implementação do tokenizer de NLI e adicionar `token_type_ids` ao
   `MLDictionaryFeatureProvider`. Não usar zeros como atalho: o Spike 8 já
   demonstrou que isso altera logits silenciosamente.
5. Remover o L6 do bundle final somente depois de todos os testes e do archive
   de release passarem. O repositório e a release anterior continuam sendo o
   rollback do artefato.

## Estratégia de testes

Unitários:

- paridade WordPiece Swift ↔ fixture Python para premissa, hipótese, acentos,
  truncamento e `token_type_ids`;
- `NLIService` devolve o argmax e probabilidades esperados do fixture;
- `NLILabels.json` corresponde à ordem empírica, não ao `id2label` remoto;
- ausência/shape errado de qualquer uma das três entradas vira
  `modelLoadFailed`, nunca fallback silencioso;
- os testes existentes de `VerificationPipeline` e `VerdictAggregator` continuam
  verdes sem alterar as regras DT-24/25/26/29/33.

Integração:

- `loadFromBundle()` encontra modelo, tokenizer e labels no app arquivado;
- pipeline real com as seis premissas de Terra plana/vacina produz
  `contradiction` antes da agregação;
- os dois pares residuais de câncer continuam explícitos como `neutral`
  esperados no conjunto de regressão, sem mascará-los por threshold;
- smoke test de erro de modelo ausente mantém a mensagem de RF-10.3.

Device:

- iPhone físico, `.cpuOnly`, com preflight de pelo menos 800 MB e número livre
  registrado;
- paridade dos três probes Mac ↔ iPhone, RAM com dois modelos vivos e carga
  180+15, e latência fria/aquecida 77/128/256/384/512;
- archive/instalação do app real para medir tamanho final e um fluxo completo de
  busca → fonte → NLI, sem usar o simulador como evidência de RAM.

## Rollback

O rollback preferível é de release: manter a versão publicada anterior e o hash
do L6 preservados, revertendo o conjunto de assets e o tokenizer numa correção
de app se aparecer regressão grave. Um seletor remoto de modelo não é proposto:
ele exigiria telemetria/configuração remota fora da especificação atual. Se for
necessário rollback instantâneo, o usuário deve primeiro aprovar essa expansão
de produto e privacidade.

## Impacto de tamanho

O novo NLI mede 104,42 MiB, contra aproximadamente 103 MB do L6. O WordPiece
do BERTimbau (~2 MB esperado) é muito menor que o tokenizer XLM-R atual (~17
MB), então a estimativa líquida é redução próxima de 14 MB no conjunto NLI +
tokenizer. Isso é estimativa: a decisão NF-05 deve usar o `.ipa`/archive real,
pois símbolos, recursos e compilação Core ML variam. O harness físico mediu
219 MB com embeddings + novo NLI, mas não é o tamanho do app de produção.

## Risco para notícias extremamente recentes

O fine-tune não torna o modelo atualizado sobre fatos. Ele classifica a relação
entre a afirmação e o texto recuperado. Para “Lula morreu hoje”, a resposta
continua dependente de a busca encontrar fontes recentes e confiáveis: uma
notícia verdadeira recém-publicada pode ficar `SEM_INFORMAÇÃO` antes da
cobertura; uma falsa pode só ser `CONTRADITO` se a fonte mencionar a negação.
O plano de integração deve preservar a linguagem “as fontes encontradas” e não
afirmar verdade absoluta, além de testar consultas de breaking news e ausência
de cobertura.

## Monitoramento de qualidade em produção — proposta, não implementação

A especificação atual exclui analytics e persistência. Sem nova decisão, o
monitoramento viável é curadoria periódica fora do app: repetir o conjunto A/B/C
e um conjunto rotativo de notícias recentes públicas antes de releases.

Se o usuário quiser monitoramento em produção, propor separadamente uma opção
explícita e revisável de feedback voluntário, sem enviar a afirmação por padrão,
ou telemetria agregada e opt-in. Isso exige requisitos de privacidade, retenção,
consentimento, segurança e revisão de “Fora de Escopo”; não deve ser introduzido
durante a troca de modelo.

## Critério para começar

Antes de mudar qualquer arquivo do app, o usuário deve aprovar:

1. substituir o NLI atual pelo BERTimbau-base selecionado;
2. aceitar a limitação 2/3 de estabilidade de claims curtos, com os testes de
   regressão propostos;
3. atualizar `spec.md` e DT-18 sob controle do usuário;
4. executar o plano de testes e de rollback acima.
