# Proxy da Tavily (Cloudflare Workers)

Worker stateless que injeta a chave da API da Tavily nas buscas do app (DT-21 / NF-09).
O app **nunca** chama `api.tavily.com` direto e **nunca** embarca a chave.

Este diretório é código de infraestrutura, não faz parte do target iOS.

## Deploy (ação do mantenedor)

O deploy e a chave são responsabilidade de quem mantém o projeto — nada aqui foi deployado.

```bash
cd proxy && npx wrangler secret put TAVILY_API_KEY
```

```bash
cd proxy && npx wrangler deploy
```

O `wrangler deploy` imprime a URL pública (`https://minotaurs-tavily-proxy.<subdomínio>.workers.dev`).
Essa URL vai em `TavilySearchService.proxyEndpoint`, em
`Minotaur-s/Services/Verificador/TavilySearchService.swift`. Enquanto ela estiver vazia, a
busca falha com `.searchRequestFailed` antes de tocar a rede.

## Contrato

O app envia `POST` com JSON e **sem** chave:

```json
{
  "query": "primeira frase da afirmação",
  "search_depth": "basic",
  "max_results": 10,
  "include_domains": ["g1.globo.com", "..."]
}
```

Só esses quatro campos são repassados; qualquer outro é descartado, para que o cliente não
possa injetar parâmetros de custo nem sobrescrever a chave.

O status e o corpo da Tavily voltam **intactos**. O app depende disso:

| Status | Tratamento no app |
|---|---|
| 200 | resposta normal |
| 401 / 403 | falha de busca, **sem** retry (chave inválida — DT-27) |
| 429 | `searchQuotaExceeded` (RF-10.2), **sem** retry |
| 5xx | falha transitória, **1** tentativa extra (RF-04.6 / DT-27) |

## Privacidade

Stateless por decisão (NF-07 / DT-13): não há KV, D1, cache nem log do corpo. O texto do
usuário existe só na memória da requisição.

## Custo

Tier gratuito do Workers: 100.000 requisições/dia. A cota que aperta primeiro é a da Tavily
(1.000 créditos/mês, 1 crédito por busca `basic`), e ela **não** é exposta em nenhum header
ou campo da resposta — o acompanhamento é manual, em `app.tavily.com` (Spike 5, seção 4.3).
