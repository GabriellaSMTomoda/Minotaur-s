# Verificação física de disponibilidade — 04/11/2026

**Estado final: instalação, inferência, busca real e teste completo pela interface aprovados no iPhone 16.**

Aparelho: iPhone 16 (`iPhone17,3`), iOS 27.2 (24B119), arm64, por USB, Modo de Desenvolvedor habilitado. Xcode 27.0. Bundle e equipe preservados.

Os modelos recuperados e os tokenizadores foram conferidos pelo manifesto SHA-256 no fonte e no bundle. A instalação pelo CoreDevice foi concluída no aparelho sem remover o app/dados anteriores.

Primeira rodada física, com busca real habilitada:

- Carregamento dos dois modelos e pipeline com evidência pública controlada: aprovado.
- Busca real, extração e pares NLI: aprovado.
- Paridade Swift/Core ML com referência PyTorch: aprovada.
- Seis sondas críticas: aprovadas.
- Resultado geral inicial: 161 aprovados, uma falha, um replay opt-in não executado.

A falha estava no teste de manchete nominal: ele chamava o NLTagger duas vezes e assumia que os recursos de idioma estariam no mesmo estado. No aparelho, a primeira chamada não tinha tags e a segunda já tinha. A política foi mantida; o detector passou a ser injetável no teste para verificar os estados “sem verbo” e “recurso indisponível” de forma determinística.

Artefatos locais:

- Rodada inicial: `/tmp/minotaurs-physical-verified.xcresult`.
- Log inicial: `/tmp/minotaurs-physical-tests.log`.
- Instalação: `/tmp/minotaurs-device-install-final.json`.

Os testes físicos exigiram informar `DEVELOPMENT_TEAM=2DK23BZ7KB` ao xcodebuild para assinar os targets de teste, que não têm equipe própria no projeto. Nenhuma capacidade do app foi removida.

Estas verificações demonstram execução no iPhone 16; não constituem teste cego de precisão, gate de RAM/p95 ou validação no iPhone 13. As limitações semânticas da baseline permanecem documentadas.


Após corrigir o teste instável, os 161 testes locais passaram no aparelho, com dois opt-in não executados nessa rodada. O smoke online havia passado na rodada anterior. A execução combinada foi marcada como falha pelo Xcode porque o runner de UI não conseguiu ativar o modo de automação do iOS; o método de UI não chegou a executar. Foi solicitada a habilitação da automação ao usuário.

- Rodada após correção: `/tmp/minotaurs-physical-complete.xcresult`.
- Log: `/tmp/minotaurs-physical-complete.log`.
- Resumo: `/tmp/minotaurs-physical-summary.json`.
- Abertura do app instalado confirmada pelo CoreDevice: `/tmp/minotaurs-physical-launch.json`.

Foi adicionado `testVerifierWithBundledModelsAndLiveSearch` no target de UI, opt-in por `VERIFIER_LIVE_UI_SMOKE=1`. Ele abre o verificador, insere uma afirmação pública fixa, executa a análise e exige a tela de resultado. Não usa mocks nem captura textos de usuários.


A entrega foi reconstruída em DerivedData separado, sem os plugins de teste no bundle. Assinatura e hashes conferidos; app de aproximadamente 262 MiB reinstalado e aberto no aparelho.

- Bundle final: `/tmp/minotaurs-device-delivery/Build/Products/Debug-iphoneos/Minotaur-s.app`.
- Build final: `/tmp/minotaurs-device-delivery-build.log`.
- Instalação final: `/tmp/minotaurs-delivery-install.json`.
- Abertura final: `/tmp/minotaurs-delivery-launch.json`.


## Confirmação final pela interface

Após o usuário ativar a automação de UI no aparelho, o XCTest conseguiu controlar a tela. A primeira tentativa expôs um seletor incorreto no teste (`TextView`); a View usa `TextField`. Foi corrigido somente o seletor do teste.

Resultado final: **um teste de UI aprovado, zero falhas, zero skips**. O teste abriu o app e o Verificador, digitou uma afirmação pública fixa, tocou em “Verificar notícia”, chegou a “Afirmação verificada” e confirmou ausência de “Análise indisponível”. Usou rede e modelos reais.

- Resultado: `/tmp/minotaurs-physical-ui-run2.xcresult`.
- Log: `/tmp/minotaurs-physical-ui-run2.log`.
- Resumo: `/tmp/minotaurs-physical-ui-summary.json`.
- Captura de tela: `/tmp/minotaurs-physical-ui-evidence/331EDABC-2582-40D2-BAE1-575F6DB7C472.png`.
- Duração do teste completo: 26,809 s, incluindo abertura, navegação, espera, digitação e screenshot. Não é uma medida isolada do tempo da análise.

A captura mostra 37 artigos encontrados, oito lidos, cinco usados e cinco origens. O resultado para a afirmação de Terra plana foi “Fontes divergentes”, reforçando a limitação semântica já registrada: o funcionamento está demonstrado, mas a baseline ainda confunde declarações citadas com evidência estabelecida. Não apresentar esse teste como acerto de veredito nem estimativa de precisão.

Depois do teste, o app final sem plugins de teste foi reinstalado e aberto. O runner de UI criado durante os testes foi removido; dados do app principal foram preservados.

- Instalação após UI: `/tmp/minotaurs-delivery-after-ui-install.json`.
- Remoção do runner: `/tmp/minotaurs-ui-runner-cleanup.json`.
- Abertura final: `/tmp/minotaurs-delivery-after-ui-launch.json`.
