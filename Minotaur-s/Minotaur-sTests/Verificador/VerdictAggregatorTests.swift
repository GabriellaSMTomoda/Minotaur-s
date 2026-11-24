//
//  VerdictAggregatorTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26. Rewritten for evidence v3 on 24/11/26.
//

import Testing
@testable import Minotaur_s

/// Evidence v3: each independent origin votes once; DIVERGENTE needs a real opposing side.
struct VerdictAggregatorTests {

    private func source(_ label: NLILabel, origin: String = "a", confidence: Double = 0.95,
                        domain: String = "g1.globo.com") -> SourceResult {
        SourceResult(url: "https://\(domain)/\(origin)", domain: domain, title: "Título", label: label,
                     confidence: confidence, similarity: 0.8, excerpt: "trecho", originGroup: origin)
    }

    private func passage(_ text: String, e: Double = 0.02, c: Double = 0.02, similarity: Double = 0.8) -> EvidencePassage {
        EvidencePassage(text: text, probabilities: .init(entailment: e, neutral: 1 - e - c, contradiction: c), similarity: similarity)
    }

    // MARK: - Ausência de fonte e neutros

    @Test("Nenhuma fonte analisada → NÃO ENCONTRADO")
    func noSources() {
        #expect(VerdictAggregator.verdict(for: []) == .naoEncontrado)
    }

    @Test("Todas neutras → SEM INFORMAÇÃO, não NÃO ENCONTRADO")
    func allNeutral() {
        let sources = ["a", "b", "c"].map { source(.neutral, origin: $0) }
        #expect(VerdictAggregator.verdict(for: sources) == .semInformacao)
    }

    @Test("Neutros não diluem a evidência")
    func neutralDoesNotVote() {
        let sources = [source(.entailment)] + ["b", "c", "d", "e"].map { source(.neutral, origin: $0) }
        #expect(VerdictAggregator.verdict(for: sources) == .confirmado)
    }

    // MARK: - Conflito

    @Test("Uma origem discordante não derruba duas origens concordantes")
    func dominantSideWins() {
        let sources = [source(.entailment, origin: "a"), source(.entailment, origin: "b"), source(.contradiction, origin: "c")]
        #expect(VerdictAggregator.verdict(for: sources) == .confirmado)
        let refuted = [source(.contradiction, origin: "a"), source(.contradiction, origin: "b"), source(.entailment, origin: "c")]
        #expect(VerdictAggregator.verdict(for: refuted) == .contradito)
    }

    @Test("Dois lados com várias origens e força comparável → DIVERGENTE")
    func realConflict() {
        let sources = [source(.entailment, origin: "a"), source(.entailment, origin: "b"),
                       source(.contradiction, origin: "c"), source(.contradiction, origin: "d")]
        #expect(VerdictAggregator.verdict(for: sources) == .divergente)
    }

    @Test("Empate entre fontes completas independentes → DIVERGENTE")
    func balancedTie() {
        #expect(VerdictAggregator.verdict(for: [source(.entailment, origin: "a"), source(.contradiction, origin: "b")]) == .divergente)
    }

    @Test("Republicações da mesma origem contam uma vez")
    func duplicatesVoteOnce() {
        var copy = source(.contradiction, origin: "b")
        copy.duplicateOf = "https://g1.globo.com/b"
        let sources = [source(.entailment, origin: "a"), source(.entailment, origin: "c"), source(.contradiction, origin: "b"), copy, copy]
        #expect(VerdictAggregator.verdict(for: sources) == .confirmado)
    }

    // MARK: - Fonte única

    @Test("Uma fonte forte basta; uma fraca não")
    func singleSource() {
        #expect(VerdictAggregator.verdict(for: [source(.entailment)]) == .confirmado)
        #expect(VerdictAggregator.verdict(for: [source(.contradiction)]) == .contradito)
        #expect(VerdictAggregator.verdict(for: [source(.neutral)]) == .semInformacao)
        #expect(VerdictAggregator.verdict(for: [source(.entailment, confidence: 0.7)]) == .semInformacao)
    }

    @Test("Enciclopédia não decide sozinha afirmações sobre o presente")
    func encyclopediaIsTimelessOnly() {
        let wiki = source(.entailment, origin: "wiki", domain: "pt.wikipedia.org")
        #expect(VerdictAggregator.verdict(for: [wiki]) == .confirmado)
        #expect(VerdictAggregator.verdict(for: [wiki], temporalKind: .current) == .semInformacao)
    }

    // MARK: - Portões de relevância por trecho

    @Test("Contradição fora do tema não vota")
    func offTopicContradictionIsIgnored() {
        let features = ClaimFeatures(claim: "O Brasil é o maior produtor de café do mundo.")
        let score = EvidenceScorer.score(passage("A Itália é a maior produtora de macarrão do mundo.", c: 0.92), features: features)
        #expect(score.refute == 0)
        var article = source(.contradiction)
        article.evidence = [passage("A Itália é a maior produtora de macarrão do mundo.", c: 0.92)]
        #expect(VerdictAggregator.verdict(for: [article], features: features) == .semInformacao)
    }

    @Test("Mesmo predicado com outro sujeito refuta")
    func samePredicateRefutes() {
        let features = ClaimFeatures(claim: "Marte é o maior planeta do Sistema Solar.")
        let score = EvidenceScorer.score(passage("Júpiter é o maior planeta do Sistema Solar.", c: 0.95), features: features)
        #expect(score.refute > 0.9)
        #expect(score.reasons.contains("same_predicate"))
    }

    @Test("Mesmo sujeito com outro número refuta")
    func numericMismatchRefutes() {
        let features = ClaimFeatures(claim: "A Copa do Mundo no Brasil foi realizada em 2010.")
        let score = EvidenceScorer.score(passage("A Copa do Mundo no Brasil foi realizada em 2014.", c: 0.45), features: features)
        #expect(score.refute >= 0.75)
        #expect(score.reasons.contains("numeric_mismatch"))
    }

    @Test("Apoio exige os mesmos nomes e é bloqueado por marcador de desmentido")
    func supportGates() {
        let features = ClaimFeatures(claim: "Machado de Assis escreveu Dom Casmurro.")
        #expect(EvidenceScorer.score(passage("Dom Casmurro é um romance escrito por Machado de Assis.", e: 0.98), features: features).support > 0.9)
        #expect(EvidenceScorer.score(passage("Memórias Póstumas é um romance escrito por Machado de Assis.", e: 0.98), features: features).support == 0)
        let debunk = EvidenceScorer.score(passage("É falso que Machado de Assis escreveu Dom Casmurro em inglês.", e: 0.9), features: features)
        #expect(debunk.support == 0)
        #expect(!EvidenceScorer.isAssertion("Quem escreveu Dom Casmurro, o romance de Machado de Assis?"))
        #expect(!EvidenceScorer.isAssertion("(A) Dom Casmurro foi escrito por Machado de Assis em 1899."))
    }

    @Test("Veredito decisivo sempre tem fonte com trecho exibível")
    func decisiveVerdictAlwaysHasEvidence() {
        let cases: [(Verdict, [SourceResult])] = [
            (.confirmado, [source(.entailment)]),
            (.contradito, [source(.contradiction)]),
            (.divergente, [source(.entailment, origin: "a"), source(.contradiction, origin: "b")]),
        ]
        for (verdict, sources) in cases {
            #expect(VerdictAggregator.verdict(for: sources) == verdict)
            let urls = VerdictAggregator.contributingURLs(sources)
            #expect(!urls.isEmpty)
            #expect(sources.filter { urls.contains($0.url) }.allSatisfy { !$0.excerpt.isEmpty })
        }
    }
}
