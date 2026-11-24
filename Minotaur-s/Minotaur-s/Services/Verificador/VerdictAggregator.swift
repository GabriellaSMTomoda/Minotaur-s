import Foundation

/// Evidence v3: weighs relevant, independent evidence per editorial origin.
///
/// v0.5 declared DIVERGENTE whenever any single passage among ~24 NLI pairs crossed 0.50 in each
/// direction; spurious contradictions from off-topic passages made that the most common verdict
/// even for trivial facts. Now each passage must pass `EvidenceScorer`'s relevance gates, each
/// origin contributes once, republications and incompatible periods never vote, partial content
/// only reinforces a complete source, and DIVERGENTE requires a real opposing side: at least two
/// independent origins carrying a comparable share of the evidence.
enum VerdictAggregator {
    struct Vote: Equatable {
        let label: NLILabel
        let score: Double
        let origin: String
        let url: String
        let complete: Bool
    }
    struct Decision {
        let verdict: Verdict
        let votes: [Vote]
        let support: Double
        let refute: Double
    }

    static func verdict(for sources: [SourceResult], features: ClaimFeatures? = nil,
                        temporalKind: ClaimContext.TemporalKind = .timeless, rules: EvidenceRules = .default) -> Verdict {
        decide(sources, features: features, temporalKind: temporalKind, rules: rules).verdict
    }

    static func contributingURLs(_ sources: [SourceResult], features: ClaimFeatures? = nil,
                                 temporalKind: ClaimContext.TemporalKind = .timeless, rules: EvidenceRules = .default) -> Set<String> {
        let decision = decide(sources, features: features, temporalKind: temporalKind, rules: rules)
        let winning: NLILabel? = decision.verdict == .confirmado ? .entailment : decision.verdict == .contradito ? .contradiction : nil
        return Set(decision.votes.filter { decision.verdict == .divergente || $0.label == winning }.map(\.url))
    }

    /// Strongest support/refutation of one source, before weighting.
    static func scores(of source: SourceResult, features: ClaimFeatures?, rules: EvidenceRules) -> (support: Double, refute: Double) {
        var support = 0.0, refute = 0.0
        if source.evidence.isEmpty {
            // Legacy/aggregate-only sources: the article label is the only signal.
            guard source.confidence >= 0.5 else { return (0, 0) }
            if source.stance == .supports || source.stance == .mixed { support = source.confidence }
            if source.stance == .refutes || source.stance == .mixed { refute = source.confidence }
        } else {
            for passage in source.evidence {
                if let features {
                    let score = EvidenceScorer.score(passage, features: features, rules: rules)
                    support = max(support, score.support); refute = max(refute, score.refute)
                } else {
                    let label = passage.probabilities.bestLabel
                    let probability = passage.probabilities.probability(of: label)
                    guard probability >= 0.5 else { continue }
                    if label == .entailment { support = max(support, probability) }
                    if label == .contradiction { refute = max(refute, probability) }
                }
            }
        }
        // Fact-check titles state the verdict; their "support" for the claim is the quoted hoax.
        // A fact-check that quotes the circulating claim and labels it false refutes it.
        if let features, !source.evidence.isEmpty {
            let factCheck = TrustedDomain.profile(for: source.domain).kind == .factCheck
            let debunks = EvidenceScorer.debunks(source.title) || source.evidence.contains { EvidenceScorer.debunks($0.text) }
                || (factCheck && EvidenceScorer.negates(source.title) && !EvidenceScorer.negates(features.text))
            if factCheck && debunks { support = 0 }
            if debunks && support == 0, source.evidence.contains(where: {
                let score = EvidenceScorer.score($0, features: features, rules: rules)
                return (score.reported || factCheck) && score.names == 1 && score.coverage >= 0.6
            }) {
                refute = max(refute, rules.debunkedReportScore)
            }
        }
        // One article rarely asserts both; the weaker side is usually NLI noise.
        if support > 0, refute > 0, min(support, refute) < rules.mixedMinimum {
            if support >= refute { refute = 0 } else { support = 0 }
        }
        return (support, refute)
    }

    static func decide(_ sources: [SourceResult], features: ClaimFeatures?, temporalKind: ClaimContext.TemporalKind,
                       rules: EvidenceRules = .default) -> Decision {
        guard !sources.isEmpty else { return Decision(verdict: .naoEncontrado, votes: [], support: 0, refute: 0) }
        struct Origin { var support = 0.0, refute = 0.0, completeSupport = false, completeRefute = false }
        var origins: [String: Origin] = [:]
        var votes: [Vote] = []
        for source in sources where source.duplicateOf == nil && source.temporalAlignment != .incompatible {
            let kind = TrustedDomain.profile(for: source.domain).kind
            var complete = source.isEligible
            if kind == .encyclopedia && (temporalKind == .current || temporalKind == .recent) { complete = false }
            let weight = rules.weight(for: kind) * (complete ? 1 : rules.partialWeight)
            let (support, refute) = scores(of: source, features: features, rules: rules)
            if support > 0 { votes.append(Vote(label: .entailment, score: support, origin: source.originGroup, url: source.url, complete: complete)) }
            if refute > 0 { votes.append(Vote(label: .contradiction, score: refute, origin: source.originGroup, url: source.url, complete: complete)) }
            var origin = origins[source.originGroup, default: Origin()]
            origin.support = max(origin.support, support * weight)
            origin.refute = max(origin.refute, refute * weight)
            origin.completeSupport = origin.completeSupport || (complete && support > 0)
            origin.completeRefute = origin.completeRefute || (complete && refute > 0)
            origins[source.originGroup] = origin
        }
        let support = origins.values.reduce(0) { $0 + $1.support }
        let refute = origins.values.reduce(0) { $0 + $1.refute }
        let supportOrigins = origins.values.filter { $0.support > 0 }.count
        let refuteOrigins = origins.values.filter { $0.refute > 0 }.count
        func result(_ verdict: Verdict) -> Decision {
            Decision(verdict: verdict, votes: votes.sorted { $0.score > $1.score }, support: support, refute: refute)
        }
        if support < rules.decideMinimum / 2 && refute < rules.decideMinimum / 2 { return result(.semInformacao) }
        let high = max(support, refute), low = min(support, refute)
        let weakerOrigins = support >= refute ? refuteOrigins : supportOrigins
        if low >= rules.divergenceMinimumSide && low >= rules.divergenceRatio * high && weakerOrigins >= rules.divergenceMinimumOrigins {
            return result(.divergente)
        }
        // A near tie between complete sources is a real conflict even with one origin per side.
        let completeBoth = origins.values.contains { $0.completeSupport } && origins.values.contains { $0.completeRefute }
        if completeBoth && low >= rules.decideMinimum && low >= rules.balancedRatio * high { return result(.divergente) }
        let supports = support >= refute
        let score = supports ? support : refute
        let count = supports ? supportOrigins : refuteOrigins
        // Snippets/partial reads may reinforce, never decide alone.
        let complete = origins.values.contains { supports ? $0.completeSupport : $0.completeRefute }
        guard complete, score >= rules.decideMinimum else { return result(.semInformacao) }
        if count == 1 && score < rules.singleOriginMinimum * rules.weight(for: .journalism) { return result(.semInformacao) }
        return result(supports ? .confirmado : .contradito)
    }
}
