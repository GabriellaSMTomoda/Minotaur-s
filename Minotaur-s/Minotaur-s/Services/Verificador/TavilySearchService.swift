import Foundation
import OSLog

/// Official search API only. All queries/retries in a verification share one budget.
struct TavilySearchService: Sendable {
    private static let logger = Logger(subsystem: "com.julia.fatoufarsa2025", category: "SearchTransport")
    static let proxyEndpoint = "https://minotaurs-tavily-proxy.hen-lac-sil.workers.dev"
    static let requestedResultCount = 20
    // Worker permits 4.5 s upstream; leave room for TLS, routing and body transfer.
    // The shared 11 s collection deadline still caps this request and its retry.
    static let timeout: TimeInterval = 6
    private let session: URLSession
    private let endpoint: String
    init(session: URLSession = .shared, endpoint: String = TavilySearchService.proxyEndpoint) {
        self.session = session; self.endpoint = endpoint
    }
    static var consultedDomains: [String] { TrustedDomain.allowlist.sorted() }
    var consultedDomains: [String] { Self.consultedDomains }

    func search(query: String) async throws -> [SearchResultItem] {
        let context = ClaimAnalyzer.context(for: query)
        return try await search(SearchQuery(text: query, kind: .descriptive, context: context), budget: VerificationBudget())
    }

    func search(_ query: SearchQuery, budget: VerificationBudget) async throws -> [SearchResultItem] {
        for attempt in 0..<2 {
            do {
                try budget.reserveSearch()
                let response = try await perform(query, budget: budget)
                return AllowlistFilter.filter(response.results, url: \.resolvedURL, limit: 20)
            } catch {
                try Task.checkCancellation()
                if let failure = error as? SearchFailure {
                    if attempt == 0 && failure.retriable && budget.searchCalls < 3 && budget.networkRemaining > 0.5 { continue }
                    throw failure.error
                }
                throw error
            }
        }
        throw VerificationError.searchRequestFailed
    }

    private func perform(_ query: SearchQuery, budget: VerificationBudget) async throws -> TavilyResponse {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil else { throw SearchFailure.failed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = min(Self.timeout, budget.networkRemaining)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["query": String(query.text.prefix(200)), "search_depth": "basic",
                                  "max_results": 20, "include_domains": query.domains,
                                  "include_domains_mode": "restrict", "include_answer": false,
                                  "auto_parameters": false, "include_usage": true,
                                  "language": "pt", "filter_by_language": true,
                                  "include_published_date": true, "query_kind": query.kind.rawValue]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        formatter.dateFormat = "yyyy-MM-dd"
        // Historical events may be covered retrospectively; do not impose publication
        // dates for those queries. Validate the event context in the extracted evidence.
        if query.context.temporalKind == .current || query.context.temporalKind == .recent {
            if let start = query.context.startDate { body["start_date"] = formatter.string(from: start) }
            body["topic"] = "news"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            try Task.checkCancellation()
            Self.logger.error("Search transport failed, code \((error as? URLError)?.code.rawValue ?? 0, privacy: .public)")
            switch (error as? URLError)?.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw SearchFailure.offline
            case .timedOut: throw SearchFailure.timeout
            default: throw SearchFailure.failed
            }
        }
        guard let http = response as? HTTPURLResponse else { throw SearchFailure.failed }
        if !(200...299).contains(http.statusCode) {
            Self.logger.error("Search HTTP status \(http.statusCode, privacy: .public)")
        }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw SearchFailure.unauthorized
        case 429:
            if http.value(forHTTPHeaderField: "X-Search-Error") == "quota_exceeded" {
                budget.record(.quota); throw SearchFailure.quota
            }
            budget.record(.rateLimit); throw SearchFailure.rateLimit
        case 432, 433: budget.record(.quota); throw SearchFailure.quota
        case 500...599: throw SearchFailure.server
        default: throw SearchFailure.failed
        }
        guard let decoded = try? JSONDecoder().decode(TavilyResponse.self, from: data) else {
            Self.logger.error("Search response does not match the expected JSON schema")
            throw SearchFailure.failed
        }
        return decoded
    }
}

private enum SearchFailure: Error {
    case offline, timeout, failed, unauthorized, quota, rateLimit, server
    var retriable: Bool { self == .timeout || self == .server }
    var error: VerificationError {
        switch self {
        case .offline: return .noConnection
        case .quota: return .searchQuotaExceeded
        case .rateLimit: return .searchRateLimited
        default: return .searchRequestFailed
        }
    }
}
struct TavilyResponse: Decodable { let results: [SearchResultItem] }
