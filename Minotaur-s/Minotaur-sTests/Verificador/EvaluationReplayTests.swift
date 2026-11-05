import Foundation
import Testing
@testable import Minotaur_s

/// Explicit opt-in public corpus replay with real Core ML and frozen network candidates.
/// It measures extraction/retrieval/inference, not the live search provider's recall.
struct EvaluationReplayTests {
    struct Case: Decodable {
        let id: String
        let claim: String
        let referenceDate: String
        let articles: [Article]
        let evidence: [GoldEvidence]
        enum CodingKeys: String, CodingKey {
            case id, claim, articles, evidence
            case referenceDate = "reference_date"
        }
    }
    struct Article: Decodable, Sendable {
        let url: String
        let title: String
        let html: String
        var publishedDate: String?
    }
    struct GoldEvidence: Decodable {
        let id: String
        let url: String
        let text: String
    }
    struct Prediction: Encodable {
        let id: String
        let verdict: String?
        let evidence: [GoldEvidenceOutput]
        let elapsed_seconds: Double
        let search_calls: Int
        let found_articles: Int
        let sources: [SourceObservation]
        var error: String? = nil
        var confidence: Double? = nil
    }
    struct GoldEvidenceOutput: Encodable {
        let id: String
        let url: String
        let text: String
    }
    struct SourceObservation: Encodable {
        let origin_group: String
        let provenance: String
        let is_partial: Bool
        let temporal_alignment: String
        let duplicate_of: String?
        let passages: [PassageObservation]
    }
    struct PassageObservation: Encodable {
        let id: String
        let url: String
        let text: String
        let logits: [Double]
    }

    @Test("Replay opt-in do corpus público com os modelos reais", .enabled(if: ProcessInfo.processInfo.environment["MINOTAURS_EVALUATION_CORPUS"] != nil,
                                                                          "Set MINOTAURS_EVALUATION_CORPUS and install validated Core ML models"))
    func replayPublicCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["MINOTAURS_EVALUATION_CORPUS"])
        let outputPath = try #require(environment["MINOTAURS_EVALUATION_OUTPUT"])
        let embeddings = try EmbeddingService.loadFromBundle()
        let nli = try NLIService.loadFromBundle()
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline)
        var predictions: [Prediction] = []
        for line in lines {
            let record = try JSONDecoder().decode(Case.self, from: Data(line.utf8))
            let date = try #require(ArticleExtractor.parseDate(record.referenceDate))
            let network = FrozenCorpus(articles: record.articles)
            let pipeline = VerificationPipeline(search: network, extractor: network, embeddings: embeddings, nli: nli,
                                                catalog: ReviewedFactCatalog(), referenceDate: { date })
            let result: VerificationResult
            let started = ProcessInfo.processInfo.systemUptime
            do { result = try await pipeline.verify(claim: record.claim) }
            catch {
                predictions.append(Prediction(id: record.id, verdict: nil, evidence: [], elapsed_seconds: ProcessInfo.processInfo.systemUptime - started,
                                              search_calls: 0, found_articles: record.articles.count, sources: [], error: String(describing: error)))
                continue
            }
            // Gold annotations are used only AFTER prediction, never passed to services.
            var retrieved: [GoldEvidenceOutput] = []
            let contributing = VerdictAggregator.contributingURLs(result.sources)
            for source in result.sources where contributing.contains(source.url) {
                for passage in source.evidence {
                    for expected in record.evidence where HybridRetrieval.canonicalURL(expected.url) == HybridRetrieval.canonicalURL(source.url) {
                        let normalized = passage.text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
                        let span = expected.text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
                        if normalized.contains(span) {
                            retrieved.append(GoldEvidenceOutput(id: expected.id, url: source.url, text: passage.text))
                        }
                    }
                }
            }
            predictions.append(Prediction(id: record.id, verdict: result.verdict.rawValue, evidence: retrieved,
                                          elapsed_seconds: result.diagnostics.elapsedSeconds, search_calls: 0,
                                          found_articles: result.diagnostics.foundArticles,
                                          sources: result.sources.map { source in
                SourceObservation(origin_group: source.originGroup, provenance: source.provenance.rawValue,
                                  is_partial: source.isPartial, temporal_alignment: source.temporalAlignment.rawValue,
                                  duplicate_of: source.duplicateOf, passages: source.evidence.enumerated().map { index, passage in
                    let id = record.evidence.first(where: {
                        HybridRetrieval.canonicalURL($0.url) == HybridRetrieval.canonicalURL(source.url) && passage.text.contains($0.text)
                    })?.id ?? "unannotated-\(source.url)-\(index)"
                    return PassageObservation(id: id, url: source.url, text: passage.text, logits: passage.rawLogits ?? [])
                })
            }, confidence: result.sources.filter { contributing.contains($0.url) }.map(\.confidence).max()))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try predictions.map { try encoder.encode($0) + Data([10]) }.reduce(Data(), +)
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        #expect(!predictions.isEmpty)
    }
}

private struct FrozenCorpus: ArticleSearching, ArticleTextExtracting {
    let articles: [EvaluationReplayTests.Article]
    var consultedDomains: [String] { TrustedDomain.allowlist.sorted() }
    func search(query: String) async throws -> [SearchResultItem] {
        articles.map { SearchResultItem(title: $0.title, url: $0.url, content: "", score: nil, publishedDate: $0.publishedDate) }
    }
    func extractText(from item: SearchResultItem) async -> String? {
        guard let html = articles.first(where: { $0.url == item.url })?.html else { return nil }
        return try? ArticleExtractor.mainText(fromHTML: html)
    }
    func extract(_ item: SearchResultItem, budget: VerificationBudget) async -> ArticleExtraction {
        guard let article = articles.first(where: { $0.url == item.url }), let url = URL(string: article.url),
              let extracted = try? ArticleExtractor.article(fromHTML: article.html, item: item, finalURL: url) else {
            return ArticleExtraction(article: nil, discardReason: .unusable)
        }
        return ArticleExtraction(article: extracted)
    }
}
