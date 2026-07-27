//
//  AllowlistFilterTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// RF-03.1 / RF-03.5 / DT-20 / DT-28 / CA-04.
struct AllowlistFilterTests {

    // MARK: - CA-04: resultado fora da allowlist é descartado

    @Test("Domínio fora da allowlist é descartado")
    func rejectsOutsideDomain() {
        // Os dois casos reais de vazamento medidos no Spike 5.
        #expect(!AllowlistFilter.isAllowed(urlString: "https://pt.wikipedia.org/wiki/Brasil"))
        #expect(!AllowlistFilter.isAllowed(urlString: "https://www.dicio.com.br/inflacao/"))
    }

    @Test("Domínio da allowlist é aceito")
    func acceptsListedDomain() {
        #expect(AllowlistFilter.isAllowed(urlString: "https://g1.globo.com/politica/noticia"))
    }

    @Test("String que não é URL absoluta é descartada")
    func rejectsMalformedURL() {
        #expect(!AllowlistFilter.isAllowed(urlString: "não é uma url"))
        #expect(!AllowlistFilter.isAllowed(urlString: "/caminho/relativo"))
    }

    // MARK: - Correspondência por sufixo (DT-20)

    @Test("Subdomínio de domínio confiável é aceito")
    func acceptsSubdomain() {
        #expect(AllowlistFilter.isAllowed(urlString: "https://www1.folha.uol.com.br/poder/"))
        // DT-20: qualquer *.gov.br passa, inclusive prefeitura, por decisão consciente.
        #expect(AllowlistFilter.isAllowed(urlString: "https://ilhabela.sp.gov.br/noticia"))
    }

    @Test("Sufixo não casa sem o ponto separador")
    func suffixRequiresDotBoundary() {
        // Sem o ponto na comparação, "evilgov.br" casaria com "gov.br".
        #expect(!AllowlistFilter.isAllowed(urlString: "https://evilgov.br/fake"))
        #expect(!AllowlistFilter.isAllowed(urlString: "https://naoeg1.globo.com.br/x"))
    }

    // MARK: - DT-28: hosts corrigidos, com e sem www

    @Test("Entradas com www casam com e sem o prefixo", arguments: [
        "https://www.band.com.br/noticias/materia",
        "https://band.com.br/noticias/materia",
        "https://www.agencialupa.org/checagem",
        "https://agencialupa.org/checagem",
    ])
    func wwwNormalizedBothWays(urlString: String) {
        // O valor gravado na allowlist é o host real (www.band.com.br), mas o casamento
        // ignora o prefixo — senão o host sem www seria descartado, que é o mesmo bug de
        // correspondência que a DT-28 veio corrigir.
        #expect(AllowlistFilter.isAllowed(urlString: urlString))
    }

    @Test("Hosts corrigidos pela DT-28 são reconhecidos", arguments: [
        "https://gauchazh.clicrbs.com.br/politica/noticia",
        "https://agenciagov.ebc.com.br/noticias/materia",
    ])
    func correctedHosts(urlString: String) {
        #expect(AllowlistFilter.isAllowed(urlString: urlString))
    }

    @Test("Hosts antigos e errados não voltam por acaso")
    func oldBrokenHostsAreGone() {
        // Estes nunca serviram conteúdo — era o bug que a DT-28 corrigiu. Se voltarem à
        // allowlist, o filtro passa a aceitar host que não existe.
        #expect(!TrustedDomain.allowlist.contains("band.uol.com.br"))
        #expect(!TrustedDomain.allowlist.contains("lupa.uol.com.br"))
        #expect(!TrustedDomain.allowlist.contains("gzh.com.br"))
    }

    @Test("Domínios removidos por bot-blocking continuam fora (RF-03.1)")
    func botBlockedDomainsStayOut() {
        for domain in ["uol.com.br", "espn.com.br", "reuters.com", "ibge.gov.br"] {
            #expect(!TrustedDomain.allowlist.contains(domain))
        }
        // `uol.com.br` fora da lista não pode derrubar folha.uol.com.br, que está nela.
        #expect(AllowlistFilter.isAllowed(urlString: "https://folha.uol.com.br/poder/x"))
        #expect(!AllowlistFilter.isAllowed(urlString: "https://economia.uol.com.br/x"))
    }

    @Test("30 veículos em 31 entradas")
    func allowlistSize() {
        // A entrada extra é agenciagov.ebc.com.br, que não casa por sufixo com gov.br nem
        // com agenciabrasil.ebc.com.br (DT-28).
        #expect(TrustedDomain.allowlist.count == 31)
    }

    // MARK: - Domínio reportado (RF-03.3 / RF-09.6)

    @Test("Correspondência mais específica vence")
    func mostSpecificMatchWins() {
        // folha.uol.com.br e uol.com.br poderiam ambos casar; só o específico está na lista.
        #expect(AllowlistFilter.matchedDomain(forHost: "www1.folha.uol.com.br")
                == "folha.uol.com.br")
    }

    // MARK: - Ordem filtrar → truncar (RF-03.5 seguido de RF-04.3)

    @Test("Filtra por allowlist antes de truncar em 5")
    func filtersBeforeTruncating() {
        // Cenário do Spike 5: os primeiros resultados vazam, os válidos vêm depois. Truncar
        // antes de filtrar devolveria 1 fonte; filtrar antes devolve 5.
        let leaked = (1...5).map { url("https://pt.wikipedia.org/wiki/\($0)") }
        let valid = [
            url("https://g1.globo.com/1"),
            url("https://estadao.com.br/2"),
            url("https://bbc.com/3"),
            url("https://exame.com/4"),
            url("https://r7.com/5"),
        ]

        let filtered = AllowlistFilter.filter(leaked + valid, url: \.resolvedURL)

        #expect(filtered.count == 5)
        #expect(filtered.allSatisfy { !$0.url.contains("wikipedia") })
    }

    @Test("Ordem de ranking original é preservada")
    func preservesRanking() {
        let items = [
            url("https://g1.globo.com/primeiro"),
            url("https://pt.wikipedia.org/vazado"),
            url("https://bbc.com/segundo"),
        ]
        let filtered = AllowlistFilter.filter(items, url: \.resolvedURL)

        #expect(filtered.map(\.url) == ["https://g1.globo.com/primeiro", "https://bbc.com/segundo"])
    }

    private func url(_ string: String) -> SearchResultItem {
        SearchResultItem(title: "t", url: string, content: "c", score: 0.5)
    }
}
