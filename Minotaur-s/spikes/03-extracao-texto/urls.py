"""
URLs reais de artigo/notícia por domínio, curadas manualmente a partir de
`discover_urls.py` (extração automática de links da homepage) + `probe.py`
(inspeção manual de seções quando a homepage só trazia links de
categoria/hub) + busca web (para os poucos domínios cuja listagem de notícias
é renderizada via JS, ou que bloqueiam requisição direta).

Todas as URLs foram conferidas manualmente antes de entrar aqui — nenhuma foi
inventada. Datas em torno de 2026-07 (data corrente do ambiente: 2026-07-24).

Congelado nesta rodada do spike: novas execuções de download.py usam este
arquivo, não regeram URLs a cada vez (para o spike ser reprodutível).

Notas por domínio problemático (documentadas também no RESULTADO.md):
- gzh.com.br: o próprio domínio redireciona (HTTP redirect) para
  gauchazh.clicrbs.com.br. É o comportamento real do site, não um erro do
  spike — URLs finais usam o domínio de destino.
- lupa.uol.com.br: redireciona para agencialupa.org (rebranding editorial de
  "Agência Lupa" -> "Agência Pública"? na prática hoje é agencialupa.org).
- gov.br: a seção /pt-br/noticias linka para agenciagov.ebc.com.br (Agência
  Gov, parte do grupo EBC) como fonte real das notícias.
- stf.jus.br: o host documentado como "portal.stf.jus.br/noticias/" deu erro
  de certificado SSL; o site de notícias de fato é noticias.stf.jus.br.
- dw.com: a seed original (/pt-br/brasil/s-1431) não existe mais (404); usada
  a home pt-br para achar artigos reais.
- reuters.com: bloqueia requisição HTTP direta (401 Forbidden) mesmo em
  páginas de seção, e o próprio buscador web usado para achar candidatos
  reportou o domínio como inacessível a user-agents automatizados. Nenhuma
  URL de artigo pôde ser confirmada por navegação real — registrado como
  bloqueio de origem, não como falha do spike. Duas URLs de seção mantidas
  aqui só para o download.py registrar o erro de forma explícita.
- espn.com.br: toda requisição (seed e artigos) retornou HTTP 202 com corpo
  vazio (bot-challenge). URLs de artigo reais foram achadas via busca web
  (não por link direto), mantidas para registrar o mesmo bloqueio.
"""

URLS = {
    "g1.globo.com": [
        "https://g1.globo.com/politica/blog/valdo-cruz/post/2026/07/24/governo-lula-atuou-para-convencer-federacao-pp-uniao-brasil-a-ficar-neutra-e-nao-apoiar-flavio-bolsonaro.ghtml",
        "https://g1.globo.com/politica/blog/natuza-nery/post/2026/07/24/crise-michelle-flavio-bolsonaro-video-juntos.ghtml",
        "https://g1.globo.com/economia/noticia/2026/07/24/durigan-expert-xp.ghtml",
    ],
    "oglobo.globo.com": [
        "https://oglobo.globo.com/brasil/noticia/2026/07/24/foie-gras-lula-sanciona-lei-e-o-brasil-torna-se-o-segundo-pais-da-america-latina-a-banir-integralmente-o-produto.ghtml",
        "https://oglobo.globo.com/brasil/noticia/2026/07/24/governo-sanciona-lei-que-autoriza-mulheres-a-comprarem-spray-de-pimenta-para-defesa-pessoal.ghtml",
        "https://oglobo.globo.com/brasil/noticia/2026/07/23/igreja-presbiteriana-unida-aprova-inclusao-de-pessoas-lgbtqiapn-como-membros-e-pastores.ghtml",
    ],
    "uol.com.br": [
        "https://noticias.uol.com.br/colunas/josias-de-souza/2026/07/24/reina-a-paz-entre-flavio-e-sua-madrasta-ate-a-proxima-briga.htm",
        "https://economia.uol.com.br/noticias/redacao/2026/07/24/o-que-muda-com-a-nova-ferramenta-do-uol-que-reune-pesquisas-eleitorais.htm",
        "https://noticias.uol.com.br/colunas/carlos-madeiro/2026/07/24/pi-homem-movimenta-r-600-mi-zera-conta-e-culpa-perda-em-bolsa-por-calote.htm",
    ],
    "folha.uol.com.br": [
        "https://www1.folha.uol.com.br/colunas/adriana-fernandes/2026/07/a-contencao-dos-bolsonaros.shtml",
        "https://www1.folha.uol.com.br/colunas/conrado-hubner-mendes/2026/07/tse-propoe-selo-maria-vai-com-as-urnas.shtml",
        "https://www1.folha.uol.com.br/blogs/brasilia-hoje/2026/07/aliados-de-lula-exploram-investigacao-de-dinheiro-de-vorcaro-a-dark-horse-para-atacar-flavio.shtml",
    ],
    "estadao.com.br": [
        "https://www.estadao.com.br/brasil/laco-de-cv-e-deputado-do-rio-mostra-ser-urgente-tirar-da-politica-os-condenados-por-crime-organizado/",
        "https://www.estadao.com.br/politica/blog-do-fausto-macedo/pgr-denuncia-desembargador-th-joias-e-ex-presidente-da-assembleia-do-rio-em-investigacao-sobre-o-cv/",
        "https://www.estadao.com.br/brasil/de-agencia-antimafia-a-fast-track-de-processos-veja-propostas-para-combater-avanco-de-pcc-e-cv/",
    ],
    "cnnbrasil.com.br": [
        "https://www.cnnbrasil.com.br/internacional/israel-prepara-grande-operacao-militar-na-cisjordania-apos-mortes/",
        "https://www.cnnbrasil.com.br/internacional/ira-diz-que-ataque-dos-eua-teve-quartel-da-guarda-revolucionaria-como-alvo/",
        "https://www.cnnbrasil.com.br/internacional/navios-sauditas-passam-por-bab-el-mandeb-apesar-de-ameacas-dos-houthis/",
    ],
    "veja.abril.com.br": [
        "https://veja.abril.com.br/brasil/brasileiras-ja-podem-comprar-spray-de-pimenta-para-defesa-pessoal/",
        "https://veja.abril.com.br/brasil/ex-prefeito-e-esposa-sao-favoritos-contra-aliados-de-lula-e-alcolumbre-no-amapa-diz-pesquisa/",
        "https://veja.abril.com.br/brasil/inqueritos-contra-autoridades-explodem-no-stj-apos-mudanca-da-regra-do-foro-no-supremo/",
    ],
    "valor.globo.com": [
        "https://valor.globo.com/brasil/noticia/2026/07/24/consumo-sustentou-economia-do-brasil-diz-fmi.ghtml",
        "https://valor.globo.com/brasil/noticia/2026/07/24/eua-confirmam-tarifa-por-trabalho-forcado.ghtml",
        "https://valor.globo.com/brasil/noticia/2026/07/23/fiscal-preocupa-mas-dimensao-do-problema-divide-economistas.ghtml",
    ],
    "exame.com": [
        "https://exame.com/invest/mercados/sete-magnificas-perdem-r-45-tri-em-um-dia-com-temor-por-gastos-em-ia/",
        "https://exame.com/invest/mercados/ibovespa-volta-a-cair-com-pressao-de-vale-petrobras-e-bancos/",
        "https://exame.com/invest/mercados/petroleo-e-juros-por-que-a-estagflacao-voltou-a-preocupar-o-mercado/",
    ],
    "r7.com": [
        "https://noticias.r7.com/economia/piora-o-que-ja-estava-ruim-afirma-setor-de-calcados-sobre-nova-tarifa-dos-eua-24072026",
        "https://noticias.r7.com/economia/receita-abre-consulta-ao-terceiro-lote-de-restituicao-do-irpf-2026-nesta-sexta-feira-24-24072026",
        "https://noticias.r7.com/economia/vai-ter-impacto-no-emprego-e-na-renda-diz-economista-sobre-setores-afetados-por-tarifaco-24072026",
    ],
    "terra.com.br": [
        "https://www.terra.com.br/noticias/brasil/acidente-da-voepass-o-que-causou-a-queda-do-aviao-em-sp,dad0d28e8c1bbd1a824b30aa4551fb49ivdtnkne.html",
        "https://www.terra.com.br/noticias/brasil/brasil-e-o-maior-perdedor-das-tarifas-adicionais-de-trump-diz-financial-times,2e5d09810020221b3ac3ab20f7d45551glwlutoo.html",
        "https://www.terra.com.br/economia/governo-lula-diminui-bloqueio-no-orcamento-e-libera-r-57-bilhoes-em-gastos-na-vespera-de-campanha,bba6831dc04e52c1d4256172cff557bfphvfbve9.html",
    ],
    "metropoles.com": [
        "https://www.metropoles.com/brasil/apos-tarifaco-lula-fala-em-nao-deixar-ninguem-meter-o-nariz-no-pais",
        "https://www.metropoles.com/brasil/produtos-brasileiros-serao-taxados-em-ate-375-a-partir-desta-6a-veja-lista",
        "https://www.metropoles.com/brasil/governo-lula-reage-a-nova-tarifa-e-promete-acionar-reciprocidade",
    ],
    "poder360.com.br": [
        "https://www.poder360.com.br/poder-economia/jbs-mira-expansao-global-com-listagem-nos-eua-e-aquisicao-em-oma/",
        "https://www.poder360.com.br/poder-governo/so-vou-falar-do-tarifaco-quando-trump-falar-diz-lula/",
        "https://www.poder360.com.br/poder-economia/saiba-quais-indicadores-internacionais-saem-nesta-semana-15/",
    ],
    "gzh.com.br": [
        "https://gauchazh.clicrbs.com.br/viral/noticia/2026/07/joao-gomes-cancela-shows-apos-ser-hospitalizado-com-influenza-cmrz4oac601sg014crnxsl3md.html",
        "https://gauchazh.clicrbs.com.br/colunistas/gisele-loeblein/noticia/2026/07/brasil-proibe-foie-gras-e-franca-reage-entenda-a-disputa-por-tras-da-iguaria-de-luxo-cmrza1zq501wa0163q6yjjuq9.html",
    ],
    "correiobraziliense.com.br": [
        "https://www.correiobraziliense.com.br/politica/2026/07/7467410-pp-opta-pela-neutralidade-nacional-e-libera-palanques-para-eleicoes.html",
        "https://www.correiobraziliense.com.br/brasil/2026/07/7467405-mulheres-ja-podem-comprar-spray-de-pimenta-para-defesa-pessoal-veja-regras.html",
        "https://www.correiobraziliense.com.br/brasil/2026/07/7467426-alem-do-spray-4-itens-de-defesa-pessoal-permitidos-por-lei-no-pais.html",
    ],
    "agenciabrasil.ebc.com.br": [
        "https://agenciabrasil.ebc.com.br/economia/noticia/2026-07/eua-impoem-nova-tarifa-de-125-produtos-brasileiros",
        "https://agenciabrasil.ebc.com.br/economia/noticia/2026-07/ministro-chama-tarifa-dos-eua-de-indevida-e-promete-reacao",
        "https://agenciabrasil.ebc.com.br/economia/noticia/2026-07/estados-unidos-isentam-471-produtos-de-nova-tarifa-de-125",
    ],
    "otempo.com.br": [
        "https://www.otempo.com.br/politica/2026/7/24/dataprev-formaliza-reajuste-em-contrato-de-tecnologia-com-a-teletex",
        "https://www.otempo.com.br/politica/governo/2026/7/14/na-vespera-de-decisao-governo-lula-faz-reuniao-com-eua-e-fala-em-carater-injusto-de-tarifas",
        "https://www.otempo.com.br/cidades/2026/7/24/justica-decide-na-proxima-quarta-se-acusado-de-matar-sargento-roger-dias-ira-a-juri-popular",
    ],
    "band.uol.com.br": [
        "https://www.band.com.br/noticias/justica-decreta-prisao-preventiva-de-homem-que-atropelou-e-matou-pm-em-sp-202607241436",
        "https://www.band.com.br/noticias/entenda-o-que-esta-por-tras-do-acordo-nuclear-entre-eua-e-arabia-saudita-202607241419",
        "https://www.band.com.br/economia/noticias/tarifaco-de-trump-veja-como-os-paises-reagiram-a-nova-sobretaxa-de-ate-125-imposta-pelos-eua-202607241157",
    ],
    "ge.globo.com": [
        "https://ge.globo.com/futebol/times/cruzeiro/noticia/2026/07/24/cruzeiro-vai-contratar-substituto-de-gabriel-pec-entenda-planos.ghtml",
        "https://ge.globo.com/futebol/copa-do-mundo/noticia/2026/06/12/copa-do-mundo-2026-veja-ranking-de-artilheiros-e-garcons.ghtml",
        "https://ge.globo.com/gato-mestre/dicas/noticia/2026/07/24/palpites-e-dicas-para-bahia-x-corinthians-pelo-brasileirao.ghtml",
    ],
    "espn.com.br": [
        "https://www.espn.com.br/futebol/sao-paulo/artigo/_/id/16096849/sao-paulo-acerta-negociacao-tripla-com-river-plate-e-encaminha-novidades-para-2026",
        "https://www.espn.com.br/futebol/copa-do-mundo/artigo/_/id/16551330/copa-do-mundo-tera-nove-representantes-arbitragem-brasil-veja-nomes",
    ],
    "aosfatos.org": [
        "https://aosfatos.org/noticias/brastemp-consul-fabrica-brasil/",
        "https://aosfatos.org/noticias/moraes-trump-visitar-bolsonaro/",
        "https://aosfatos.org/noticias/governo-idade-minima-aposentadoria/",
    ],
    "lupa.uol.com.br": [
        "https://www.agencialupa.org/noticias/2026/07/21/e-falso-que-luciano-hang-anunciou-plataforma-que-rende-ate-r-220-mil-por-mes/",
        "https://www.agencialupa.org/verificacao/2026/07/02/e-golpe-site-que-simula-plataforma-de-investimento-da-petrobras/",
        "https://www.agencialupa.org/institucional/2026/07/21/aqui-nao-tem-propaganda-de-bets/",
    ],
    "bbc.com": [
        "https://www.bbc.com/portuguese/articles/c75yy56153xo",
        "https://www.bbc.com/portuguese/articles/c8rn582102vo",
        "https://www.bbc.com/portuguese/articles/cz64le56412o",
    ],
    "dw.com": [
        "https://www.dw.com/pt-br/falta-de-emprego-entre-jovens-vira-desafio-global/a-78052376",
        "https://www.dw.com/pt-br/alvo-de-tarifaço-brasil-é-há-décadas-fonte-de-superávit-recorde-para-os-eua/a-78090576",
        "https://www.dw.com/pt-br/flávio-e-michelle-fazem-as-pazes-antes-de-convenção-do-pl/a-78105395",
    ],
    "elpais.com": [
        "https://elpais.com/internacional/2026-07-24/trump-impone-un-sistema-comercial-caotico-en-su-tercera-ronda-arancelaria.html",
        "https://elpais.com/internacional/2026-07-24/las-claves-de-los-nuevos-aranceles-de-trump-que-suponen-a-que-paises-afectan-y-cuando-entran-en-vigor.html",
        "https://elpais.com/internacional/2026-07-24/bruselas-recibe-con-cautela-los-nuevos-aranceles-de-trump-a-la-union-europea.html",
    ],
    "reuters.com": [
        "https://www.reuters.com/world/",
        "https://www.reuters.com/business/",
    ],
    "apnews.com": [
        "https://apnews.com/article/iran-us-hormuz-strait-war-24-july-2026-78c2dbf538f6e61ab816479a4d9bdd85",
        "https://apnews.com/article/usvi-lawsuit-guns-concealed-2nd-amendment-1039052c4389483e4be4ed23f30ef82b",
        "https://apnews.com/article/usmediatimesair-force-one-42429e4d4da8accc42b6c3ddf3f4fed5",
    ],
    "gov.br": [
        "https://agenciagov.ebc.com.br/noticias/202607/governo-brasileiro-rechaca-alegacoes-dos-eua-para-impor-nova-taxa",
        "https://agenciagov.ebc.com.br/noticias/202607/enade-2026-prazo-para-solicitar-atendimento-especializado-e-nome-social-termina-hoje-24",
        "https://agenciagov.ebc.com.br/noticias/202607/cnpj-alfanumerico-o-que-muda-para-empresas-e-empreendedores",
    ],
    "camara.leg.br": [
        "https://www.camara.leg.br/noticias/1290742-projeto-preve-avaliacao-de-risco-de-feminicidio-durante-atendimento-a-vitimas-de-violencia",
        "https://www.camara.leg.br/noticias/1285520-projeto-protege-sigilo-do-local-de-trabalho-de-servidoras-com-medida-protetiva",
        "https://www.camara.leg.br/noticias/1293099-retrospectiva-deputados-aprovaram-minirreforma-eleitoral-no-primeiro-semestre-deste-ano",
    ],
    "senado.leg.br": [
        "https://www12.senado.leg.br/noticias/materias/2026/07/24/eleicoes-o-que-e-permitido-e-o-que-e-proibido-nas-redes-sociais",
        "https://www12.senado.leg.br/noticias/materias/2026/07/24/lei-autoriza-venda-de-spray-de-pimenta-para-seguranca-das-mulheres",
    ],
    "stf.jus.br": [
        "https://noticias.stf.jus.br/postsnoticias/stf-revoga-medidas-cautelares-impostas-a-investigados-por-envolvimento-com-grupos-criminosos-violentos-no-rj",
        "https://noticias.stf.jus.br/postsnoticias/decisao-do-stf-permite-retomada-da-cobranca-de-iptu-em-teresina",
        "https://noticias.stf.jus.br/postsnoticias/rede-questiona-falta-de-responsabilizacao-de-parlamentares-por-emendas-impositivas",
    ],
    "tse.jus.br": [
        "https://www.tse.jus.br/comunicacao/noticias/2026/Julho/manual-do-eleitor-entenda-como-vai-funcionar-a-biometria-nas-eleicoes-2026",
        "https://www.tse.jus.br/comunicacao/noticias/2026/Julho/justica-eleitoral-completa-94-anos-de-atuacao-na-paraiba",
        "https://www.tse.jus.br/comunicacao/noticias/2026/Abril/justica-eleitoral-conclui-atualizacao-tecnologica-dos-portais-reforcando-modernizacao-e-seguranca",
    ],
    "ibge.gov.br": [
        "https://agenciadenoticias.ibge.gov.br/agencia-noticias/2012-agencia-de-noticias/noticias/47613-ibge-participa-da-78-reuniao-anual-da-sbpc-e-convida-publico-a-conhecer-suas-atividades",
        "https://agenciadenoticias.ibge.gov.br/agencia-noticias/2012-agencia-de-noticias/noticias/47506-cumprimento-a-legislacao-eleitoral-a-partir-de-4-de-julho",
    ],
    "who.int": [
        "https://www.who.int/news/item/02-07-2026-who-adds-first-diagnostic-test-for-ebola-bundibugyo-virus-to-its-emergency-use-listing",
        "https://www.who.int/news/item/03-02-2026-who-launches-2026-appeal-to-help-millions-of-people-in-health-emergencies-and-crisis-settings",
    ],
}

TOTAL_DOMAINS = 34
assert len(URLS) == TOTAL_DOMAINS, len(URLS)
