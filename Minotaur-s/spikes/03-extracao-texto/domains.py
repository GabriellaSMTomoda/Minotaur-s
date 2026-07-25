"""
Os 34 domínios de trustedDomains (Minotaur-s/Minotaur-s/Views/Verificador.swift,
linhas 61-96). Copiados exatamente, não reordenados nem editados.

Para os domínios institucionais/governamentais (marcados abaixo), a "homepage"
usada para descobrir URLs de artigo é uma seção de notícias/imprensa do próprio
site, não a home genérica.
"""

# domínio -> URL usada como ponto de partida para achar links de artigo/notícia
SEED_PAGES = {
    "g1.globo.com": "https://g1.globo.com/",
    "oglobo.globo.com": "https://oglobo.globo.com/",
    "uol.com.br": "https://www.uol.com.br/",
    "folha.uol.com.br": "https://www1.folha.uol.com.br/",
    "estadao.com.br": "https://www.estadao.com.br/",
    "cnnbrasil.com.br": "https://www.cnnbrasil.com.br/",
    "veja.abril.com.br": "https://veja.abril.com.br/",
    "valor.globo.com": "https://valor.globo.com/",
    "exame.com": "https://exame.com/",
    "r7.com": "https://www.r7.com/",
    "terra.com.br": "https://www.terra.com.br/noticias/",
    "metropoles.com": "https://www.metropoles.com/",
    "poder360.com.br": "https://www.poder360.com.br/",
    "gzh.com.br": "https://gauchazh.clicrbs.com.br/",
    "correiobraziliense.com.br": "https://www.correiobraziliense.com.br/",
    "agenciabrasil.ebc.com.br": "https://agenciabrasil.ebc.com.br/",
    "otempo.com.br": "https://www.otempo.com.br/",
    "band.uol.com.br": "https://www.band.uol.com.br/noticias",
    "ge.globo.com": "https://ge.globo.com/",
    "espn.com.br": "https://www.espn.com.br/",
    "aosfatos.org": "https://aosfatos.org/noticias/",
    "lupa.uol.com.br": "https://lupa.uol.com.br/",
    "bbc.com": "https://www.bbc.com/portuguese",
    "dw.com": "https://www.dw.com/pt-br/brasil/s-1431",
    "elpais.com": "https://elpais.com/america/",
    "reuters.com": "https://www.reuters.com/world/",
    "apnews.com": "https://apnews.com/",
    "gov.br": "https://www.gov.br/pt-br/noticias",
    "camara.leg.br": "https://www.camara.leg.br/noticias",
    "senado.leg.br": "https://www12.senado.leg.br/noticias",
    "stf.jus.br": "https://portal.stf.jus.br/noticias/",
    "tse.jus.br": "https://www.tse.jus.br/comunicacao/noticias",
    "ibge.gov.br": "https://agenciadenoticias.ibge.gov.br/",
    "who.int": "https://www.who.int/news-room/headlines",
}

DOMAINS = list(SEED_PAGES.keys())
assert len(DOMAINS) == 34, len(DOMAINS)
