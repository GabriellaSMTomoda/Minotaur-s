# Gate físico no iPhone-alvo — execução de 2026-08-10

Status: **BLOQUEADO — aparelho-alvo indisponível**

## Descoberta de aparelhos

A configuração disponível do XcodeBuildMCP não expôs o workflow de devices físicos: os defaults mostraram `deviceId` vazio e somente as operações de simulador estavam habilitadas. Como verificação auxiliar somente leitura, `xcrun devicectl list devices` registrou:

| Estado | Aparelho | Identificador de modelo | Identificador CoreDevice |
|---|---|---|---|
| conectado | iPhone 16 | `iPhone17,3` | `EFEE75FC-18B6-5948-BC37-9F9A6AA0C0F8` |
| indisponível | iPhone 16 | `iPhone17,3` | `BB9BECF6-AB6E-50AE-A728-EE4094E7318E` |
| indisponível | iPad Air (4ª geração) | `iPad13,1` | `D0CF8576-4125-5123-8620-B1CDFE0DE723` |
| indisponível | iPad Air (4ª geração) | `iPad13,1` | `45D49008-87F3-5FD8-9372-D86F60D62F5B` |

Não havia iPhone 13 nem outro iPhone de 4 GB conectado. O iPhone 16 conectado não foi usado como substituto da prova pedida.

## Verificações auxiliares executadas

- `bash -n` aprovou `spikes/08-gate-ram/run_gate_ram.sh` e `run_trained_device_gate.sh`;
- fixture física treinada presente;
- modelos de embeddings e NLI presentes;
- SHA-256 real do `weight.bin` do NLI: `8153a2b3aace8be194a1dd5577191a9f24980947f6d382935c26bbccdd5e2ac2`, igual à evidência de integração.

## Itens não executados

Sem aparelho adequado, não foram executados preflight de armazenamento no alvo, paridade tokenizer/NLI, seis casos críticos, carga conjunta embeddings+NLI, latência fria/aquecida até 512 tokens, memória de pico nem fluxo completo do app. Nenhuma medição anterior ou de simulador foi promovida a evidência deste gate. NF-02 e NF-06 permanecem inalterados.

## Como desbloquear

1. Conectar por USB um iPhone 13 ou outro iPhone compatível com 4 GB de RAM e iOS 17 ou superior.
2. Desbloquear o aparelho, confirmar “Confiar neste computador” e habilitar o Modo de Desenvolvedor.
3. Garantir espaço livre confortável; o harness aborta abaixo de 800 MB, mas o gate deve começar com margem suficiente para instalar app/modelos e evitar contaminação das medições.
4. Habilitar o workflow de devices físicos na configuração do XcodeBuildMCP e confirmar que o aparelho aparece como `connected` com um `deviceId`.
5. Manter a equipe/perfil de assinatura válidos. Não remover a capability/entitlement de Siri para contornar provisioning.

Nenhum app foi instalado ou removido, nenhum dado do aparelho foi alterado e nenhum commit ou push foi feito.
