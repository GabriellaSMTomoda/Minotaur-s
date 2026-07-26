# Instruções para Claude Code neste projeto

Este arquivo orienta como trabalhar neste repositório. A especificação técnica completa da tarefa atual está em [`spec.md`](./spec.md) — leia-a por inteiro antes de qualquer alteração de código. Este `CLAUDE.md` não substitui a spec, apenas fixa regras operacionais de como aplicá-la.

---

## Escopo desta tarefa

A tarefa ativa é a reconstrução da feature **"Verificar Notícia"**, hoje implementada em `Verificador.swift`. **Nenhuma outra funcionalidade do app deve ser tocada.**

O app é maior que esta feature. Antes de editar qualquer arquivo, pergunte: *"isso pertence exclusivamente ao fluxo de Verificar Notícia?"* Se a resposta for não ou for incerta, pare e pergunte ao usuário em vez de decidir sozinho.

---

## O que fazer com o código atual

`Verificador.swift` hoje:
- faz scraping do DuckDuckGo;
- envia o artigo inteiro para `FoundationModels` analisar de uma vez, sem chunking, sem embeddings, sem NLI;
- concentra lógica de negócio e UI no mesmo arquivo/struct (`VerificadorView`), incluindo a lista `trustedDomains`.

Essa implementação **erra com frequência** e não deve ser usada como referência de arquitetura ou lógica.

### Pode reaproveitar
- Layout, componentes visuais e fluxo de navegação da tela atual, quando forem razoáveis (ver spec, seção 0 e RF-09).
- O **conteúdo** de `trustedDomains` (os domínios em si) — ver RF-03.1. Só o conteúdo, não a forma como está armazenado hoje.

### NÃO pode reaproveitar
- Qualquer lógica de scraping, parsing de HTML, chamada ao `FoundationModels`, ou decisão de arquitetura da análise em si.
- A estrutura de "tudo em um arquivo só" — a nova lógica deve ser separada em arquivos próprios por responsabilidade (busca, extração, embeddings, NLI, agregação). Ver DT-17 na spec.
- `trustedDomains` permanecendo como propriedade de `VerificadorView` — deve ser movido para fora da camada de UI (RF-03.6).

### Regra de segurança
Se durante a implementação você encontrar mais trechos do código antigo que pareçam reaproveitáveis além do que está listado acima, **pare e pergunte antes de reaproveitar**. Não assuma.

Antes de deletar qualquer parte de `Verificador.swift`, mapeie o que outras partes do app chamam dele (imports, referências, tipos compartilhados) — não delete às cegas. Isso é risco explícito na spec (seção 7.1).

---

## Como trabalhar

1. **Leia `spec.md` inteiro** antes de gerar código. Não implemente a partir da memória da conversa que originou a spec — a spec é a fonte de verdade.
2. **Rode os spikes técnicos da seção 7.4 da spec antes da implementação final**, nesta ordem: (1) modelos em PT-BR, (2) conversão Core ML + latência real em dispositivo, (3) extração de texto nos domínios da allowlist, (4) estabilidade do scraping do DDG. Esses spikes são código descartável (script/CLI), não fazem parte do app.
3. **Nunca resolva um item marcado `[EM ABERTO]` na spec por conta própria.** Marque como pendência, pergunte ao usuário, ou proponha uma opção e peça confirmação antes de seguir.
4. **Trace cada requisito funcional (RF-XX) implementado até um trecho de código identificável.** Se não der para apontar onde um RF foi atendido, ele não foi implementado.
5. **Escreva testes a partir dos Critérios de Aceitação (CA-01 a CA-11).** Cada CA da spec deve virar um teste antes de considerar a tarefa concluída — não "compila e roda", e sim "os critérios de aceitação passam".
6. **Não implemente nada listado em "Fora de Escopo" (seção 5 da spec)**, mesmo que pareça uma melhoria óbvia. Sinalize a ideia ao usuário em vez de implementar.

---

## Ao final de uma alteração

Antes de considerar a tarefa concluída, confirme explicitamente:
- [ ] Nenhum arquivo fora do escopo da feature "Verificar Notícia" foi alterado.
- [ ] `trustedDomains` foi migrado para fora de `VerificadorView`, preservando o conteúdo.
- [ ] A lógica de análise foi reescrita do zero (sem `FoundationModels` analisando o artigo inteiro).
- [ ] A nova lógica está separada em arquivos por responsabilidade, não concentrada em um único arquivo.
- [ ] Cada CA relevante da spec foi verificado (manualmente ou por teste).
- [ ] Nenhum item de "Fora de Escopo" foi implementado (incluindo: nenhuma verificação anterior é persistida, em nenhuma forma).
- [ ] Itens `[EM ABERTO]` da spec continuam em aberto ou foram resolvidos com confirmação explícita do usuário, não por suposição.

---

## Referência rápida da spec

| Seção | Conteúdo |
|---|---|
| 0 | Contexto: o que pode/não pode ser reaproveitado do código atual |
| 1 | Objetivo da feature |
| 2 (RF-01 a RF-10) | Requisitos funcionais — pipeline completo: entrada → busca (Tavily via proxy) → extração → embeddings → NLI → agregação → resultado → erros |
| 3 (NF) | Stack, modelos, performance, segurança, formatos de dados |
| 4 (CA-01 a CA-11) | Critérios de aceitação — base para os testes |
| 5 | Fora de escopo — não implementar |
| 6 (DT-01 a DT-21) | Decisões técnicas já tomadas — não reabrir sem necessidade |
| 7 | Riscos e pontos `[EM ABERTO]` — não resolver sem confirmação do usuário |
