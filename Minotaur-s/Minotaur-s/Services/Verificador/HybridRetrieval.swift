import Foundation

enum HybridRetrieval {
    static func terms(_ text: String) -> [String] {
        let normalized = ClaimAnalyzer.folded(text)
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:[.,]\d+)?"#)
        return regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        }
    }

    static func bm25(query: String, documents: [String]) -> [Double] {
        guard !documents.isEmpty else { return [] }
        let tokens = documents.map(terms)
        let queryTerms = Set(terms(query))
        let average = max(1, Double(tokens.reduce(0) { $0 + $1.count }) / Double(tokens.count))
        var frequencies: [String: Int] = [:]
        for words in tokens { for term in Set(words) { frequencies[term, default: 0] += 1 } }
        return tokens.map { words in
            let counts = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
            return queryTerms.reduce(0) { total, term in
                let tf = Double(counts[term, default: 0])
                let df = Double(frequencies[term, default: 0])
                let idf = log(1 + (Double(tokens.count) - df + 0.5) / (df + 0.5))
                return total + idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * Double(words.count) / average))
            }
        }
    }

    static func fusedOrder(lexical: [Double], semantic: [Double]) -> [Int] {
        guard lexical.count == semantic.count else { return [] }
        func order(_ values: [Double]) -> [Int] {
            values.indices.sorted { values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1] }
        }
        var scores = [Double](repeating: 0, count: lexical.count)
        for (rank, index) in order(lexical).enumerated() where lexical[index] > 0 { scores[index] += 1 / Double(60 + rank + 1) }
        for (rank, index) in order(semantic).enumerated() where semantic[index] >= EmbeddingService.minimumSimilarity {
            scores[index] += 1 / Double(60 + rank + 1)
        }
        return order(scores).filter { scores[$0] > 0 }
    }

    static func canonicalURL(_ text: String) -> String {
        guard var parts = URLComponents(string: text) else { return text }
        parts.fragment = nil
        parts.host = parts.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        parts.queryItems = parts.queryItems?.filter { !($0.name.hasPrefix("utm_") || ["fbclid", "gclid"].contains($0.name)) }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? text
    }

    static func rankArticles(_ items: [SearchResultItem], claim: String) -> [SearchResultItem] {
        let lexical = bm25(query: claim, documents: items.map { $0.title + " " + $0.content })
        let ordered = items.indices.sorted {
            let a = lexical[$0] + (items[$0].score ?? 0)
            let b = lexical[$1] + (items[$1].score ?? 0)
            return a == b ? $0 < $1 : a > b
        }
        var seenURLs = Set<String>(), seenOrigins = Set<String>()
        var diverse: [SearchResultItem] = [], others: [SearchResultItem] = []
        for index in ordered {
            let item = items[index]
            guard let url = item.resolvedURL, AllowlistFilter.isAllowed(url),
                  seenURLs.insert(canonicalURL(item.url)).inserted else { continue }
            let domain = AllowlistFilter.matchedDomain(for: url) ?? ""
            let origin = TrustedDomain.profile(for: domain).editorialOrigin
            if seenOrigins.insert(origin).inserted { diverse.append(item) } else { others.append(item) }
        }
        return diverse + others
    }

    static func nearDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        let a = terms(lhs), b = terms(rhs)
        if a == b { return true }
        // A tiny edit in a long article can reverse the evidence while leaving shingle
        // overlap above 0.95. Never reuse a prediction across changed quantities, names,
        // negation, attribution or modality.
        let qualifiers: Set<String> = ["nao", "nunca", "jamais", "sem", "diz", "disse", "afirma", "afirmou",
                                        "alega", "alegou", "pode", "podem", "poderia", "comprovou", "provou",
                                        "todos", "todas", "nenhum", "nenhuma", "apenas"]
        func protected(_ words: [String]) -> [String] {
            words.indices.compactMap { i in
                if qualifiers.contains(words[i]) { return words[i] }
                if words[i].contains(where: \.isNumber) {
                    return words[max(0, i - 1)...min(words.count - 1, i + 1)].joined(separator: " ")
                }
                return nil
            }.sorted()
        }
        func names(_ text: String) -> Set<String> {
            let regex = try! NSRegularExpression(pattern: #"\b\p{Lu}[\p{L}\p{N}]+\b"#)
            return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            })
        }
        guard protected(a) == protected(b), names(lhs) == names(rhs) else { return false }
        // Shingles preserve relations/numbers; topic similarity alone is not duplication.
        func shingles(_ tokens: [String]) -> Set<String> {
            guard tokens.count >= 5 else { return Set(tokens) }
            return Set((0...(tokens.count - 5)).map { tokens[$0..<($0 + 5)].joined(separator: " ") })
        }
        let x = shingles(a), y = shingles(b)
        let union = x.union(y).count
        return union > 0 && Double(x.intersection(y).count) / Double(union) >= 0.85
    }
}
