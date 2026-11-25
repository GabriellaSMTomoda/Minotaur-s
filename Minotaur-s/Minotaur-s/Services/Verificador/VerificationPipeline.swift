import Foundation

enum VerificationStage: Equatable, Sendable { case searching, readingSources, analyzing }

protocol ArticleSearching: Sendable {
    var consultedDomains: [String] { get }
    func search(query: String) async throws -> [SearchResultItem]
    func search(_ query: SearchQuery, budget: VerificationBudget) async throws -> [SearchResultItem]
}
extension ArticleSearching {
    func search(_ query: SearchQuery, budget: VerificationBudget) async throws -> [SearchResultItem] {
        try budget.reserveSearch()
        return try await search(query: query.text)
    }
}
protocol ArticleTextExtracting: Sendable {
    func extractText(from item: SearchResultItem) async -> String?
    func extract(_ item: SearchResultItem, budget: VerificationBudget) async -> ArticleExtraction
}
extension ArticleTextExtracting {
    func extract(_ item: SearchResultItem, budget: VerificationBudget) async -> ArticleExtraction {
        guard let text = await extractText(from: item) else { return ArticleExtraction(article: nil, discardReason: .network) }
        return ArticleExtraction(article: ExtractedArticle(item: item, text: text, finalURL: item.url))
    }
}
protocol ChunkSelecting {
    func selectTopChunks(claim: String, chunks: [String]) throws -> [EmbeddingService.ScoredChunk]
    func selectTopChunks(claim: String, chunks: [String], claimVector: [Float]?, budget: VerificationBudget) throws -> [EmbeddingService.ScoredChunk]
    func prepareClaim(_ claim: String) throws -> [Float]?
    func tokenCount(_ text: String) -> Int
    /// Sentence scoring for short NLI premises; `nil` keeps window-level premises.
    func similarities(of texts: [String], claimVector: [Float], budget: VerificationBudget) throws -> [Double]?
    func termRarity(_ word: String) -> Double?
}
extension ChunkSelecting {
    func similarities(of texts: [String], claimVector: [Float], budget: VerificationBudget) throws -> [Double]? { nil }
    func termRarity(_ word: String) -> Double? { nil }
    func prepareClaim(_ claim: String) throws -> [Float]? { nil }
    func tokenCount(_ text: String) -> Int { TextChunker.conservativeTokenEstimate(text) }
    func selectTopChunks(claim: String, chunks: [String], claimVector: [Float]?, budget: VerificationBudget) throws -> [EmbeddingService.ScoredChunk] {
        try budget.checkAnalysis()
        return try selectTopChunks(claim: claim, chunks: chunks)
    }
}
protocol ChunkClassifying {
    func label(for claim: String, chunks: [EmbeddingService.ScoredChunk]) throws -> NLIService.ArticleLabel?
    func classify(claim: String, chunks: [EmbeddingService.ScoredChunk], budget: VerificationBudget) throws -> NLIService.ArticleLabel?
    func tokenCount(_ text: String) -> Int
}
extension ChunkClassifying {
    func tokenCount(_ text: String) -> Int { TextChunker.conservativeTokenEstimate(text) }
    func classify(claim: String, chunks: [EmbeddingService.ScoredChunk], budget: VerificationBudget) throws -> NLIService.ArticleLabel? {
        try budget.reservePairs(chunks.count)
        return try label(for: claim, chunks: chunks)
    }
}
extension TavilySearchService: ArticleSearching {}
extension ArticleExtractor: ArticleTextExtracting {}
extension EmbeddingService: ChunkSelecting {}
extension NLIService: ChunkClassifying {}

/// The only coordinator; all session content stays in memory. Network work is raced against
/// an 11-second monotonic deadline; synchronous Core ML is checked between every prediction.
struct VerificationPipeline {
    typealias ProgressHandler = @Sendable (VerificationStage) -> Void
    static let minimumChunkTokens = 64
    private let search: any ArticleSearching
    private let extractor: any ArticleTextExtracting
    private let embeddings: any ChunkSelecting
    private let nli: any ChunkClassifying
    private let encyclopedia: (any EncyclopediaSearching)?
    private let makeBudget: @Sendable () -> VerificationBudget
    private let catalog: ReviewedFactCatalog
    private let referenceDate: @Sendable () -> Date

    init(search: any ArticleSearching, extractor: any ArticleTextExtracting,
         embeddings: any ChunkSelecting, nli: any ChunkClassifying,
         makeBudget: @escaping @Sendable () -> VerificationBudget = { VerificationBudget() },
         catalog: ReviewedFactCatalog = .load(), referenceDate: @escaping @Sendable () -> Date = { Date() },
         encyclopedia: (any EncyclopediaSearching)? = nil) {
        self.search = search; self.extractor = extractor; self.embeddings = embeddings; self.nli = nli
        self.encyclopedia = encyclopedia
        self.makeBudget = makeBudget
        self.catalog = catalog
        self.referenceDate = referenceDate
    }
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> VerificationPipeline {
        VerificationPipeline(search: TavilySearchService(), extractor: ArticleExtractor(),
                             embeddings: try EmbeddingService.loadFromBundle(bundle), nli: try NLIService.loadFromBundle(bundle),
                             encyclopedia: WikipediaSearchService())
    }

    func verify(claim: String, onProgress: ProgressHandler = { _ in }) async throws -> VerificationResult {
        try Task.checkCancellation()
        let analysis = ClaimAnalyzer.analyze(claim)
        guard !analysis.needsRephrasing else { throw VerificationError.claimNeedsRephrasing }
        guard analysis.candidates.count == 1 else { throw VerificationError.claimNeedsSelection }
        guard nli.tokenCount(claim) <= 509 - Self.minimumChunkTokens else { throw VerificationError.claimNeedsRephrasing }
        let context = ClaimAnalyzer.context(for: claim, at: referenceDate())
        let budget = makeBudget()
        if let source = catalog.match(context) {
            return makeResult(context: context, sources: [source], collection: Collection(items: [], articles: []), budget: budget)
        }
        onProgress(.searching)
        let collected = try await collect(context: context, budget: budget, onProgress: onProgress)
        try Task.checkCancellation()
        if collected.items.isEmpty {
            if budget.limitations.contains(.deadline) { throw VerificationError.deadlineExceeded }
            return makeResult(context: context, sources: [], collection: collected, budget: budget)
        }
        guard !collected.articles.isEmpty else {
            if budget.limitations.contains(.deadline) { throw VerificationError.deadlineExceeded }
            throw VerificationError.readingIncomplete
        }
        onProgress(.analyzing)
        let features = ClaimFeatures(claim: context.text, rarity: embeddings.termRarity)
        let sources = try analyze(context: context, articles: collected.articles, budget: budget, features: features)
        try Task.checkCancellation()
        return makeResult(context: context, sources: sources, collection: collected, budget: budget)
    }

    private struct Collection {
        var items: [SearchResultItem] = []
        var articles: [ExtractedArticle] = []
    }
    private enum NetworkEvent {
        case search(Result<[SearchResultItem], Error>)
        case article(ArticleExtraction)
        case encyclopedia([ExtractedArticle])
        case deadline
    }

    private func collect(context: ClaimContext, budget: VerificationBudget, onProgress: ProgressHandler) async throws -> Collection {
        let queries = SearchQueryBuilder.plan(for: context)
        guard let primary = queries.first else { throw VerificationError.claimNeedsRephrasing }
        let search = self.search, extractor = self.extractor, encyclopedia = self.encyclopedia
        return try await withThrowingTaskGroup(of: NetworkEvent.self) { group in
            group.addTask {
                do { return .search(.success(try await search.search(primary, budget: budget))) }
                catch { return .search(.failure(error)) }
            }
            // Free encyclopedic source in parallel; it never consumes the Tavily budget.
            if let encyclopedia {
                group.addTask { .encyclopedia(await encyclopedia.articles(for: context, budget: budget)) }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, budget.networkRemaining) * 1_000_000_000))
                return .deadline
            }
            var collection = Collection()
            var pendingSearches = encyclopedia == nil ? 1 : 2, activeDownloads = 0, scheduledDownloads = 0
            var queue: [SearchResultItem] = []
            var seenURLs = Set<String>(), scheduledURLs = Set<String>()
            var expanded = false
            var firstError: Error?
            while let event = try await group.next() {
                try Task.checkCancellation()
                switch event {
                case .deadline:
                    budget.record(.deadline); group.cancelAll()
                    return collection
                case .search(let response):
                    pendingSearches -= 1
                    switch response {
                    case .success(let items):
                        for item in items where item.resolvedURL.map(AllowlistFilter.isAllowed) == true {
                            if seenURLs.insert(HybridRetrieval.canonicalURL(item.url)).inserted { collection.items.append(item) }
                        }
                        queue = HybridRetrieval.rankArticles(collection.items, claim: context.text)
                            .filter { !scheduledURLs.contains(HybridRetrieval.canonicalURL($0.url)) }
                        let origins = Set(collection.items.compactMap { $0.resolvedURL.flatMap(AllowlistFilter.matchedDomain).map { TrustedDomain.profile(for: $0).editorialOrigin } })
                        // Expand early while first downloads are in flight, not after spending
                        // the network deadline reading them. Empty results also get a rescue query.
                        if !expanded && (origins.count < 2 || collection.items.count < 4) && budget.networkRemaining > 1 {
                            expanded = true
                            for query in queries.dropFirst().prefix(max(0, 3 - budget.searchCalls)) {
                                pendingSearches += 1
                                group.addTask {
                                    do { return .search(.success(try await search.search(query, budget: budget))) }
                                    catch { return .search(.failure(error)) }
                                }
                            }
                        }
                    case .failure(let error):
                        if error is CancellationError { throw CancellationError() }
                        let failure = error as? VerificationError ?? .searchRequestFailed
                        if failure != .searchBudgetExceeded {
                            firstError = firstError ?? failure
                            budget.record(failure == .searchQuotaExceeded ? .quota : failure == .searchRateLimited ? .rateLimit : .searchFailure)
                        }
                    }
                case .encyclopedia(let articles):
                    pendingSearches -= 1
                    for article in articles where seenURLs.insert(HybridRetrieval.canonicalURL(article.finalURL)).inserted {
                        scheduledURLs.insert(HybridRetrieval.canonicalURL(article.finalURL))
                        collection.items.append(article.item); collection.articles.append(article)
                    }
                case .article(let extraction):
                    activeDownloads -= 1
                    if let article = extraction.article { collection.articles.append(article) }
                    if extraction.article?.isPartial == true { budget.record(.partialContent) }
                    if extraction.discardReason != nil { budget.record(.readingFailure) }
                    let needsRescue = extraction.article.map {
                        $0.isPartial || context.alignment(publishedAt: $0.publishedAt, text: $0.text) != .compatible
                    } ?? true
                    if !expanded && needsRescue && budget.networkRemaining > 1.5 {
                        expanded = true
                        for query in queries.dropFirst().prefix(max(0, 3 - budget.searchCalls)) {
                            pendingSearches += 1
                            group.addTask {
                                do { return .search(.success(try await search.search(query, budget: budget))) }
                                catch { return .search(.failure(error)) }
                            }
                        }
                    }
                }
                while activeDownloads < 4 && scheduledDownloads < 8 && !queue.isEmpty && budget.networkRemaining > 0 {
                    if pendingSearches > 0 && scheduledDownloads >= 4 { break }
                    let item = queue.removeFirst()
                    guard scheduledURLs.insert(HybridRetrieval.canonicalURL(item.url)).inserted else { continue }
                    activeDownloads += 1; scheduledDownloads += 1
                    if scheduledDownloads == 1 { onProgress(.readingSources) }
                    group.addTask {
                        try Task.checkCancellation()
                        let result = await extractor.extract(item, budget: budget)
                        try Task.checkCancellation()
                        return .article(result)
                    }
                }
                if pendingSearches == 0 && activeDownloads == 0 {
                    group.cancelAll()
                    if collection.items.isEmpty, let firstError { throw firstError }
                    let order = Dictionary(uniqueKeysWithValues: collection.items.enumerated().map { ($0.element.url, $0.offset) })
                    collection.articles.sort { (order[$0.item.url] ?? 0) < (order[$1.item.url] ?? 0) }
                    return collection
                }
            }
            return collection
        }
    }

    private func analyze(context: ClaimContext, articles: [ExtractedArticle], budget: VerificationBudget,
                         features: ClaimFeatures) throws -> [SourceResult] {
        var sources: [SourceResult] = []
        var previous: [(article: ExtractedArticle, source: SourceResult)] = []
        do {
            try budget.checkAnalysis()
            let claimVector = try embeddings.prepareClaim(context.text)
            for article in articles.sorted(by: { !$0.isPartial && $1.isPartial }) {
                try budget.checkAnalysis()
                if let duplicate = previous.first(where: {
                    HybridRetrieval.canonicalURL($0.article.canonicalURL ?? $0.article.finalURL) == HybridRetrieval.canonicalURL(article.canonicalURL ?? article.finalURL)
                    || HybridRetrieval.nearDuplicate($0.article.text, article.text)
                }) {
                    var copy = duplicate.source
                    copy = SourceResult(url: article.finalURL, domain: domain(article.item), title: article.title ?? article.item.title,
                                        label: copy.label, confidence: copy.confidence, similarity: copy.similarity, excerpt: copy.excerpt,
                                        stance: copy.stance, provenance: article.provenance, isPartial: article.isPartial,
                                        publishedAt: article.publishedAt, temporalAlignment: copy.temporalAlignment,
                                        originGroup: copy.originGroup, duplicateOf: copy.url, evidence: copy.evidence,
                                        reason: "Republicação ou conteúdo equivalente a outra matéria analisada.")
                    sources.append(copy)
                    continue
                }
                let premiseBudget = 509 - nli.tokenCount(context.text)
                let nliChunker = TextChunker(maxTokens: premiseBudget, estimateTokens: nli.tokenCount)
                let windows = ChunkQualityFilter.keeping(TextChunker(maxTokens: 126, estimateTokens: embeddings.tokenCount)
                    .chunks(from: article.text).flatMap { nliChunker.chunks(from: $0) })
                guard !windows.isEmpty else { continue }
                let selected = try embeddings.selectTopChunks(claim: context.text, chunks: windows, claimVector: claimVector, budget: budget)
                guard !selected.isEmpty else { continue }
                let premises = try sentencePremises(selected, in: windows, title: article.title ?? article.item.title,
                                                    claim: context.text, claimVector: claimVector, budget: budget)
                    ?? expand(selected, in: windows, claim: context.text)
                guard var label = try nli.classify(claim: context.text, chunks: premises, budget: budget) else { continue }
                label = Self.relabel(label, features: features)
                let alignment = context.alignment(publishedAt: article.publishedAt, text: label.evidence.map(\.text).joined(separator: " ") + " " + label.excerpt)
                if article.isPartial { budget.record(.partialContent) }
                if alignment == .unknown { budget.record(.temporalUncertainty) }
                if alignment == .incompatible { budget.record(.temporalMismatch) }
                let sourceDomain = domain(article.item)
                let origin = article.originalSource.map(HybridRetrieval.canonicalURL)
                    ?? TrustedDomain.profile(for: sourceDomain == "gov.br" ? URL(string: article.finalURL)?.host ?? sourceDomain : sourceDomain).editorialOrigin
                let source = SourceResult(url: article.finalURL, domain: sourceDomain, title: article.title ?? article.item.title,
                                          label: label.label, confidence: label.confidence, similarity: label.similarity, excerpt: label.excerpt,
                                          stance: label.stance, provenance: article.provenance, isPartial: article.isPartial,
                                          publishedAt: article.publishedAt, temporalAlignment: alignment, originGroup: origin, evidence: label.evidence,
                                          reason: article.isPartial ? "Conteúdo parcial: usado apenas como reforço." : alignment != .compatible ? "O período da evidência não pôde ser confirmado." : nil)
                sources.append(source); previous.append((article, source))
            }
        } catch let error as VerificationError where error == .deadlineExceeded || error == .inferenceBudgetExceeded {
            budget.record(error == .deadlineExceeded ? .deadline : .inferenceBudget)
        } catch {
            try Task.checkCancellation()
            throw error as? VerificationError ?? .modelLoadFailed
        }
        return sources
    }

    /// Short, single-assertion premises: the NLI model was trained on sentence pairs, and long
    /// windows mix facts. Candidates are the title plus the sentences of the selected windows
    /// (and the window right after each, where rebuttals often follow a quoted claim).
    private func sentencePremises(_ selected: [EmbeddingService.ScoredChunk], in windows: [String], title: String,
                                  claim: String, claimVector: [Float]?, budget: VerificationBudget) throws -> [EmbeddingService.ScoredChunk]? {
        guard let claimVector else { return nil }
        let rules = EvidenceRules.default
        var indices = Set<Int>()
        for chunk in selected {
            guard let index = windows.firstIndex(of: chunk.text) else { continue }
            indices.insert(index)
            if index + 1 < windows.count { indices.insert(index + 1) }
        }
        var candidates = [EvidenceScorer.cleanPremise(title)]
        for index in indices.sorted() {
            let sentences = TextChunker.sentences(in: windows[index]).map(EvidenceScorer.cleanPremise)
            for (offset, sentence) in sentences.enumerated() {
                let dependent = offset > 0 && ClaimAnalyzer.matches(#"^(ele|ela|eles|elas|isso|isto|esse|essa|esses|essas|o mesmo|a mesma|alem disso|porem|mas|no entanto|contudo|entretanto|tambem)\b"#, in: ClaimAnalyzer.folded(sentence))
                candidates.append(dependent ? sentences[offset - 1] + " " + sentence : sentence)
            }
        }
        var seen = Set<String>()
        candidates = candidates.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { EvidenceScorer.isAssertion($0) && seen.insert($0).inserted }
        guard !candidates.isEmpty,
              let similarities = try embeddings.similarities(of: candidates, claimVector: claimVector, budget: budget) else { return nil }
        let lexical = HybridRetrieval.bm25(query: claim, documents: candidates)
        let ranked = candidates.indices
            .filter { similarities[$0] >= rules.minimumSentenceSimilarity || lexical[$0] > 0 }
            .sorted { similarities[$0] + 0.05 * min(lexical[$0], 6) > similarities[$1] + 0.05 * min(lexical[$1], 6) }
            .prefix(rules.premisesPerArticle)
        return ranked.map { EmbeddingService.ScoredChunk(text: candidates[$0], similarity: similarities[$0]) }
    }

    /// The displayed label/stance follow the passages that actually pass the evidence gates,
    /// not the raw NLI argmax.
    static func relabel(_ label: NLIService.ArticleLabel, features: ClaimFeatures) -> NLIService.ArticleLabel {
        guard !label.evidence.isEmpty else { return label }
        let scored = label.evidence.map { ($0, EvidenceScorer.score($0, features: features)) }
        let support = scored.max { $0.1.support < $1.1.support }
        let refute = scored.max { $0.1.refute < $1.1.refute }
        let s = support?.1.support ?? 0, r = refute?.1.refute ?? 0
        guard s > 0 || r > 0 else {
            let fallback = label.evidence.max { $0.similarity < $1.similarity }!
            return NLIService.ArticleLabel(label: .neutral, confidence: fallback.probabilities.neutral, similarity: fallback.similarity,
                                           excerpt: fallback.text, stance: .insufficient, evidence: label.evidence)
        }
        let mixed = s > 0 && r > 0 && min(s, r) >= EvidenceRules.default.mixedMinimum
        let best = s >= r ? support!.0 : refute!.0
        return NLIService.ArticleLabel(label: s >= r ? .entailment : .contradiction, confidence: min(1, max(s, r)),
                                       similarity: best.similarity, excerpt: best.text,
                                       stance: mixed ? .mixed : s >= r ? .supports : .refutes, evidence: label.evidence)
    }

    private func expand(_ selected: [EmbeddingService.ScoredChunk], in windows: [String], claim: String) -> [EmbeddingService.ScoredChunk] {
        let available = max(1, 509 - nli.tokenCount(claim))
        var seen = Set<String>()
        return selected.compactMap { selected in
            var text = selected.text
            if let index = windows.firstIndex(of: text) {
                // Prefer the following paragraph: rebuttals frequently follow a quoted claim.
                for neighbor in [index + 1, index - 1] where windows.indices.contains(neighbor) {
                    let candidate = neighbor > index ? text + " " + windows[neighbor] : windows[neighbor] + " " + text
                    if nli.tokenCount(candidate) <= available { text = candidate }
                }
            }
            guard seen.insert(text).inserted else { return nil }
            return EmbeddingService.ScoredChunk(text: text, similarity: selected.similarity)
        }
    }

    private func domain(_ item: SearchResultItem) -> String {
        item.resolvedURL.flatMap(AllowlistFilter.matchedDomain) ?? item.resolvedURL?.host ?? ""
    }
    private func makeResult(context: ClaimContext, sources: [SourceResult], collection: Collection, budget: VerificationBudget) -> VerificationResult {
        let features = ClaimFeatures(claim: context.text, rarity: embeddings.termRarity)
        var result = VerificationResult(id: UUID(), claim: context.text, createdAt: context.referenceDate,
                                        verdict: sources.isEmpty && !collection.items.isEmpty ? .semInformacao
                                            : VerdictAggregator.verdict(for: sources, features: features, temporalKind: context.temporalKind),
                                        consultedDomains: search.consultedDomains, sources: sources, context: context)
        if !EvidencePolicy.current.calibrated && !sources.allSatisfy({ $0.provenance == .reviewedCatalog }) { budget.record(.uncalibratedPolicy) }
        let contributing = VerdictAggregator.contributingURLs(sources, features: features, temporalKind: context.temporalKind)
        result.diagnostics = VerificationDiagnostics(foundArticles: collection.items.count, readArticles: collection.articles.count,
                                                    usedSources: contributing.count,
                                                    independentOrigins: Set(sources.filter { contributing.contains($0.url) }.map(\.originGroup)).count,
                                                    searchCalls: budget.searchCalls, nliPairs: budget.nliPairs,
                                                    elapsedSeconds: budget.elapsed, limitations: budget.limitations)
        return result
    }
}
