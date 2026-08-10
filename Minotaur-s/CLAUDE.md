# Instruções para agentes de código neste projeto

Este arquivo registra o estado operacional do repositório. Para mudanças no **Verificador de Notícias**, leia também [`spec.md`](./spec.md) por inteiro: ela é a fonte de verdade dos requisitos, decisões e riscos da feature.

## Estado atual — 10 de agosto de 2026

O app possui duas áreas funcionais: o quiz “Fato ou Farsa”, incluindo Pergunta do Dia/App Intents, e o Verificador de Notícias. A reconstrução do verificador e a troca do NLI estão concluídas no código.

Pipeline atual:

```text
entrada → SearchQueryBuilder → TavilySearchService (proxy Cloudflare)
→ AllowlistFilter → ArticleExtractor → TextChunker → ChunkQualityFilter
→ EmbeddingService (cosseno, top 3) → NLIService (BERTimbau-base)
→ VerdictAggregator → VerificationResult
```

`VerificationPipeline` é o único coordenador. `VerificationViewModel` mantém a inferência fora da main thread e traduz progresso, cancelamento, resultado e falhas para a UI.

Não existem mais `FoundationModels` nem scraping do DuckDuckGo. Não reintroduza nenhum dos dois.

### Modelo NLI integrado

- BERTimbau-base, fine-tune próprio de três classes em PLUE/MNLI (Spike 9);
- MLProgram INT8/FP16, ~104 MB, `.cpuOnly`;
- tokenização WordPiece dedicada em `BERTTokenizer.swift`;
- entradas `input_ids`, `attention_mask` e `token_type_ids`;
- ordem empírica de labels: `[entailment, neutral, contradiction]`;
- limite de 512 tokens por par, com orçamento do chunk descontando a hipótese;
- resultado adversarial: 13/15, incluindo 6/6 nos casos críticos;
- gate físico: até 383,7 MB residentes e 66,5 ms aquecidos em 512 tokens no iPhone 16.

O BERTimbau-large do Spike 7 **não** é o modelo atual: ele reprovou RAM e latência no Spike 8 e foi substituído pelo fine-tune base do Spike 9.

## Estado de validação e distribuição

A auditoria final de 10 de agosto de 2026 registrou:

- 143/143 testes Swift Testing e 6/6 testes de UI no iPhone 16 Pro Simulator/iOS 18.6;
- 28/28 testes focados no iPhone 16;
- paridade WordPiece/Hugging Face e PyTorch/Core ML;
- build e lançamento no simulador e em aparelho;
- build Release arm64 sem assinatura aprovado;
- `.app` sem assinatura com 267.536 KiB (261 MiB), dois modelos Core ML únicos, AppIcon 1024×1024, versão 1.0/build 1 e ATS sem exceções.

O archive assinado continua bloqueado por configuração externa: `Provisioning profile "iOS Team Provisioning Profile: *" doesn't include the Siri capability.` e `doesn't include the com.apple.developer.siri entitlement.` A correção mínima é autenticar no Xcode a conta da equipe `2DK23BZ7KB` e regenerar/baixar o profile de `com.julia.fatoufarsa2025` com Siri habilitada. Não remova entitlements, Siri, bundle identifier ou equipe para contornar o bloqueio.

Não existe política de privacidade acessível nem aviso de primeira execução; também não há privacy manifest próprio do app (somente o manifest transitivo de `swift-crypto`). Archive, `.ipa` e estimativa da App Store só podem ser medidos depois da correção de assinatura.

O modelo ainda tem limitações conhecidas: dois erros em 15 pares adversariais, ambos ligados à nuance de “cura do câncer”, e estabilidade de claims curtos em 2/3 famílias. Não descreva a feature como detector infalível nem remova os avisos/links que contextualizam o resultado.

## Onde trabalhar

| Diretório | Responsabilidade |
|---|---|
| `Models/Verificador/` | `TrustedDomain`, resultado e erros de domínio |
| `Services/Verificador/` | busca, extração, chunks, ML, agregação e coordenador |
| `Views/Verificador/` | entrada, resultado, apresentação e Safari |
| `Minotaur-sTests/Verificador/` | testes Swift Testing e fixtures |
| `spikes/` | pesquisa descartável/reproduzível; não entra no app |
| `proxy/` | Worker stateless que protege a chave da Tavily |

Para uma tarefa restrita ao verificador, não altere outras features por efeito colateral. O acoplamento externo intencional é o `NavigationLink` de `ContentView` para `VerificadorView()`; preserve o nome e o inicializador sem argumentos, salvo se o usuário pedir uma mudança transversal.

## Projeto Xcode e dependências

O arquivo usado hoje é `Minotaur-s.xcodeproj`, que está versionado e contém SwiftSoup, `swift-transformers`, nome de exibição e configurações que ainda não existem em `project.yml`.

**Não execute `xcodegen generate` sem antes sincronizar e revisar `project.yml`.** No estado atual, regenerar o projeto removeria configuração válida.

Configuração relevante:

- Swift 5;
- deployment target iOS 17.0;
- SwiftSoup a partir de 2.9.6;
- `swift-transformers` 1.3.3, produto `Tokenizers`;
- grupos sincronizados no Xcode: arquivos Swift novos nas pastas de sources entram automaticamente.

## Assets de ML

Os pesos Core ML não são versionados. Antes de compilar em uma máquina nova:

```bash
./scripts/sync-models.sh
```

O script copia:

- embeddings de `spikes/02-coreml-latencia/build/Embeddings_int8.mlpackage`;
- NLI de `spikes/09-nli-base-search/build/trained/bertimbau_base_plue_dynamic512_int8.mlpackage`.

Os recursos de tokenizer e labels em `Minotaur-s/Resources/Tokenizers/` são versionados. Para regenerar os assets do NLI selecionado, use `spikes/09-nli-base-search/export_app_assets.py`; não use o export antigo do Spike 7.

## Busca e proxy

O Worker está implantado e `TavilySearchService.proxyEndpoint` aponta para ele. A chave deve existir apenas no secret `TAVILY_API_KEY` do Cloudflare. Nunca coloque a chave em Swift, arquivos de configuração versionados, fixtures ou logs.

A allowlist possui 31 domínios para 30 veículos. O `include_domains` da Tavily não é considerado uma barreira rígida: `AllowlistFilter` deve continuar obrigatório antes do truncamento para cinco resultados.

## Regras de implementação

1. Leia a spec inteira antes de mudar o verificador e trate o working tree como mais recente que o `HEAD`.
2. Mantenha os serviços independentes; somente `VerificationPipeline` conhece a ordem das etapas.
3. Preserve os contratos de privacidade: sem persistência das verificações, sem IA em nuvem e sem log do texto/query no proxy.
4. Preserve a linguagem referenciada às fontes. Nunca transforme os vereditos em “verdadeiro” ou “falso”.
5. Mantenha o aviso de limitação visível sem rolagem e os trechos limitados a 300 caracteres com atribuição e link.
6. Valide a ordem índice→label empiricamente ao trocar qualquer modelo. Não confie apenas em `id2label` remoto.
7. Toda mudança de modelo exige, nesta ordem: execução em aparelho, paridade, RAM/latência e avaliação com pares adversariais reais.
8. Não altere limiares (`0,25` de similaridade; `0,50` de confiança), votação ou margem para mascarar regressão sem reabrir formalmente as DT correspondentes.
9. Testes derivam dos critérios de aceitação. Use Swift Testing em `Minotaur-sTests/Verificador`; os stubs de `Minotaur-sUITests` não são o padrão do projeto.
10. Se uma investigação foi pedida, apresente causa e evidência antes de implementar correção.

## Lições que não podem regredir

- “Converteu” não significa “roda no aparelho”: o mDeBERTa passou conversão/paridade e falhou em device.
- Acurácia em pares limpos não prevê texto jornalístico real: o MiniLM antigo acertava o dataset limpo e confirmava desinformação quando o artigo repetia a alegação para refutá-la.
- INT8 reduz disco, mas pode não reduzir proporcionalmente a RAM do caminho CPU.
- Espaço livre baixo contaminou fortemente medições no Spike 8; todo gate físico deve registrar preflight de armazenamento.
- `token_type_ids` não pode ser substituído por zeros: isso muda logits silenciosamente.
- O tokenizador do NLI é WordPiece próprio; `XLMRTokenizer` continua exclusivo dos embeddings.

## Pendências atuais

Consulte a seção 7.3 da spec para o registro completo. As principais são:

- validar diretamente RAM/latência no aparelho-alvo mais antigo (iPhone 13);
- medir o tamanho final assinado/`.ipa` e corrigir o provisioning de Siri;
- publicar/expor a política de privacidade e implementar o aviso de primeira execução sobre a query enviada;
- definir política de `robots.txt`;
- decidir retry por artigo e validar paywall parcial;
- documentar/comprovar o tratamento real de cota e rate-limit da Tavily;
- avaliar `search_depth="advanced"` e o peso transitivo de `swift-transformers`;
- decidir se nomes amigáveis de veículos substituem os domínios na UI;
- acompanhar os dois erros adversariais residuais e a estabilidade 2/3 de claims curtos.

## Checklist de entrega

- [ ] Alterações limitadas ao escopo pedido pelo usuário.
- [ ] `VerificadorView()` continua instanciável sem argumentos, quando aplicável.
- [ ] Nenhuma chave ou peso grande entrou no Git.
- [ ] Critérios de aceitação relevantes exercitados; lacunas declaradas.
- [ ] Testes focados e, quando viável, suíte completa executados.
- [ ] Mudanças de modelo validadas em aparelho físico com espaço livre registrado.
- [ ] `spec.md`, `README.md` e este arquivo continuam coerentes.
- [ ] Itens `[EM ABERTO]`, DT reabertas e alterações fora de escopo informados ao usuário.
