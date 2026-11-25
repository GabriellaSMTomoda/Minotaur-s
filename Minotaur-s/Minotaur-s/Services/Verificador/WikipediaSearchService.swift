import Foundation
import OSLog

/// Encyclopedic source for stable facts, fetched in parallel with the first news search.
protocol EncyclopediaSearching: Sendable {
    func articles(for context: ClaimContext, budget: VerificationBudget) async -> [ExtractedArticle]
}

/// Wikipédia PT through the Worker `POST /wiki` route: free, no Tavily credit, and the user's
/// IP never reaches Wikimedia. Failures only remove this source; they never become "not found".
/// Mirrors `evaluation/harness/wiki.py`.
struct WikipediaSearchService: EncyclopediaSearching {
    private static let logger = Logger(subsystem: "com.julia.fatoufarsa2025", category: "EncyclopediaTransport")
    static let host = "pt.wikipedia.org"
    static let timeout: TimeInterval = 5
    private let session: URLSession
    private let endpoint: String
    init(session: URLSession = .shared, endpoint: String = TavilySearchService.proxyEndpoint + "/wiki") {
        self.session = session; self.endpoint = endpoint
    }

    /// Content words of the claim, then its names, as in the harness.
    static func queries(for claim: String) -> [String] {
        let words = EvidenceScorer.words(claim)
        let content = words.filter { !EvidenceScorer.stopwords.contains(ClaimAnalyzer.folded($0)) && $0.count > 2 }
        let names = words.filter { $0.first?.isUppercase == true || $0.allSatisfy(\.isNumber) }
        var out = [content.joined(separator: " ")]
        let keys = names.joined(separator: " ")
        if !keys.isEmpty && keys != out[0] { out.append(keys) }
        return out.filter { !$0.isEmpty }.map { String($0.prefix(200)) }
    }

    func articles(for context: ClaimContext, budget: VerificationBudget) async -> [ExtractedArticle] {
        var out: [ExtractedArticle] = []
        for query in Self.queries(for: context.text) where out.count < 2 && budget.networkRemaining > 1 {
            guard let items = await search(query, budget: budget) else { break }
            for item in items where out.count < 2 && !out.contains(where: { $0.finalURL == item.url }) {
                guard let text = item.rawContent, text.count >= 200,
                      URL(string: item.url)?.host == Self.host else { continue }
                var article = ExtractedArticle(item: item.searchItem, text: text, finalURL: item.url)
                article.canonicalURL = item.url
                article.title = item.title
                out.append(article)
            }
        }
        return out
    }

    private struct Item: Decodable {
        let title: String, url: String, content: String
        let rawContent: String?
        let score: Double?
        enum CodingKeys: String, CodingKey { case title, url, content, score; case rawContent = "raw_content" }
        var searchItem: SearchResultItem { SearchResultItem(title: title, url: url, content: content, score: score) }
    }
    private struct Response: Decodable { let results: [Item] }

    private func search(_ query: String, budget: VerificationBudget) async -> [Item]? {
        guard let url = URL(string: endpoint), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = min(Self.timeout, budget.networkRemaining)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Self.logger.error("Encyclopedia HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0, privacy: .public)")
                return nil
            }
            return try JSONDecoder().decode(Response.self, from: data).results
        } catch {
            Self.logger.error("Encyclopedia request failed")
            return nil
        }
    }
}
