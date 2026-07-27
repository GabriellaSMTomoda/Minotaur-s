//
//  SearchQueryBuilderTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Testing
@testable import Minotaur_s

/// RF-02.1 / RF-02.2 / DT-22 — primeira frase, truncada em 200 caracteres.
struct SearchQueryBuilderTests {

    @Test("Afirmação de uma frase curta passa inalterada")
    func singleShortSentence() {
        let claim = "O governo anunciou um novo programa de habitação."
        #expect(SearchQueryBuilder.query(from: claim) == claim)
    }

    @Test("Só a primeira frase é usada")
    func onlyFirstSentence() {
        let claim = """
        A taxa de desemprego caiu para 6,2% no trimestre. \
        Esse é o menor patamar da série histórica. \
        O IBGE divulgou os dados nesta quinta.
        """
        let query = SearchQueryBuilder.query(from: claim)

        #expect(query == "A taxa de desemprego caiu para 6,2% no trimestre.")
        #expect(!query.contains("IBGE"))
    }

    @Test("Query nunca passa de 200 caracteres")
    func neverExceedsLimit() {
        // Frase única de mais de 200 caracteres: a segmentação não ajuda, quem corta é o
        // truncamento.
        let claim = String(repeating: "palavra ", count: 60) + "final."
        let query = SearchQueryBuilder.query(from: claim)

        #expect(query.count <= SearchQueryBuilder.maxQueryLength)
        #expect(!query.isEmpty)
    }

    @Test("Truncamento não parte palavra ao meio")
    func truncationRespectsWordBoundary() {
        // 199 caracteres de "ab " repetido, depois uma palavra longa que cruza o limite.
        let claim = String(repeating: "ab ", count: 66) + "presidenteDaRepublica coisa."
        let query = SearchQueryBuilder.query(from: claim)

        #expect(query.count <= SearchQueryBuilder.maxQueryLength)
        // O fragmento cortado no meio ("presidenteDaR...") não pode sobrar: ou a palavra
        // inteira cabe, ou ela fica de fora.
        #expect(!query.hasSuffix("presidenteDaR"))
        #expect(query.last != " ")
    }

    @Test("Palavra única maior que o limite ainda é cortada")
    func singleOversizedWord() {
        let claim = String(repeating: "a", count: 400)
        let query = SearchQueryBuilder.query(from: claim)

        #expect(query.count == SearchQueryBuilder.maxQueryLength)
    }

    @Test("Texto sem pontuação de fim vira frase única")
    func textWithoutPunctuation() {
        let claim = "governo anuncia programa de habitação popular para 2027"
        #expect(SearchQueryBuilder.query(from: claim) == claim)
    }

    @Test("Espaços em volta são descartados")
    func trimsWhitespace() {
        #expect(SearchQueryBuilder.query(from: "   O dólar fechou em alta.  ")
                == "O dólar fechou em alta.")
    }

    @Test("Entrada vazia ou só espaços devolve string vazia")
    func emptyInput() {
        #expect(SearchQueryBuilder.query(from: "").isEmpty)
        #expect(SearchQueryBuilder.query(from: "    \n  ").isEmpty)
    }
}
