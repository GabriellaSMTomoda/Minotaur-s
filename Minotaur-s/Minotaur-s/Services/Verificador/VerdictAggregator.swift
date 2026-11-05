import Foundation

/// Counts independent, complete, temporally compatible evidence. A majority cannot erase
/// an eligible opposing source. Missing/partial evidence is never a negative vote.
enum VerdictAggregator {
    static func verdict(for sources: [SourceResult], policy: EvidencePolicy = .current) -> Verdict {
        guard !sources.isEmpty else { return .naoEncontrado }
        let decisive = votes(sources, policy: policy)
        let support = decisive.contains { $0.label == .entailment }
        let refute = decisive.contains { $0.label == .contradiction }
        if support && refute { return .divergente }
        if support { return .confirmado }
        if refute { return .contradito }
        return .semInformacao
    }

    static func contributingURLs(_ sources: [SourceResult], policy: EvidencePolicy = .current) -> Set<String> {
        Set(votes(sources, policy: policy).map(\.url))
    }

    private struct Vote { let label: NLILabel; let confidence: Double; let origin: String; let url: String }
    private static func votes(_ sources: [SourceResult], policy: EvidencePolicy) -> [Vote] {
        var candidates: [Vote] = []
        for source in sources where source.isEligible {
            if !source.evidence.isEmpty {
                for passage in source.evidence {
                    let label = passage.probabilities.bestLabel
                    let confidence = passage.probabilities.probability(of: label)
                    if label != .neutral && confidence >= policy.minimumConfidence {
                        candidates.append(Vote(label: label, confidence: confidence, origin: source.originGroup, url: source.url))
                    }
                }
            } else if source.confidence >= policy.minimumConfidence {
                if source.stance == .supports || source.stance == .mixed {
                    candidates.append(Vote(label: .entailment, confidence: source.confidence, origin: source.originGroup, url: source.url))
                }
                if source.stance == .refutes || source.stance == .mixed {
                    candidates.append(Vote(label: .contradiction, confidence: source.confidence, origin: source.originGroup, url: source.url))
                }
            }
        }
        let single = Set(candidates.map(\.origin)).count == 1
        return candidates.filter { $0.confidence >= (single ? policy.singleSourceMinimumConfidence : policy.minimumConfidence) }
    }
}
