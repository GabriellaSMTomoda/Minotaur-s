//
//  TrustedDomain.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Allowlist de domínios de veículos de imprensa considerados confiáveis para a
/// feature "Verificar Notícia". Conteúdo migrado de `VerificadorView.trustedDomains`
/// (RF-03.1), movido para fora da camada de UI (RF-03.6).
/// Nesta fase a lista é estática: não editável em runtime, não atualizada remotamente (RF-03.4).
///
/// **30 veículos, 31 entradas** (DT-28). O número de strings é maior que o de veículos
/// porque a Agência Gov é servida em `agenciagov.ebc.com.br`, que não casa por sufixo nem
/// com `gov.br` nem com a entrada vizinha `agenciabrasil.ebc.com.br` — precisa de entrada
/// própria. Nenhum veículo foi adicionado ou removido nesta correção.
struct TrustedDomain {
    private init() {}

    /// Domínios enviados em `include_domains` na chamada de busca (RF-02.3) e usados pelo
    /// `AllowlistFilter` para descartar o que vazar (RF-03.5).
    ///
    /// Os valores são o **host real que serve o conteúdo**. Quatro entradas foram corrigidas
    /// na Fase 3 (DT-28) porque o valor antigo nunca casaria — não é nova curadoria, é
    /// correção de bug de correspondência que impedia essas fontes de retornar artigo algum.
    /// O prefixo `www.` de duas delas é intencional (é o host real); o casamento local
    /// ignora esse prefixo, ver `AllowlistFilter.matchedDomain(forHost:)`.
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
        "gauchazh.clicrbs.com.br",   // DT-28: era "gzh.com.br"
        "correiobraziliense.com.br",
        "agenciabrasil.ebc.com.br",
        "otempo.com.br",
        "www.band.com.br",           // DT-28: era "band.uol.com.br"
        "ge.globo.com",
        "aosfatos.org",
        "www.agencialupa.org",       // DT-28: era "lupa.uol.com.br"
        "bbc.com",
        "dw.com",
        "elpais.com",
        "apnews.com",
        "gov.br",                    // validação por sufixo, inclui órgãos menores (DT-20)
        "agenciagov.ebc.com.br",     // DT-28: host real da Agência Gov, não coberto por "gov.br"
        "camara.leg.br",
        "senado.leg.br",
        "stf.jus.br",
        "tse.jus.br",
        "who.int"
    ]
}
