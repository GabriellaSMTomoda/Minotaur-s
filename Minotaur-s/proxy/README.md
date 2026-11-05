# Proxy gratuito de busca — contrato v2

O app envia consultas curtas por POST; o Worker protege a chave Tavily e impõe a política de custo. Não chama LLM, não guarda consultas/artigos/resultados e não registra corpos. D1 armazena somente mês, contadores produção/avaliação, minuto e rajada. Não há cache de conteúdo nem IDs de pessoas/aparelhos.

## Política imposta no servidor

- `search_depth=basic`, `max_results=20`, `include_answer=false`, `auto_parameters=false`, `language=pt`, `filter_by_language=true`.
- Lista de domínios do servidor; `query_kind=factCheck` escolhe o subconjunto de checagem. Os domínios fornecidos pelo cliente são ignorados.
- Até 200 grafemas na consulta e corpo de até 8 KiB. Campos de chaves, custo, respostas geradas e extração remota são descartados.
- Uma reserva SQLite/D1 atômica ANTES de cada fetch externo: 800 chamadas produção + 200 avaliação/mês; teto global 1.000. Tentativas incertas não são devolvidas ao orçamento.
- Máximo global de 30 chamadas/minuto. Isso limita rajadas; não autentica instalações nem impede alguém de esgotar a cota pública.
- Contadores por mês UTC. Antes de ativar, confirmar o ciclo real da conta Tavily e reconciliar consumo já realizado no mês. O plano da conta deve ser **Researcher/Free, sem pay-as-you-go**. O Worker não altera o faturamento da conta.
- Avaliação exige o secret independente `EVALUATION_KEY`, enviado no header `X-Evaluation-Key`; nunca embarcado no app. Clientes comuns usam produção. A reserva de avaliação não pode ser escolhida por campo JSON.
- Falha do D1 impede a chamada externa. Timeout externo 4,5 segundos; o app também aplica orçamento total por verificação e limite de três tentativas.

A allowlist está em `src/domains.js`; o teste confere igualdade com o Swift. Alterar os dois cadastros na mesma mudança. Preservar allowlist também no aparelho e validar URLs finais dos artigos.

## Preparação e implantação

```sh
npm ci
npm test
npx wrangler deploy --dry-run
npx wrangler login
npx wrangler d1 create minotaurs-search-budget
```

Adicionar o `database_id` retornado ao binding `SEARCH_BUDGET` de `wrangler.jsonc`. O arquivo já declara nome e migrations; IDs de banco não são segredos. Aplicar a migração antes de implantar:

```sh
npx wrangler d1 migrations apply minotaurs-search-budget --remote
npx wrangler secret list
# A chave existente TAVILY_API_KEY deve ser preservada.
# Se a chave não existir, usar o prompt seguro: npx wrangler secret put TAVILY_API_KEY
npx wrangler secret put EVALUATION_KEY
npx wrangler deploy
```

`EVALUATION_KEY` é opcional para o tráfego de produção; sem ele, a faixa de avaliação fica inacessível. Não colocar chaves em argumentos, fixtures, arquivos versionados ou logs. Não habilitar plano Workers pago.

Ao migrar no meio do mês, inserir/reconciliar o consumo existente no D1, incluindo uso de outras chaves da mesma conta Tavily, antes de liberar tráfego. Uma conta nova com consumo zero pode iniciar sem linhas. Não zerar contadores do mês para recuperar disponibilidade. O servidor recusa buscas se o binding/tabela estiver ausente.

A URL do Worker permanece a mesma. Requisições antigas continuam aceitas: seus parâmetros são restringidos à política v2. Novos clientes toleram o Worker anterior, mas só a implantação v2 ativa o teto atômico. `wrangler deploy --dry-run` não implanta nada.

## Erros

| Status / marcador | Significado | App |
|---|---|---|
| 200 | candidatos de busca | filtrar e ranquear |
| 401/403 | chave/configuração inválida | sem retry |
| 429 + `X-Search-Error: quota_exceeded` | cota mensal própria | sem retry; aguardar renovação |
| 429 + `rate_limited` | rajada temporária | sem retry automático; `Retry-After: 60` |
| 432/433 upstream | limite de uso/plano Tavily | cota esgotada |
| 5xx | falha transitória ou indisponibilidade do orçamento | no máximo um retry, dentro do teto de três |

O corpo da Tavily é transmitido em streaming, sem log. `Cache-Control: no-store` impede cache das respostas do proxy.

## Testes

`npm test` usa SQLite real em memória, sem Cloudflare/Tavily/rede: concorrência no teto de 800, faixa autenticada de 200, rajadas, tentativas incertas, falha fechada, restrição de parâmetros, tamanho e paridade da allowlist. Tipos do binding podem ser gerados com `npx wrangler types`.

## Implantação concluída em 04/11/2026

- URL de produção preservada: `https://minotaurs-tavily-proxy.hen-lac-sil.workers.dev`.
- Versão `b5c751d7-1d30-4353-aeca-825fa65f5b30` em 100% do tráfego.
- D1 `minotaurs-search-budget`, ID `eca0d7e5-871b-46a9-b165-eb8d2d7e2b6a`; migração `0001_search_budget.sql` aplicada.
- Secrets `TAVILY_API_KEY` (preservada) e `EVALUATION_KEY` (adicionada). A própria chave do Worker confirmou plano Researcher/1.000 créditos e consumo pay-as-you-go zero.
- Contador de novembro inicializado com uma busca de produção pré-migração, por prudência. Após os testes ao vivo: produção 2, avaliação 1. Não diminuir esses valores para repetir testes.
- Buscas reais nas duas faixas: HTTP 200, `usage.credits=1`, `answer` ausente/nulo, `Cache-Control: no-store`, inclusive com parâmetros caros injetados pelo cliente. Onze testes locais aprovados.
- A credencial de avaliação foi salva somente em `~/Library/Application Support/Minotaur-s/credentials/evaluation-key`, modo 0600, fora do repositório. Não copiar para o app nem imprimir em logs.

O endpoint GET `/_admin/usage` requer `X-Evaluation-Key`. Ele usa a secret Tavily existente para consultar plano/uso agregado, sem retornar a chave, consultas ou resultados, e não reserva uma busca no D1. Sem credencial responde 404. Usar essa leitura para reconciliar o orçamento antes de novas implantações. O contador local continua conservador caso a API de uso do provedor ainda não reflita requisições recentes.

Os filtros legados `country=brazil` (general) e `time_range=year` (news) continuam aceitos; valores arbitrários são descartados. Nenhum plano pago foi habilitado durante a implantação.
