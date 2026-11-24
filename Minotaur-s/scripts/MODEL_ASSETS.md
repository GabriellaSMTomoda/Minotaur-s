# Assets locais do verificador

Em 04/11/2026, os dois modelos ausentes foram recuperados da instalação de 10/08/2026 do app no simulador. São ML Programs compilados (`.mlmodelc`), com entradas dinâmicas de 1–512 tokens, disponibilidade iOS 16+ e execução CPU. Não houve treinamento nem troca de arquitetura.

| Asset | SHA-256 de `weights/weight.bin` |
|---|---|
| NLI, BERTimbau-base PLUE/MNLI Spike 9 | `8153a2b3aace8be194a1dd5577191a9f24980947f6d382935c26bbccdd5e2ac2` |
| Embeddings, MiniLM multilíngue Spike 2 | `fc85a3b3ab2394d829c9ed4fe70ec23a58d4b2e83be6101e5f8b08dee756423d` |

O hash NLI coincide com o gate físico registrado no Spike 9. Os cinco arquivos de tokenização/labels são idênticos aos da instalação recuperada. A versão legada não tinha `model_version` no metadado Core ML; a identidade é fixada pelo manifesto de hashes e pela política baseline `bertimbau-base-plue-spike9`. Novas conversões devem incluir o metadado.

Os `weight.bin` (109 MB e 118 MB) excedem o limite de 100 MB por arquivo do GitHub, então são versionados **fatiados em partes de 45 MiB** em `model-parts/` (`NLI.weight.bin.part00..02`, `Embeddings.weight.bin.part00..02`). Os demais arquivos dos `.mlmodelc` (pequenos) ficam versionados em `Minotaur-s/Resources/Models/`; só o `weight.bin` remontado é ignorado pelo Git. Há também uma cópia independente dos caches do simulador, usada de preferência se existir, em:

`~/Library/Application Support/Minotaur-s/models/bertimbau-base-plue-spike9/`

Para restaurar, dentro da pasta que contém o `.xcodeproj`:

```sh
bash scripts/sync-models.sh
```

Para usar uma cópia do mesmo conjunto validado em outro local:

```sh
MINOTAURS_MODEL_BACKUP='/caminho/para/o/conjunto' bash scripts/sync-models.sh
```

O script verifica os arquivos em staging antes de substituir os modelos (e sai sem mexer em nada se já estiver íntegro). Não baixa pesos, não treina nem altera o manifesto para aceitar arquivos diferentes. Em outra máquina basta `git pull`: sem backup local, o script remonta os pesos de `model-parts/` e confere o SHA-256 do manifesto. A fase de build `Restore model weights` roda esse script sozinha quando falta algum `weight.bin`, então a primeira build após o clone funciona sem passo manual. Se alterar os pesos, regenere as partes com `split -b 45m -d -a 2 <weight.bin> model-parts/<Modelo>.weight.bin.part` e atualize o manifesto.

O target do app tem uma fase obrigatória `Verify local inference assets`, em Debug e Release. Ela confere SHA-256 dos 15 arquivos do modelo/tokenizadores no projeto e no bundle final, incluindo o manifesto. Arquivo ausente ou diferente faz o build falhar. Nunca desabilitar essa fase para contornar erro de empacotamento.

`MLServicesTests` não pula mais inferência por falta dos modelos. Além da paridade PyTorch e dos seis casos críticos, há uma regressão do pipeline com modelos reais e rede controlada. O smoke de rede completo é opt-in por `VERIFIER_LIVE_SMOKE=1`; não registra consultas do usuário e usa uma afirmação pública fixa.

O checkpoint PyTorch original não foi recuperado. Os compilados permitem inferência; carregamento, paridade, pipeline com busca real e fluxo pela interface foram confirmados em iPhone 16 por USB em 04/11/2026. Não substituem o checkpoint para novos treinos. Precisão geral, novos ajustes e metas de RAM/p95 em iPhone 13 continuam sujeitos aos gates de avaliação.
