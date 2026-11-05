import Foundation

struct ReviewedFactCatalog {
    struct Entry: Codable {
        let id: String
        let claim: String
        let entities: [String]
        let eventYear: Int
        let verdict: Verdict
        let url: String
        let title: String
        let excerpt: String
        let publishedAt: String
        let status: String
        let reviewerIDs: [String]
    }
    var entries: [Entry] = []
    static func load(_ bundle: Bundle = .main) -> ReviewedFactCatalog {
        guard let url = bundle.url(forResource: "FactCheckCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return ReviewedFactCatalog() }
        return ReviewedFactCatalog(entries: entries)
    }
    func match(_ context: ClaimContext) -> SourceResult? {
        // No fuzzy semantic match, no contemporary transfer of an old fact-check.
        guard context.temporalKind == .historical, let date = context.startDate else { return nil }
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let normalized = HybridRetrieval.terms(context.text)
        guard let entry = entries.first(where: {
            $0.status == "reviewed" && Set($0.reviewerIDs).count >= 2 && $0.eventYear == year
                && HybridRetrieval.terms($0.claim) == normalized
                && $0.entities.allSatisfy { ClaimAnalyzer.folded(context.text).contains(ClaimAnalyzer.folded($0)) }
                && [.confirmado, .contradito].contains($0.verdict) && AllowlistFilter.isAllowed(urlString: $0.url)
                && !$0.excerpt.isEmpty && $0.excerpt.count <= 300
        }) else { return nil }
        let domain = URL(string: entry.url).flatMap(AllowlistFilter.matchedDomain) ?? ""
        return SourceResult(url: entry.url, domain: domain, title: entry.title,
                            label: entry.verdict == .confirmado ? .entailment : .contradiction,
                            confidence: 1, similarity: 1, excerpt: entry.excerpt,
                            provenance: .reviewedCatalog, publishedAt: ArticleExtractor.parseDate(entry.publishedAt),
                            originGroup: domain, reason: "Checagem pública com correspondência exata de afirmação, entidades e período; revisada no catálogo.")
    }
}
