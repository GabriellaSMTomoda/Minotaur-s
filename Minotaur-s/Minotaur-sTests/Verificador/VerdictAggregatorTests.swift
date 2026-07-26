//
//  VerdictAggregatorTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Testing
@testable import Minotaur_s

/// RF-08.1 / RF-08.3 / DT-26 — tabela-verdade completa da agregação.
struct VerdictAggregatorTests {

    private func source(_ label: NLILabel, confidence: Double = 0.9) -> SourceResult {
        SourceResult(
            url: "https://g1.globo.com/artigo",
            domain: "g1.globo.com",
            title: "Título",
            label: label,
            confidence: confidence,
            similarity: 0.5,
            excerpt: "trecho"
        )
    }

    // MARK: - Ausência de fonte

    @Test("Nenhuma fonte analisada → NÃO ENCONTRADO")
    func noSources() {
        #expect(VerdictAggregator.verdict(for: []) == .naoEncontrado)
    }

    // MARK: - Neutro não vota

    @Test("Todas neutras → SEM INFORMAÇÃO, não NÃO ENCONTRADO")
    func allNeutral() {
        let sources = [source(.neutral), source(.neutral), source(.neutral)]
        // A distinção importa para o usuário: houve fonte, ela só não fala do assunto.
        #expect(VerdictAggregator.verdict(for: sources) == .semInformacao)
    }

    @Test("Neutros não diluem a maioria")
    func neutralDoesNotVote() {
        // E=1, C=0, mais 4 neutros. Se neutro votasse, isso não seria maioria de entailment.
        let sources = [source(.entailment)] + Array(repeating: source(.neutral), count: 4)
        #expect(VerdictAggregator.verdict(for: sources) == .confirmado)
    }

    // MARK: - E vs. C

    @Test("E > C → CONFIRMADO")
    func entailmentWins() {
        let sources = [source(.entailment), source(.entailment), source(.contradiction)]
        #expect(VerdictAggregator.verdict(for: sources) == .confirmado)
    }

    @Test("C > E → CONTRADITO")
    func contradictionWins() {
        let sources = [source(.contradiction), source(.contradiction), source(.entailment)]
        #expect(VerdictAggregator.verdict(for: sources) == .contradito)
    }

    @Test("E = C > 0 → DIVERGENTE")
    func tieIsDivergent() {
        let sources = [source(.entailment), source(.contradiction)]
        #expect(VerdictAggregator.verdict(for: sources) == .divergente)
    }

    @Test("Empate com neutros no meio continua DIVERGENTE")
    func tieWithNeutrals() {
        let sources = [source(.entailment), source(.neutral),
                       source(.contradiction), source(.neutral)]
        #expect(VerdictAggregator.verdict(for: sources) == .divergente)
    }

    // MARK: - Sem piso mínimo de fontes (decisão de produto explícita, DT-26)

    @Test("1 fonte entailment já basta para CONFIRMADO")
    func singleEntailmentSource() {
        #expect(VerdictAggregator.verdict(for: [source(.entailment)]) == .confirmado)
    }

    @Test("1 fonte contradiction já basta para CONTRADITO")
    func singleContradictionSource() {
        #expect(VerdictAggregator.verdict(for: [source(.contradiction)]) == .contradito)
    }

    @Test("1 fonte neutra → SEM INFORMAÇÃO")
    func singleNeutralSource() {
        #expect(VerdictAggregator.verdict(for: [source(.neutral)]) == .semInformacao)
    }

    // MARK: - Trava de evidência

    @Test("Veredito decisivo sempre tem fonte com trecho exibível")
    func decisiveVerdictAlwaysHasEvidence() {
        // A trava "decisivo exige evidência exibida" é satisfeita por construção: um veredito
        // confirmado/contradito exige E>0 ou C>0, e toda fonte carrega excerpt e link
        // (RF-09.2/09.4). Este teste fixa a propriedade para que ninguém a quebre depois
        // fazendo o agregador decidir sem fonte direcional.
        for verdict in [Verdict.confirmado, .contradito, .divergente] {
            let sources: [SourceResult]
            switch verdict {
            case .confirmado: sources = [source(.entailment)]
            case .contradito: sources = [source(.contradiction)]
            default: sources = [source(.entailment), source(.contradiction)]
            }

            #expect(VerdictAggregator.verdict(for: sources) == verdict)
            let directional = sources.filter { $0.label != .neutral }
            #expect(!directional.isEmpty)
            #expect(directional.allSatisfy { !$0.excerpt.isEmpty && !$0.url.isEmpty })
        }
    }
}
