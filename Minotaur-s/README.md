# Minotaur-s — Fato ou Farsa

A documentação principal está em [README.md na raiz](../README.md). A especificação vigente do verificador é [spec.md](spec.md), versão 0.5, de 04/11/2026.

- [Curadoria, treino local, calibração e gates](evaluation/README.md)
- [Estado da implementação e validações](evaluation/IMPLEMENTATION_STATUS.md)
- [Proxy gratuito, D1 e implantação](proxy/README.md)

Abrir `Minotaur-s.xcodeproj`; não executar `xcodegen generate` sem reconciliar `project.yml`. Os pesos (>100 MB, limite do GitHub) são versionados fatiados em `model-parts/`; a build remonta e verifica o SHA-256 automaticamente na primeira vez, ou manualmente com `bash scripts/sync-models.sh`. O build confere os pesos/tokenizadores e falha se estiverem ausentes ou alterados; consulte [assets dos modelos](scripts/MODEL_ASSETS.md).

As metas de precisão/cobertura dependem de dados revisados e avaliação real. Os 204 candidatos importados não são gold e o catálogo inicial não decide antes de revisão independente.
