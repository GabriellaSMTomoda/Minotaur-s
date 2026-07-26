import Foundation

// Mesmos critérios de detecção de bloqueio de spikes/04-ddg-scraping/search_ddg.py
// (looks_blocked): status fora de 200 (403/429/503 explícitos, ou qualquer outro
// != 200), marcador textual de captcha/bloqueio no corpo, ou corpo < 1500 bytes.
struct SearchResult: Codable {
    var query: String
    var statusCode: Int
    var elapsedS: Double
    var bodyLen: Int
    var blocked: Bool
    var blockReason: String?
    var resultCount: Int
    var resultHosts: [String]
    var nDomains: Int?
    var queryLen: Int
    var hostsMatchingSubset: Int?
    var hostsTotal: Int
    var claim: String?
    var keywords: String?
    var networkError: String?

    enum CodingKeys: String, CodingKey {
        case query
        case statusCode = "status_code"
        case elapsedS = "elapsed_s"
        case bodyLen = "body_len"
        case blocked
        case blockReason = "block_reason"
        case resultCount = "result_count"
        case resultHosts = "result_hosts"
        case nDomains = "n_domains"
        case queryLen = "query_len"
        case hostsMatchingSubset = "hosts_matching_subset"
        case hostsTotal = "hosts_total"
        case claim
        case keywords
        case networkError = "network_error"
    }
}

struct RunResult: Codable {
    var phaseA: [SearchResult]
    var phaseB: [SearchResult]
    var stoppedEarly: Bool
    var stopReason: String?
    var safeNDomainsUsedInPhaseB: Int?

    enum CodingKeys: String, CodingKey {
        case phaseA = "phase_a"
        case phaseB = "phase_b"
        case stoppedEarly = "stopped_early"
        case stopReason = "stop_reason"
        case safeNDomainsUsedInPhaseB = "safe_n_domains_used_in_phase_b"
    }
}

enum DDGSpike {
    // Mesmo endpoint do Spike 4 original (Python). Sem headers customizados,
    // sem URLSessionConfiguration especial — URLSession.shared puro, para
    // refletir o que o app real faria por padrão (ver instrução da tarefa).
    static let endpoint = "https://html.duckduckgo.com/html/"

    static let blockMarkers = [
        "unusual traffic",
        "captcha",
        "verify you are a human",
        "are you a robot",
        "automated queries",
        "anomaly",
        "blocked",
        "access denied",
        "rate limit",
    ]

    static let resultLinkRegex = try! NSRegularExpression(
        pattern: "class=\"result__a\"[^>]*href=\"([^\"]+)\""
    )

    static func looksBlocked(status: Int, text: String, bodyLenBytes: Int) -> (Bool, String?) {
        if [403, 429, 503].contains(status) {
            return (true, "HTTP \(status)")
        }
        if status != 200 {
            return (true, "HTTP \(status) inesperado")
        }
        let low = text.lowercased()
        for marker in blockMarkers {
            if low.contains(marker) {
                return (true, "marcador de bloqueio no corpo: '\(marker)'")
            }
        }
        if bodyLenBytes < 1500 {
            return (true, "corpo suspeito pequeno (\(bodyLenBytes) bytes)")
        }
        return (false, nil)
    }

    static func extractHosts(from text: String) -> [String] {
        let ns = text as NSString
        let matches = resultLinkRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var hosts: [String] = []
        for m in matches {
            guard m.numberOfRanges > 1 else { continue }
            let href = ns.substring(with: m.range(at: 1))
            if let url = URL(string: href), var host = url.host {
                host = host.lowercased()
                if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
                hosts.append(host)
            }
        }
        return hosts
    }

    static func hostInAllowlist(_ host: String, _ allowlist: [String]) -> Bool {
        allowlist.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // Requisição pura via URLSession.shared — sem headers customizados,
    // sem configuração especial. GET para o endpoint com "q" como query param,
    // igual ao requests.get(ENDPOINT, params={"q": query}) do Spike 4 original.
    static func doSearch(query: String) async -> SearchResult {
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let url = components.url!

        let t0 = Date()
        var statusCode = -1
        var bodyLenBytes = 0
        var bodyText = ""
        var networkError: String?

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                statusCode = http.statusCode
            }
            bodyLenBytes = data.count
            bodyText = String(data: data, encoding: .utf8) ?? ""
        } catch {
            networkError = error.localizedDescription
        }

        let elapsed = Date().timeIntervalSince(t0)
        let (blocked, reason): (Bool, String?)
        if let networkError {
            blocked = true
            reason = "erro de rede: \(networkError)"
        } else {
            (blocked, reason) = looksBlocked(status: statusCode, text: bodyText, bodyLenBytes: bodyLenBytes)
        }
        let hosts = blocked ? [] : extractHosts(from: bodyText)

        return SearchResult(
            query: query,
            statusCode: statusCode,
            elapsedS: (elapsed * 100).rounded() / 100,
            bodyLen: bodyLenBytes,
            blocked: blocked,
            blockReason: reason,
            resultCount: hosts.count,
            resultHosts: hosts,
            nDomains: nil,
            queryLen: query.count,
            hostsMatchingSubset: nil,
            hostsTotal: hosts.count,
            claim: nil,
            keywords: nil,
            networkError: networkError
        )
    }

    static func sleepLikeAHuman() async {
        let delay = Double.random(in: 10...25)
        print("    (aguardando \(String(format: "%.1f", delay))s antes da próxima busca)")
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    static func phaseA() async -> ([SearchResult], Bool) {
        print("\n=== FASE A — limite prático de domínios por query (site: OR) ===")
        let baseQuery = DDGClaims.extractKeywords(DDGClaims.claims[0])
        let countsToTry = [3, 5, 8, 12, 16, 20, 25, 30]
        var rows: [SearchResult] = []

        for n in countsToTry {
            let subset = Array(DDGDomains.trusted.prefix(n))
            let siteClause = subset.map { "site:\($0)" }.joined(separator: " OR ")
            let query = "\(baseQuery) \(siteClause)"
            print("\n[A] n_domains=\(n) query_len=\(query.count) chars")

            var result = await doSearch(query: query)
            result.nDomains = n
            result.queryLen = query.count
            let matched = result.resultHosts.filter { hostInAllowlist($0, subset) }
            result.hostsMatchingSubset = matched.count
            result.hostsTotal = result.resultHosts.count
            rows.append(result)

            let status = result.blocked ? "BLOQUEADO" : "ok"
            print("    status=\(result.statusCode) \(status) resultados=\(result.resultCount) dentro_do_subset=\(result.hostsMatchingSubset ?? 0)/\(result.hostsTotal) tempo=\(result.elapsedS)s")

            if result.blocked {
                print("    !!! BLOQUEIO DETECTADO: \(result.blockReason ?? "?") — parando fase A")
                return (rows, true)
            }
            await sleepLikeAHuman()
        }
        return (rows, false)
    }

    static func phaseB(maxDomains: Int) async -> ([SearchResult], Bool) {
        print("\n=== FASE B — 20 buscas distintas (max_domains=\(maxDomains)) ===")
        let subset = Array(DDGDomains.trusted.prefix(maxDomains))
        var rows: [SearchResult] = []

        for (i, claim) in DDGClaims.claims.enumerated() {
            let keywords = DDGClaims.extractKeywords(claim)
            let siteClause = subset.map { "site:\($0)" }.joined(separator: " OR ")
            let query = "\(keywords) \(siteClause)"
            let preview = String(claim.prefix(70))
            print("\n[B \(i + 1)/20] claim: \(preview)...")

            var result = await doSearch(query: query)
            result.claim = claim
            result.keywords = keywords
            result.queryLen = query.count
            let matched = result.resultHosts.filter { hostInAllowlist($0, DDGDomains.trusted) }
            result.hostsMatchingSubset = matched.count
            result.hostsTotal = result.resultHosts.count
            rows.append(result)

            let status = result.blocked ? "BLOQUEADO" : "ok"
            print("    status=\(result.statusCode) \(status) resultados=\(result.resultCount) na_allowlist=\(result.hostsMatchingSubset ?? 0)/\(result.hostsTotal) tempo=\(result.elapsedS)s")

            if result.blocked {
                print("    !!! BLOQUEIO DETECTADO: \(result.blockReason ?? "?") — parando fase B")
                return (rows, true)
            }
            if i < DDGClaims.claims.count - 1 {
                await sleepLikeAHuman()
            }
        }
        return (rows, false)
    }

    static func mainFlow() async -> String {
        print("=== INICIO SPIKE 4b (URLSession, device físico) ===")

        let (phaseARows, blockedA) = await phaseA()
        var run = RunResult(phaseA: phaseARows, phaseB: [], stoppedEarly: false, stopReason: nil, safeNDomainsUsedInPhaseB: nil)

        if blockedA {
            run.stoppedEarly = true
            run.stopReason = "bloqueio detectado na fase A"
            print("\nParando após bloqueio na fase A.")
            return encode(run)
        }

        var safeN = 30
        for row in phaseARows {
            if row.hostsTotal > 0 {
                let matchRate = Double(row.hostsMatchingSubset ?? 0) / Double(row.hostsTotal)
                if matchRate < 0.5 {
                    safeN = max(3, (row.nDomains ?? 30) - 1)
                    break
                }
            }
        }

        let (phaseBRows, blockedB) = await phaseB(maxDomains: safeN)
        run.phaseB = phaseBRows
        run.safeNDomainsUsedInPhaseB = safeN
        if blockedB {
            run.stoppedEarly = true
            run.stopReason = "bloqueio detectado na fase B"
        }

        print("\n=== FIM SPIKE 4b ===")
        return encode(run)
    }

    static func encode(_ run: RunResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(run), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
