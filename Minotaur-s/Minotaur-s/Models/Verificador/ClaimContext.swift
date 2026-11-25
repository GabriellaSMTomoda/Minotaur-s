import Foundation

struct ClaimContext: Codable, Equatable, Sendable {
    enum TemporalKind: String, Codable { case timeless, historical, recent, current }
    let text: String
    let referenceDate: Date
    let temporalKind: TemporalKind
    var startDate: Date?
    var endDate: Date?
    var containsAttribution: Bool

    func alignment(publishedAt: Date?, text: String) -> TemporalAlignment {
        guard temporalKind != .timeless else { return .compatible }
        // A dated past event is discussed long after it happened, and the contested element is
        // the date itself: later or undated publications are compatible. An article published
        // before the claimed period only counts when it states dates of its own.
        if temporalKind == .historical, let startDate {
            guard let publishedAt, publishedAt < startDate else { return .compatible }
            return ClaimAnalyzer.matches(#"\b(1[5-9]|20)\d{2}\b"#, in: text) ? .compatible : .incompatible
        }
        guard let publishedAt else { return .unknown }
        if let startDate, publishedAt < startDate { return .incompatible }
        if let endDate, publishedAt > endDate { return .incompatible }
        return .compatible
    }
}

struct SearchQuery: Sendable, Equatable {
    enum Kind: String, Sendable { case descriptive, contextual, factCheck }
    let text: String
    let kind: Kind
    let context: ClaimContext
    var domains: [String] {
        kind == .factCheck ? TrustedDomain.factCheckDomains : TrustedDomain.allowlist.sorted()
    }
}

/// The uncalibrated baseline preserves the existing NLI floor. Stronger single-source
/// thresholds/temperature require the offline evaluation gate, not hand-picked fixtures.
struct EvidencePolicy: Codable {
    let version: String
    let modelVersion: String
    let temperature: Double
    let minimumConfidence: Double
    let singleSourceMinimumConfidence: Double
    let calibrated: Bool
    var calibrationDigest: String? = nil
    static let baseline = EvidencePolicy(version: "evidence-v2-baseline", modelVersion: "bertimbau-base-plue-spike9",
                                        temperature: 1, minimumConfidence: 0.50,
                                        singleSourceMinimumConfidence: 0.50, calibrated: false)
    static let current: EvidencePolicy = {
        struct ModelVersion: Decodable { let modelVersion: String }
        guard let policyURL = Bundle.main.url(forResource: "EvidencePolicy", withExtension: "json"),
              let versionURL = Bundle.main.url(forResource: "VerificationModelManifest", withExtension: "json"),
              let data = try? Data(contentsOf: policyURL), let versionData = try? Data(contentsOf: versionURL),
              let version = try? JSONDecoder().decode(ModelVersion.self, from: versionData),
              let policy = try? JSONDecoder().decode(EvidencePolicy.self, from: data),
              policy.isValid(for: version.modelVersion) else { return baseline }
        return policy
    }()

    func isValid(for modelVersion: String) -> Bool {
        self.modelVersion == modelVersion && calibrated && !version.isEmpty
            && temperature.isFinite && (0.049...21).contains(temperature)
            && (0.5...1).contains(minimumConfidence)
            && (minimumConfidence...1).contains(singleSourceMinimumConfidence)
            && calibrationDigest?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }
}
