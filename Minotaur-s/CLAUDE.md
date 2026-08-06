# Instruções para Claude Code neste projeto

Este arquivo orienta como trabalhar neste repositório. A especificação técnica completa está em [`spec.md`](./spec.md) — leia-a por inteiro antes de qualquer alteração de código. Este `CLAUDE.md` não substitui a spec, apenas fixa regras operacionais de como aplicá-la.

---

## Estado atual do projeto

A feature **"Verificar Notícia"** foi **reconstruída e está implementada** (Fases 1–5 concluídas). O pipeline atual é:

```
entrada → SearchQueryBuilder → TavilySearchService (via proxy Cloudflare)
→ AllowlistFilter → ArticleExtractor → TextChunker → ChunkQualityFilter
→ EmbeddingService (similaridade de cosseno, top-3) → NLIService
→ VerdictAggregator → VerificationResult
```

Coordenado por `VerificationPipeline`, consumido por `VerificadorView`. Sem `FoundationModels`, sem scraping do DuckDuckGo — ambos foram destruídos na Fase 5 (DT-15).

**Onde as coisas vivem:**

| Diretório | Conteúdo |
|---|---|
| `Models/Verificador/` | `TrustedDomain`, `VerificationResult`, `VerificationError` |
| `Services/Verificador/` | Os 9 serviços do pipeline + o coordenador |
| `Views/Verificador/` | UI: `Verificador.swift`, `VerificationViewModel`, `VerificationPresentation`, `VerificationResultView`, `SafariView` |
| `Minotaur-sTests/Verificador/` | Testes (swift-testing) |
| `spikes/` | Código descartável de validação (Spikes 1–7), com `RESULTADO.md` cada |
| `proxy/` | Worker Cloudflare que injeta a chave da Tavily (DT-21) |

Todos esses são grupos sincronizados no Xcode — arquivo novo entra sozinho, sem editar `project.pbxproj`.

**Tarefa ativa: Fase 6** — trocar o modelo de NLI (DT-18 revisada 2ª vez), conforme o resultado do Spike 7. Ver item aberto 27 (gate de RAM) e o risco materializado em 7.1 da spec.

**Nenhuma outra funcionalidade do app deve ser tocada.** Antes de editar qualquer arquivo, pergunte: *"isso pertence exclusivamente ao fluxo de Verificar Notícia?"* Se a resposta for não ou for incerta, pare e pergunte ao usuário em vez de decidir sozinho. O único acoplamento externo conhecido é `ContentView.swift:55` (`NavigationLink` para `VerificadorView()`) — não edite esse arquivo; preserve o nome do tipo e o `init()` sem argumentos.

---

## Bloqueio de lançamento em aberto

O pipeline **confirma notícias comprovadamente falsas** (risco materializado, seção 7.1 da spec). A causa foi isolada — não é bug de código, é julgamento do modelo de NLI — e a correção decidida é a troca de modelo da Fase 6. Enquanto ela não for integrada e validada ponta a ponta, **o produto não está pronto para lançar**, por mais que compile e passe nos testes.

Isso importa para o seu trabalho: "141 testes passando" não é evidência de que a feature funciona. Os testes usam mocks e pares limpos; o defeito só apareceu em texto real de artigo.

---

## Lições estruturais deste projeto (não repetir)

Três erros já custaram caro aqui. Aplique-os como regra, não como curiosidade:

1. **"Converte sem erro" ≠ "executa em device"** (Spike 2). O mDeBERTa convertia para Core ML e batia logits com PyTorch, mas travava em todo device físico testado. Desde o Spike 2c, o gate de execução em device vem **antes** da avaliação de qualidade — nunca o contrário.
2. **"Acerta pares limpos" ≠ "acerta texto real"** (Spike 7). O modelo escolhido tinha 90% em dataset limpo e 20% em pares adversariais colhidos de artigos reais. Validação de NLI neste projeto exige pares reais, extraídos do pipeline em funcionamento.
3. **Não confie no `id2label` do config** (Spike 7). Confirme a ordem índice→rótulo empiricamente, com sondas inequívocas, antes de medir qualquer coisa. Uma ordem trocada inverte o veredito sem erro visível em lugar nenhum.

E uma armadilha já encontrada em integração: o `swift-transformers` despacha o tokenizador pelo `tokenizer_class` do config, não pelo `model.type`, e cai em `fatalError` (não em `throw`) quando erra a escolha.

---

## Como trabalhar

1. **Leia `spec.md` inteiro** antes de gerar código. Não implemente a partir da memória de conversa — a spec é a fonte de verdade. Se o working tree tiver uma `spec.md` diferente do `HEAD`, a do working tree é a mais recente (o usuário sincroniza manualmente).
2. **Quando resolver um item marcado `[EM ABERTO]` na spec, avise o usuário.** O mesmo vale para reabrir uma DT-XX já decidida.
3. **Você pode editar `spec.md` ou este arquivo sempre que achar necessário, desde que avise o usuário. É importante sempre manter os dois arquivos atualizados para a próxima conversa entender o momento atual do projeto.**.
4. **Trace cada requisito funcional (RF-XX) implementado até um trecho de código identificável.** Se não der para apontar onde um RF foi atendido, ele não foi implementado.
5. **Testes saem dos Critérios de Aceitação (CA-01 a CA-11).** O padrão do projeto é swift-testing em `Minotaur-sTests/Verificador`. Os stubs em `Minotaur-sUITests` são gerados pelo Xcode, não são padrão a seguir.
6. **Avise sempre que implementar algo listado em "Fora de Escopo" (seção 5)**, mesmo que pareça melhoria óbvia.
7. **Spikes são código descartável**, vivem em `spikes/NN-nome/` com um `RESULTADO.md`, e não fazem parte do app.
8. **Quando a tarefa for investigar antes de corrigir, investigue e pare.** Relatar causa com evidência vale mais que uma correção rápida na causa errada.

---

## Pré-requisitos de build

Os `.mlpackage` (113 MB + 320 MB) não são versionados. Antes do primeiro build em qualquer máquina:

```bash
./scripts/sync-models.sh
```

`export_assets.py` (em `spikes/07-tokenizer-parity/`) gera tokenizers e fixtures de paridade e **é** versionado — só precisa rodar de novo em caso de suspeita de drift. A validação real é o `TokenizerParityTests`, não a existência do arquivo. Ver DT-31.

O proxy da Tavily precisa estar deployado e sua URL colada em `TavilySearchService.proxyEndpoint`, ou toda busca falha antes da rede.

---

## Ao final de uma alteração

- [ ] Nenhum arquivo fora do escopo da feature "Verificar Notícia" foi alterado.
- [ ] `ContentView.swift` intocado; `VerificadorView()` continua instanciável sem argumentos.
- [ ] Separação por responsabilidade mantida — nenhum serviço conhece os demais; só o coordenador conhece a ordem.
- [ ] Cada CA relevante verificado (por teste ou manualmente), com a lacuna declarada quando houver.
- [ ] Avisar se algo "Fora de Escopo" foi implementado.
- [ ] Avisar se `[EM ABERTO]` continuam abertos, ou foram resolvidos.
- [ ] Avisar se DT-XX foi reaberta.
- [ ] Achados colaterais relevantes sinalizados ao usuário, mesmo que fora do escopo da tarefa.

---

## Referência rápida da spec

| Seção | Conteúdo |
|---|---|
| 0 | Estado atual vs. estado anterior (motivação da reconstrução) |
| 1 | Objetivo da feature |
| 2 (RF-01 a RF-10) | Requisitos funcionais — pipeline completo |
| 3 (NF-01 a NF-15) | Stack, modelos de ML, performance, segurança, formatos de dados |
| 4 (CA-01 a CA-11) | Critérios de aceitação — base para os testes |
| 5 | Fora de escopo — não implementar |
| 6 (DT-01 a DT-34) | Decisões técnicas já tomadas — não reabrir sem decisão do usuário |
| 7.1 / 7.2 | Riscos técnicos e de produto (inclui o risco materializado de confirmação de notícias falsas) |
| 7.3 | Pontos `[EM ABERTO]` — hoje: 9, 11, 12, 14, 17, 18, 19, 20, 21, 22, 23, 26, 27 |
