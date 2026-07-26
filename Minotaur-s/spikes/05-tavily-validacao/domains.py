"""
Allowlist atual (pós Tarefa 1 — 4 domínios removidos por bot-blocking
detectado no Spike 3: uol.com.br, espn.com.br, reuters.com, ibge.gov.br).
Copiada de Minotaur-s/Minotaur-s/Views/Verificador.swift (trustedDomains).
"""

TRUSTED_DOMAINS = [
    "g1.globo.com",
    "oglobo.globo.com",
    "folha.uol.com.br",
    "estadao.com.br",
    "cnnbrasil.com.br",
    "veja.abril.com.br",
    "valor.globo.com",
    "exame.com",
    "r7.com",
    "terra.com.br",
    "metropoles.com",
    "poder360.com.br",
    "gzh.com.br",
    "correiobraziliense.com.br",
    "agenciabrasil.ebc.com.br",
    "otempo.com.br",
    "band.uol.com.br",
    "ge.globo.com",
    "aosfatos.org",
    "lupa.uol.com.br",
    "bbc.com",
    "dw.com",
    "elpais.com",
    "apnews.com",
    "gov.br",
    "camara.leg.br",
    "senado.leg.br",
    "stf.jus.br",
    "tse.jus.br",
    "who.int",
]

assert len(TRUSTED_DOMAINS) == 30
