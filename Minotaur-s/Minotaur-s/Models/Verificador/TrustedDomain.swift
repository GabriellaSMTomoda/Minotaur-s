//
//  TrustedDomain.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Allowlist de domínios de veículos de imprensa considerados confiáveis para a
/// feature "Verificar Notícia". Conteúdo migrado de `VerificadorView.trustedDomains`
/// sem alteração (RF-03.1), movido para fora da camada de UI (RF-03.6).
/// Nesta fase a lista é estática: não editável em runtime, não atualizada remotamente (RF-03.4).
struct TrustedDomain {
    private init() {}

    static let allowlist: Set<String> = [
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
        "who.int"
    ]
}
