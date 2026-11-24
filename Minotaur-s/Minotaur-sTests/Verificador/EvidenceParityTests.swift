import Testing
@testable import Minotaur_s

/// `EvidenceScorer.swift` must score real dev passages exactly like the reference
/// `evaluation/harness/evidence.py`. Regenerate the fixture with `export_parity_fixture.py`.
struct EvidenceParityTests {
    @Test("Pontuação Swift reproduz a referência Python em passagens reais do conjunto dev")
    func scorerMatchesHarness() throws {
        let embeddings = try EmbeddingService.loadFromBundle()
        var features: [String: ClaimFeatures] = [:]
        var mismatches: [String] = []
        for item in EvidenceParityFixtures.cases {
            let claim = features[item.claim] ?? ClaimFeatures(claim: item.claim, rarity: embeddings.termRarity)
            features[item.claim] = claim
            if claim.anchors != item.anchors { mismatches.append("anchors \(claim.anchors) ≠ \(item.anchors): \(item.claim)") }
            let passage = EvidencePassage(text: item.text, probabilities: .init(entailment: item.e, neutral: item.n, contradiction: item.c),
                                          similarity: item.similarity)
            let score = EvidenceScorer.score(passage, features: claim)
            if abs(score.support - item.support) > 1e-3 || abs(score.refute - item.refute) > 1e-3 {
                mismatches.append("S \(score.support)/\(item.support) R \(score.refute)/\(item.refute) \(score.reasons): \(item.claim) | \(item.text.prefix(90))")
            }
        }
        let report = "\(mismatches.count) of \(EvidenceParityFixtures.cases.count):\n" + mismatches.prefix(15).joined(separator: "\n")
        #expect(mismatches.isEmpty, Comment(rawValue: report))
    }
}
