import Foundation

struct NLIProbabilities: Codable, Equatable {
    let entailment: Double
    let neutral: Double
    let contradiction: Double
    var bestLabel: NLILabel {
        if neutral >= entailment && neutral >= contradiction { return .neutral }
        return entailment >= contradiction ? .entailment : .contradiction
    }
    func probability(of label: NLILabel) -> Double {
        switch label {
        case .entailment: return entailment
        case .neutral: return neutral
        case .contradiction: return contradiction
        }
    }
}

enum TextProvenance: String, Codable, Sendable { case articleBody, structuredData, searchSnippet, reviewedCatalog }
enum SourceStance: String, Codable { case supports, refutes, mixed, insufficient }
enum TemporalAlignment: String, Codable { case compatible, unknown, incompatible }
enum VerificationLimitation: String, Codable, CaseIterable {
    case deadline, quota, rateLimit, searchFailure, readingFailure, partialContent
    case temporalUncertainty, temporalMismatch, inferenceBudget, uncalibratedPolicy
}

struct EvidencePassage: Codable, Equatable {
    let text: String
    let probabilities: NLIProbabilities
    let similarity: Double
    var rawLogits: [Double]? = nil
}

struct ExtractedArticle: Sendable {
    let item: SearchResultItem
    let text: String
    let finalURL: String
    var canonicalURL: String?
    var title: String?
    var author: String?
    var publishedAt: Date?
    var modifiedAt: Date?
    var provenance: TextProvenance = .articleBody
    var isPartial: Bool = false
    var originalSource: String?
    var paragraphs: [String] { text.components(separatedBy: .newlines).filter { !$0.isEmpty } }
}

enum ArticleDiscardReason: String, Sendable { case network, timeout, paywall, unusable, disallowedURL, robots }
struct ArticleExtraction: Sendable {
    let article: ExtractedArticle?
    var discardReason: ArticleDiscardReason?
}

struct VerificationDiagnostics: Codable {
    var foundArticles = 0
    var readArticles = 0
    var usedSources = 0
    var independentOrigins = 0
    var searchCalls = 0
    var nliPairs = 0
    var elapsedSeconds: Double = 0
    var limitations: [VerificationLimitation] = []
    var policyVersion = EvidencePolicy.current.version
}
