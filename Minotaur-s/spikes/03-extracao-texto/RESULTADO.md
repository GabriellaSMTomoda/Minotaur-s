# SPIKE 3 — Resultado: Extração de Texto Principal em HTML Estático

**Data:** 2026-07-24
**Objetivo:** validar se dá para extrair o texto principal de artigos de
notícia (descartando menu/rodapé/ads/comentários/"leia também") a partir do
HTML estático dos 34 domínios de `trustedDomains`
(`Minotaur-s/Minotaur-s/Views/Verificador.swift`, linhas 61-96) — risco
citado na spec §7.2 ("extração de texto principal falhar em muitos sites").
Etapa 3 da ordem de spikes definida em §7.4 do `spec.md`.

Código de validação descartável, isolado do app iOS (Python, fora do
projeto Xcode). Não decide biblioteca Swift final, não implementa nada do
app, não avança para scraping via DDG (spike futuro/anterior) e não remove
nada da allowlist — só recomenda.

---

## Veredito rápido

> **30 dos 34 domínios (88%) tiveram pelo menos uma URL com extração limpa,
> ≥200 caracteres, sem paywall e sem depender de JS**, usando só
> `requests` + HTML estático. Os 4 domínios que falharam (uol.com.br,
> ibge.gov.br, reuters.com, espn.com.br) falharam **100% por bloqueio de
> bot no download** (HTTP 401/403/202 vazio) — nenhuma URL baixada com
> sucesso teve texto poluído ou curto demais. **A extração de texto em si
> não é o gargalo**; o risco real e concentrado é bloqueio de scraping em
> alguns sites específicos. **`trafilatura` (abordagem A) venceu 57/86
> comparações (66%) contra 29/86 (34%) da heurística manual (abordagem B)**,
> mas B também produziu texto utilizável na maioria dos casos — a diferença
> foi de robustez a armadilhas do HTML real, não de "funciona vs não
> funciona".

---

## Metodologia

1. Para cada um dos 34 domínios, 2–3 URLs de artigo/notícia real e atual
   (`urls.py`) — achadas por: extração automática de links da homepage
   (`discover_urls.py`), inspeção manual de seções quando a homepage só
   trazia links de categoria/hub (`probe.py`), e busca web para os poucos
   casos em que a listagem de notícias depende de JS ou o domínio bloqueia
   requisição direta. Nenhuma URL foi inventada — todas resolvem para
   páginas reais conferidas manualmente. Total: **34 domínios, 96 URLs**.
2. Download com `requests`, User-Agent de navegador real, timeout 15s
   (`download.py`) → `download_manifest.json`.
3. Duas abordagens de extração sobre cada HTML baixado (`compare.py`):
   - **A — `trafilatura`** (`extract_a_trafilatura.py`): biblioteca de
     readability pronta, `favor_precision=True`.
   - **B — heurística manual** (`extract_b_heuristic.py`): remove
     `script/style/nav/footer/aside/form/header` + qualquer elemento cujo
     `class`/`id` bata num denylist (`related`, `comment`, `sidebar`,
     `nav`, `footer`, `ads`, `leia-tambem`, `newsletter`, `menu`, etc.); se
     existir `<article>`, usa os `<p>` dentro dele; senão, escolhe o menor
     container que ainda cobre ≥90% do texto de `<p>` encontrado no
     documento (ver "achados" abaixo sobre por que não é só "o
     container com mais texto").
4. Por URL: chars extraídos, ≥200 chars (limite de RF-05.3), paywall
   (padrões de texto tipo "assine para continuar" **no texto já extraído**,
   não na página toda — ver nota abaixo), indício de dependência de JS
   (HTML muito curto, `<div id="root"></div>` vazio, ou quase nenhum
   texto em `<p>` apesar de HTML grande), tempo de download.

---

## Tabela por domínio × URL

| Domínio | URL (resumida) | Tempo download | JS-dep? | Paywall? | Vencedor | Chars (vencedor) | ≥200 chars? | Qualidade |
|---|---|---:|:---:|:---:|---|---:|:---:|---|
| g1.globo.com | g1.globo.com/politica/blog/valdo-cruz/post/2026/07/2... | 0.18s | não | não | B (heurística) | 2106 | sim | limpo |
| g1.globo.com | g1.globo.com/politica/blog/natuza-nery/post/2026/07/... | 0.21s | não | não | B (heurística) | 2173 | sim | limpo |
| g1.globo.com | g1.globo.com/economia/noticia/2026/07/24/durigan-exp... | 0.20s | não | não | A (trafilatura) | 3816 | sim | limpo |
| oglobo.globo.com | oglobo.globo.com/brasil/noticia/2026/07/24/foie-gras... | 0.32s | não | não | A (trafilatura) | 4581 | sim | limpo |
| oglobo.globo.com | oglobo.globo.com/brasil/noticia/2026/07/24/governo-s... | 0.35s | não | não | A (trafilatura) | 3378 | sim | limpo |
| oglobo.globo.com | oglobo.globo.com/brasil/noticia/2026/07/23/igreja-pr... | 0.36s | não | não | A (trafilatura) | 2596 | sim | limpo |
| uol.com.br | noticias.uol.com.br/colunas/josias-de-souza/... | - | - | - | - | - | - | **bloqueado**: HTTP 403 |
| uol.com.br | economia.uol.com.br/noticias/redacao/... | - | - | - | - | - | - | **bloqueado**: HTTP 403 |
| uol.com.br | noticias.uol.com.br/colunas/carlos-madeiro/... | - | - | - | - | - | - | **bloqueado**: HTTP 403 |
| folha.uol.com.br | www1.folha.uol.com.br/colunas/adriana-fernandes/2026... | 0.17s | não | não | B (heurística) | 2514 | sim | limpo |
| folha.uol.com.br | www1.folha.uol.com.br/colunas/conrado-hubner-mendes/... | 0.16s | não | não | B (heurística) | 3655 | sim | limpo |
| folha.uol.com.br | www1.folha.uol.com.br/blogs/brasilia-hoje/2026/07/al... | 0.16s | não | não | B (heurística) | 3473 | sim | limpo |
| estadao.com.br | www.estadao.com.br/brasil/laco-de-cv-e-deputado-do-r... | 0.23s | não | não | B (heurística) | 4803 | sim | limpo |
| estadao.com.br | www.estadao.com.br/politica/blog-do-fausto-macedo/pg... | 0.12s | não | não | B (heurística) | 6112 | sim | limpo |
| estadao.com.br | www.estadao.com.br/brasil/de-agencia-antimafia-a-fas... | 0.14s | não | não | B (heurística) | 9975 | sim | limpo |
| cnnbrasil.com.br | www.cnnbrasil.com.br/internacional/israel-prepara-gr... | 0.17s | não | não | A (trafilatura) | 4824 | sim | limpo |
| cnnbrasil.com.br | www.cnnbrasil.com.br/internacional/ira-diz-que-ataqu... | 0.16s | não | não | A (trafilatura) | 3927 | sim | limpo |
| cnnbrasil.com.br | www.cnnbrasil.com.br/internacional/navios-sauditas-p... | 0.16s | não | não | B (heurística) | 1881 | sim | limpo |
| veja.abril.com.br | veja.abril.com.br/brasil/brasileiras-ja-podem-compra... | 0.14s | não | não | A (trafilatura) | 2266 | sim | limpo |
| veja.abril.com.br | veja.abril.com.br/brasil/ex-prefeito-e-esposa-sao-fa... | 0.14s | não | não | A (trafilatura) | 2636 | sim | limpo |
| veja.abril.com.br | veja.abril.com.br/brasil/inqueritos-contra-autoridad... | 0.15s | não | não | A (trafilatura) | 1348 | sim | limpo |
| valor.globo.com | valor.globo.com/brasil/noticia/2026/07/24/consumo-su... | 0.43s | não | não | A (trafilatura) | 448 | sim | limpo |
| valor.globo.com | valor.globo.com/brasil/noticia/2026/07/24/eua-confir... | 0.30s | não | não | A (trafilatura) | 548 | sim | limpo |
| valor.globo.com | valor.globo.com/brasil/noticia/2026/07/23/fiscal-pre... | 0.49s | não | não | B (heurística) | 1622 | sim | limpo |
| exame.com | exame.com/invest/mercados/sete-magnificas-perdem-r-4... | 0.17s | não | não | B (heurística) | 4296 | sim | limpo |
| exame.com | exame.com/invest/mercados/ibovespa-volta-a-cair-com-... | 0.17s | não | não | B (heurística) | 5092 | sim | limpo |
| exame.com | exame.com/invest/mercados/petroleo-e-juros-por-que-a... | 2.05s | não | não | B (heurística) | 5208 | sim | limpo |
| r7.com | noticias.r7.com/economia/piora-o-que-ja-estava-ruim-... | 0.22s | não | não | B (heurística) | 2700 | sim | limpo |
| r7.com | noticias.r7.com/economia/receita-abre-consulta-ao-te... | 0.16s | não | não | A (trafilatura) | 2068 | sim | limpo |
| r7.com | noticias.r7.com/economia/vai-ter-impacto-no-emprego-... | 0.24s | não | não | B (heurística) | 1918 | sim | limpo |
| terra.com.br | www.terra.com.br/noticias/brasil/acidente-da-voepass... | 0.08s | não | não | A (trafilatura) | 8373 | sim | limpo |
| terra.com.br | www.terra.com.br/noticias/brasil/brasil-e-o-maior-pe... | 0.11s | não | não | A (trafilatura) | 4644 | sim | limpo |
| terra.com.br | www.terra.com.br/economia/governo-lula-diminui-bloqu... | 0.08s | não | não | A (trafilatura) | 2796 | sim | limpo |
| metropoles.com | www.metropoles.com/brasil/apos-tarifaco-lula-fala-em... | 0.50s | não | não | A (trafilatura) | 2790 | sim | limpo |
| metropoles.com | www.metropoles.com/brasil/produtos-brasileiros-serao... | 0.16s | não | não | A (trafilatura) | 7370 | sim | limpo |
| metropoles.com | www.metropoles.com/brasil/governo-lula-reage-a-nova-... | 0.15s | não | não | A (trafilatura) | 4104 | sim | limpo |
| poder360.com.br | www.poder360.com.br/poder-economia/jbs-mira-expansao... | 0.13s | não | não | A (trafilatura) | 5843 | sim | limpo |
| poder360.com.br | www.poder360.com.br/poder-governo/so-vou-falar-do-ta... | 0.13s | não | não | A (trafilatura) | 2860 | sim | limpo |
| poder360.com.br | www.poder360.com.br/poder-economia/saiba-quais-indic... | 0.11s | não | não | A (trafilatura) | 1901 | sim | limpo, ruído leve (1) |
| gzh.com.br | gauchazh.clicrbs.com.br/viral/noticia/2026/07/joao-g... | 1.13s | não | não | B (heurística) | 837 | sim | limpo |
| gzh.com.br | gauchazh.clicrbs.com.br/colunistas/gisele-loeblein/n... | 0.82s | não | não | A (trafilatura) | 4379 | sim | limpo |
| correiobraziliense.com.br | .../politica/2026/07/7467410-pp-opta-pela-neut... | 0.14s | não | não | B (heurística) | 1805 | sim | limpo |
| correiobraziliense.com.br | .../brasil/2026/07/7467405-mulheres-ja-podem-c... | 0.14s | não | não | A (trafilatura) | 2422 | sim | limpo |
| correiobraziliense.com.br | .../brasil/2026/07/7467426-alem-do-spray-4-ite... | 0.13s | não | não | B (heurística) | 3887 | sim | limpo |
| agenciabrasil.ebc.com.br | .../economia/noticia/2026-07/eua-impoem... | 0.07s | não | não | A (trafilatura) | 5027 | sim | limpo |
| agenciabrasil.ebc.com.br | .../economia/noticia/2026-07/ministro-chama... | 0.08s | não | não | B (heurística) | 4065 | sim | limpo |
| agenciabrasil.ebc.com.br | .../economia/noticia/2026-07/estados-unidos... | 0.07s | não | não | A (trafilatura) | 3467 | sim | limpo |
| otempo.com.br | www.otempo.com.br/politica/2026/7/24/dataprev-formal... | 0.16s | não | não | A (trafilatura) | 4317 | sim | limpo |
| otempo.com.br | www.otempo.com.br/politica/governo/2026/7/14/na-vesp... | 0.12s | não | não | A (trafilatura) | 2462 | sim | limpo, ruído leve (1) |
| otempo.com.br | www.otempo.com.br/cidades/2026/7/24/justica-decide-n... | 0.12s | não | não | A (trafilatura) | 3835 | sim | limpo |
| band.uol.com.br | www.band.com.br/noticias/justica-decreta-prisao-prev... | 0.13s | não | não | A (trafilatura) | 2255 | sim | limpo |
| band.uol.com.br | www.band.com.br/noticias/entenda-o-que-esta-por-tras... | 0.14s | não | não | A (trafilatura) | 10548 | sim | limpo, ruído leve (1) |
| band.uol.com.br | www.band.com.br/economia/noticias/tarifaco-de-trump-... | 0.12s | não | não | B (heurística) | 7655 | sim | limpo, ruído leve (1) |
| ge.globo.com | ge.globo.com/futebol/times/cruzeiro/noticia/2026/07/... | 0.20s | não | não | B (heurística) | 2052 | sim | limpo |
| ge.globo.com | ge.globo.com/futebol/copa-do-mundo/noticia/2026/06/1... | 0.19s | não | não | B (heurística) | 8035 | sim | limpo |
| ge.globo.com | ge.globo.com/gato-mestre/dicas/noticia/2026/07/24/pa... | 0.21s | não | não | B (heurística) | 2667 | sim | limpo |
| espn.com.br | www.espn.com.br/futebol/sao-paulo/artigo/.../16096849 | - | - | - | - | - | - | **bloqueado**: HTTP 202 (vazio) |
| espn.com.br | www.espn.com.br/futebol/copa-do-mundo/artigo/.../16551330 | - | - | - | - | - | - | **bloqueado**: HTTP 202 (vazio) |
| aosfatos.org | aosfatos.org/noticias/brastemp-consul-fabrica-brasil/ | 0.15s | não | não | A (trafilatura) | 3049 | sim | limpo |
| aosfatos.org | aosfatos.org/noticias/moraes-trump-visitar-bolsonaro/ | 0.17s | não | não | A (trafilatura) | 4020 | sim | limpo |
| aosfatos.org | aosfatos.org/noticias/governo-idade-minima-aposentad... | 0.15s | não | não | A (trafilatura) | 2742 | sim | limpo |
| lupa.uol.com.br | www.agencialupa.org/noticias/2026/07/21/e-falso-que-... | 0.15s | não | não | B (heurística) | 4881 | sim | limpo |
| lupa.uol.com.br | www.agencialupa.org/verificacao/2026/07/02/e-golpe-s... | 0.14s | não | não | A (trafilatura) | 5690 | sim | limpo |
| lupa.uol.com.br | www.agencialupa.org/institucional/2026/07/21/aqui-na... | 0.13s | não | não | A (trafilatura) | 3830 | sim | limpo |
| bbc.com | www.bbc.com/portuguese/articles/c75yy56153xo | 0.45s | não | não | A (trafilatura) | 724 | sim | limpo |
| bbc.com | www.bbc.com/portuguese/articles/c8rn582102vo | 0.16s | não | não | A (trafilatura) | 4939 | sim | limpo |
| bbc.com | www.bbc.com/portuguese/articles/cz64le56412o | 0.16s | não | não | A (trafilatura) | 3124 | sim | limpo |
| dw.com | www.dw.com/pt-br/falta-de-emprego-entre-jovens... | 0.16s | não | não | B (heurística) | 7061 | sim | limpo |
| dw.com | www.dw.com/pt-br/alvo-de-tarifaço-brasil... | 1.41s | não | não | B (heurística) | 9273 | sim | limpo |
| dw.com | www.dw.com/pt-br/flávio-e-michelle-fazem-as-pazes... | 0.75s | não | não | A (trafilatura) | 4344 | sim | limpo |
| elpais.com | elpais.com/internacional/2026-07-24/trump-impone-un-... | 0.18s | não | não | A (trafilatura) | 6995 | sim | limpo |
| elpais.com | elpais.com/internacional/2026-07-24/las-claves-de-lo... | 0.20s | não | não | A (trafilatura) | 7616 | sim | limpo |
| elpais.com | elpais.com/internacional/2026-07-24/bruselas-recibe-... | 0.19s | não | não | A (trafilatura) | 6243 | sim | limpo |
| reuters.com | www.reuters.com/world/ | - | - | - | - | - | - | **bloqueado**: HTTP 401 |
| reuters.com | www.reuters.com/business/ | - | - | - | - | - | - | **bloqueado**: HTTP 401 |
| apnews.com | apnews.com/article/iran-us-hormuz-strait-war-24-july... | 0.19s | não | não | B (heurística) | 9248 | sim | limpo |
| apnews.com | apnews.com/article/usvi-lawsuit-guns-concealed-2nd-a... | 0.17s | não | não | A (trafilatura) | 2712 | sim | limpo |
| apnews.com | apnews.com/article/usmediatimesair-force-one-42429e4... | 0.20s | não | não | A (trafilatura) | 7321 | sim | limpo |
| gov.br | agenciagov.ebc.com.br/noticias/202607/governo-brasil... | 0.14s | não | não | A (trafilatura) | 3071 | sim | limpo |
| gov.br | agenciagov.ebc.com.br/noticias/202607/enade-2026-pra... | 0.08s | não | não | A (trafilatura) | 1212 | sim | limpo |
| gov.br | agenciagov.ebc.com.br/noticias/202607/cnpj-alfanumer... | 0.07s | não | não | A (trafilatura) | 6727 | sim | limpo |
| camara.leg.br | www.camara.leg.br/noticias/1290742-projeto-preve-ava... | 0.17s | não | não | A (trafilatura) | 2517 | sim | limpo |
| camara.leg.br | www.camara.leg.br/noticias/1285520-projeto-protege-s... | - | - | - | - | - | - | **falhou**: HTTP 500 (intermitente — funcionou em teste manual isolado antes) |
| camara.leg.br | www.camara.leg.br/noticias/1293099-retrospectiva-dep... | 0.09s | não | não | A (trafilatura) | 5113 | sim | limpo |
| senado.leg.br | www12.senado.leg.br/noticias/materias/2026/07/24/ele... | 0.61s | não | não | A (trafilatura) | 8249 | sim | limpo |
| senado.leg.br | www12.senado.leg.br/noticias/materias/2026/07/24/lei... | 0.25s | não | não | A (trafilatura) | 4991 | sim | limpo |
| stf.jus.br | noticias.stf.jus.br/postsnoticias/stf-revoga-medidas... | 0.75s | não | não | A (trafilatura) | 2565 | sim | limpo, ruído leve (1) |
| stf.jus.br | noticias.stf.jus.br/postsnoticias/decisao-do-stf-per... | 0.71s | não | não | A (trafilatura) | 2862 | sim | limpo |
| stf.jus.br | noticias.stf.jus.br/postsnoticias/rede-questiona-fal... | 1.17s | não | não | A (trafilatura) | 1671 | sim | limpo |
| tse.jus.br | www.tse.jus.br/comunicacao/noticias/2026/Julho/manua... | 0.10s | não | não | B (heurística) | 4462 | sim | limpo, ruído leve (1) |
| tse.jus.br | www.tse.jus.br/comunicacao/noticias/2026/Julho/justi... | 0.10s | não | não | A (trafilatura) | 1872 | sim | limpo |
| tse.jus.br | www.tse.jus.br/comunicacao/noticias/2026/Abril/justi... | 0.07s | não | não | A (trafilatura) | 3958 | sim | limpo |
| ibge.gov.br | agenciadenoticias.ibge.gov.br/.../47613-ibge-partici... | - | - | - | - | - | - | **bloqueado**: HTTP 403 |
| ibge.gov.br | agenciadenoticias.ibge.gov.br/.../47506-cumprimento-... | - | - | - | - | - | - | **bloqueado**: HTTP 403 |
| who.int | www.who.int/news/item/02-07-2026-who-adds-first-diag... | 0.13s | não | não | B (heurística) | 4721 | sim | limpo |
| who.int | www.who.int/news/item/03-02-2026-who-launches-2026-a... | 0.15s | não | não | A (trafilatura) | 4380 | sim | limpo |

URLs completas, manifest bruto e resultados detalhados (incluindo o texto
extraído por ambas as abordagens em cada URL) em `download_manifest.json`,
`results.json` e `urls.py`.

---

## Abordagem A × Abordagem B

| | A — trafilatura | B — heurística manual |
|---|---:|---:|
| Comparações vencidas (de 86 downloads OK) | **57 (66%)** | 29 (34%) |
| Domínios em que produziu texto utilizável em ≥1 URL | 30/30 dos utilizáveis | 26/30 dos utilizáveis |
| Falhas por bug/armadilha de heurística (corrigidas durante o spike) | 0 | 3 classes de bug (ver abaixo) |

**`trafilatura` venceu com folga e nunca precisou de correção** — é uma
biblioteca madura, testada contra HTML real de milhares de sites, e isso
apareceu na prática: zero falhas catastróficas em qualquer um dos 86 HTMLs
baixados.

**A heurística manual (B) funcionou na maioria dos casos, mas expôs 3
armadilhas reais do HTML de produção** que só apareceram ao rodar contra
sites de verdade (não teria sido óbvio escrevendo o denylist "no papel"):

1. **Classes utilitárias na tag `<html>`/`<body>` batendo no denylist.**
   `g1.globo.com` põe a classe `glb-theme-elem-sharebar--touch` na própria
   `<html>` (tema/estado de UI, nada a ver com o botão de compartilhar do
   artigo). Um denylist ingênuo por substring (`share`) casava com essa
   classe e apagava a **página inteira** ao decompor a tag raiz. Corrigido
   proibindo remoção de tags estruturais (`html`, `body`, `main`,
   `article`) — só os descendentes delas são candidatos ao denylist.
2. **Container de conteúdo GRATUITO literalmente chamado de `-paywall-parent`.**
   No Estadão, o `<div>` que envolve os parágrafos do preview antes do
   corte de assinatura se chama `-paywall-parent` — é o "pai da barreira",
   não o conteúdo pago. O termo `paywall` no denylist apagava o próprio
   texto do artigo. Corrigido removendo `paywall` do denylist estrutural;
   detecção de paywall de verdade passou a olhar o **texto já extraído**
   (chamada de assinatura no fim do texto), não nomes de classe CSS.
3. **Wrapper de todo o corpo da página nomeado por um plugin de menu
   mobile.** Em `poder360.com.br` e `camara.leg.br`, o `<div>` que envolve
   **todo o conteúdo do `<body>`** (não só o menu) se chama
   `navigation-menu__wrapper` / `js-mmenu-container` — um padrão comum de
   temas que envolvem a página toda num wrapper para animar o menu
   "off-canvas" ao abrir. Esse caso **não foi corrigido** (ficaria
   arriscado demais tentar um patch específico sem generalizar mal para
   outros casos) — nesses 2 domínios a heurística B retorna vazio para
   aquela URL específica, mas `trafilatura` (A) extraiu normalmente.

O padrão geral: escrever um extrator por heurística de classe/id é viável e
chega a funcionar na maioria dos casos, mas tem risco real e recorrente de
falso positivo grave (apagar o artigo inteiro) porque frameworks de CSS
usam os mesmos termos (`share`, `paywall`, `menu`) tanto para os widgets
que a heurística realmente quer remover quanto para wrappers estruturais
que envolvem o conteúdo de verdade. `trafilatura` não sofreu nenhum desses
3 problemas nos mesmos HTMLs.

---

## Domínios bloqueados (falha de download, não de extração)

| Domínio | Sintoma | URLs testadas | Nota |
|---|---|---|---|
| `uol.com.br` | HTTP 403 em todas | 3/3 | Bloqueio consistente mesmo com UA de navegador real; `noticias.uol.com.br` e `economia.uol.com.br` ambos bloqueiam. |
| `espn.com.br` | HTTP 202 com corpo vazio | 2/2 | Também aconteceu na homepage e em seções — parece challenge/bot-detection que retorna 202 "aceito, processando" sem nunca servir o HTML real a esse User-Agent. |
| `reuters.com` | HTTP 401 em todas as seções testadas | 2/2 | Bloqueio tão agressivo que o **próprio buscador web usado para achar URLs candidatas recusou indexar o domínio** ("not accessible to our user agent") — não foi possível nem descobrir uma URL de artigo individual para testar. |
| `ibge.gov.br` | HTTP 403 nas duas URLs de `agenciadenoticias.ibge.gov.br` | 2/2 | A homepage do mesmo host respondeu 200 normalmente durante a descoberta de URLs; o bloqueio 403 apareceu especificamente nas páginas de artigo (`/agencia-noticias/.../noticias/NNNNN-...`). |

Nenhum desses 4 domínios teve problema de **qualidade de extração** —
simplesmente não foi possível baixar o HTML com uma requisição HTTP simples
e User-Agent de navegador. `camara.leg.br` teve **uma** URL com HTTP 500
intermitente (a mesma URL respondeu 200 numa checagem manual isolada minutos
antes) — tratado como instabilidade pontual do servidor, não bloqueio de
bot, já que as outras 2 URLs do domínio funcionaram normalmente.

---

## Percentual de domínios utilizáveis

**30/34 = 88%** dos domínios da allowlist tiveram pelo menos uma URL com
extração limpa, ≥200 caracteres, sem paywall e sem indício de dependência
de JS, usando só HTML estático via `requests`.

Nenhuma URL baixada com sucesso (86/96) ficou abaixo de 200 caracteres ou
saiu claramente poluída com menu/ads/relacionados — a "qualidade" da
extração em si não foi o fator limitante neste teste; o download em si (bot
blocking) foi.

**Ressalva sobre paywall/JS:** nenhuma das 96 URLs testadas disparou os
sinais de paywall ou dependência de JS deste spike — mas isso reflete a
amostra pequena (2-3 URLs por domínio, todas de matérias abertas), não uma
garantia de que `valor.globo.com` ou `estadao.com.br` (ambos com paywall
conhecido em parte do conteúdo) nunca terão artigo bloqueado no app real.
O comportamento por-artigo (parte aberta, parte paga) não foi coberto aqui.

---

## Recomendação final

**Viável seguir com extração de HTML estático para a maioria dos
domínios da allowlist.** O risco do §7.2 ("extração de texto principal
falhar em muitos sites") **não se materializou como problema de
extração** — nos 86/96 downloads bem-sucedidos, texto limpo e suficiente
saiu praticamente sempre, com as duas abordagens testadas. O risco real e
concreto que **apareceu** foi bloqueio de scraping (bot detection) em 4
domínios específicos: `uol.com.br`, `espn.com.br`, `reuters.com`,
`ibge.gov.br`.

Recomendação (não decisão): **reavaliar esses 4 domínios** — não
necessariamente removê-los da allowlist (RF-03.6 trata a allowlist como
lista de confiança editorial, e um app real poderia usar headers mais
elaborados, retries, ou aceitar que a fonte simplesmente falhe silenciosa
em runtime como as demais fontes de uma busca), mas ter clareza de que,
tal como testado aqui, essas 4 fontes não contribuem artigo nenhum ao
pipeline RF-04/RF-05. `camara.leg.br` também merece nota por ter mostrado
um HTTP 500 intermitente numa das 3 URLs — não bloqueio, mas instabilidade
que pode gerar falha ocasional em runtime.

---

## O que este spike NÃO fez

- **Não decide a biblioteca Swift final.** `trafilatura` venceu em Python,
  mas a escolha real do app (SwiftSoup + heurística própria, porte de
  Readability, outra lib) é decisão posterior — este spike só valida que
  extração de texto principal em HTML estático é **viável** para a
  allowlist, não qual implementação Swift usar.
- **Não implementa nada do app principal.** Nenhum arquivo em
  `Minotaur-s/Minotaur-s/` ou `.xcodeproj` foi tocado.
- **Não avança para scraping via DuckDuckGo.** Todas as URLs foram
  descobertas por link direto da homepage/seção de cada site ou por busca
  web (para achar candidatos), nunca simulando o fluxo de busca do
  RF-02/RF-03 do app. Esse é o spike da seção 7.4, item 4 ("estabilidade
  do scraping do DDG"), ainda pendente.
- **Não remove nada de `trustedDomains`.** Os 4 domínios problemáticos
  são citados como recomendação de reavaliação, não removidos do arquivo
  fonte da allowlist nem de `Verificador.swift`.
- **Não testa comportamento real de paywall parcial** (artigo com preview
  aberto + resto bloqueado) nem sites que variam entre HTML estático e
  renderização client-side dependendo da rota — a amostra de 2-3 URLs por
  domínio não cobre esses casos, só o caso feliz de artigo totalmente
  aberto.
- **Não versiona o HTML baixado** (36 MB em 86 arquivos — grande demais
  para o repo). Fica em `spikes/03-extracao-texto/html/`, ignorado via
  `.gitignore` local do spike. Reproduzível rodando `download.py` — os
  artigos podem ter mudado ou saído do ar desde a coleta (2026-07-24), mas
  o `download_manifest.json` e `results.json` já commitados preservam os
  números e o texto extraído desta rodada.

---

## Como reproduzir

```bash
cd spikes/03-extracao-texto
python3 -m venv .venv && source .venv/bin/activate
pip install requests beautifulsoup4 lxml trafilatura
python download.py    # baixa os 96 HTMLs -> download_manifest.json
python compare.py     # roda as 2 abordagens -> results.json, results.md
python report_table.py  # tabela markdown completa -> table_full.md
```

Scripts: [`urls.py`](./urls.py) (URLs testadas, com notas por domínio
problemático), [`domains.py`](./domains.py) (seeds usadas para descoberta),
[`discover_urls.py`](./discover_urls.py) e [`probe.py`](./probe.py)
(descoberta de URLs reais), [`download.py`](./download.py),
[`extract_a_trafilatura.py`](./extract_a_trafilatura.py),
[`extract_b_heuristic.py`](./extract_b_heuristic.py),
[`compare.py`](./compare.py), [`report_table.py`](./report_table.py).
