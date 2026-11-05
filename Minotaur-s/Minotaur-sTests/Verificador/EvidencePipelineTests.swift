import Foundation
import Testing
@testable import Minotaur_s

struct EvidencePipelineTests {
    @Test("A entrada com várias frases exige escolha antes de qualquer busca")
    func selectionBeforeNetworking() async {
        let search = EvidenceSearch(items: [])
        let pipeline = pipeline(search: search)
        await #expect(throws: VerificationError.claimNeedsSelection) {
            try await pipeline.verify(claim: "A cidade inaugurou um hospital. A escola recebeu novos livros.")
        }
        #expect(search.calls == 0)
    }

    @Test("Atribuição, negação e nomes não são removidos da afirmação")
    func preservesMeaning() {
        let claim = "O médico afirmou que o tratamento não cura todos os pacientes."
        let analysis = ClaimAnalyzer.analyze(claim)
        #expect(analysis.candidates == [claim])
        #expect(!analysis.needsRephrasing)
        #expect(ClaimAnalyzer.context(for: claim).containsAttribution)
        #expect(SearchQueryBuilder.plan(for: ClaimAnalyzer.context(for: claim))[0].text == claim)
        #expect(ClaimAnalyzer.analyze("Ela disse que o tratamento funciona.").needsRephrasing)
    }

    @Test("Consultas respeitam 200 caracteres e resolvem ontem pela data de referência")
    func temporalQueries() throws {
        let date = try #require(ArticleExtractor.parseDate("2026-11-04T15:00:00Z"))
        let context = ClaimAnalyzer.context(for: "A cidade inaugurou um hospital ontem.", at: date)
        let queries = SearchQueryBuilder.plan(for: context)
        #expect(queries.count <= 3)
        #expect(queries.allSatisfy { $0.text.count <= 200 })
        #expect(queries[0].text.contains("2026-11-03"))
        #expect(!queries[0].text.contains("ontem"))
        #expect(context.alignment(publishedAt: ArticleExtractor.parseDate("2024-01-01"), text: "Notícia antiga") == .incompatible)
        #expect(context.alignment(publishedAt: nil, text: "Sem data") == .unknown)
    }

    @Test("O orçamento admite no máximo três buscas e 24 pares")
    func sharedCounters() async throws {
        let budget = VerificationBudget()
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 { group.addTask { (try? budget.reserveSearch()) != nil } }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        #expect(successes == 3)
        try budget.reservePairs(24)
        #expect(throws: VerificationError.inferenceBudgetExceeded) { try budget.reservePairs() }
    }

    @Test("O prazo usa relógio monotônico e impede novas inferências")
    func monotonicDeadline() throws {
        let clock = EvidenceClock()
        let budget = VerificationBudget(now: { clock.value })
        clock.advance(16)
        #expect(throws: VerificationError.deadlineExceeded) { try budget.reserveSearch() }
        #expect(throws: VerificationError.deadlineExceeded) { try budget.reservePairs() }
        #expect(budget.limitations.contains(.deadline))
    }

    @Test("Snippet com classificação forte não pode decidir sozinho")
    func snippetDoesNotVote() async throws {
        let item = item("https://g1.globo.com/noticia")
        let extractor = EvidenceExtractor(provenance: .searchSnippet, partial: true)
        let result = try await pipeline(search: EvidenceSearch(items: [item]), extractor: extractor).verify(claim: "O estudo apresentou novos resultados.")
        #expect(result.verdict == .semInformacao)
        #expect(result.sources.count == 1)
        #expect(result.diagnostics.usedSources == 0)
        #expect(result.diagnostics.limitations.contains(.partialContent))
    }

    @Test("Maioria de republicações não apaga uma refutação válida")
    func conflictsSurviveMajority() {
        let a = source(.entailment, origin: "origem-a")
        var duplicate = source(.entailment, origin: "origem-a")
        duplicate.duplicateOf = a.url
        let contrary = source(.contradiction, origin: "origem-b")
        #expect(VerdictAggregator.verdict(for: [a, duplicate, duplicate, contrary]) == .divergente)
        var partial = contrary; partial.isPartial = true
        #expect(VerdictAggregator.verdict(for: [a, partial]) == .confirmado)
        var old = contrary; old.temporalAlignment = .incompatible
        #expect(VerdictAggregator.verdict(for: [a, old]) == .confirmado)
        var mixed = a; mixed.stance = .mixed
        #expect(VerdictAggregator.verdict(for: [mixed]) == .divergente)
    }

    @Test("Republicação é mostrada, mas evita inferência e voto duplicados")
    func duplicatesShareEvidence() async throws {
        let result = try await pipeline(search: EvidenceSearch(items: [item("https://g1.globo.com/a"), item("https://bbc.com/b")]))
            .verify(claim: "O estudo apresentou novos resultados.")
        #expect(result.sources.count == 2)
        #expect(result.sources.filter { $0.duplicateOf != nil }.count == 1)
        #expect(result.diagnostics.nliPairs <= 3)
        #expect(result.diagnostics.independentOrigins == 1)
    }

    @Test("Rede pendente é cancelada pelo prazo e não vira NÃO ENCONTRADO")
    func globalNetworkDeadline() async {
        let pipeline = pipeline(search: EvidenceSearch(items: [], delay: 2),
                                makeBudget: { VerificationBudget(totalSeconds: 0.1, networkSeconds: 0.03) })
        let start = ProcessInfo.processInfo.systemUptime
        await #expect(throws: VerificationError.deadlineExceeded) {
            try await pipeline.verify(claim: "O estudo apresentou novos resultados.")
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 1)
    }

    @Test("Busca sem cobertura é distinta de artigos encontrados que não puderam ser lidos")
    func readingFailureIsDistinct() async {
        let extractor = EvidenceExtractor(fails: true)
        await #expect(throws: VerificationError.readingIncomplete) {
            try await pipeline(search: EvidenceSearch(items: [item("https://g1.globo.com/a")]), extractor: extractor)
                .verify(claim: "O estudo apresentou novos resultados.")
        }
    }

    @Test("JSON-LD é lido antes da limpeza, preservando datas, autoria e conteúdo")
    func structuredExtraction() throws {
        let html = #"<html><head><script type="application/ld+json">{"@type":"NewsArticle","headline":"Estudo","datePublished":"2026-11-04T12:00:00Z","author":{"name":"Autora"},"articleBody":"O estudo apresentou novos resultados, mas os pesquisadores ressaltaram que o tratamento permanece experimental. A pesquisa acompanhou apenas um pequeno grupo de pacientes e novos estudos ainda serão necessários para avaliar eficácia e segurança."}</script></head><body><main></main></body></html>"#
        let article = try ArticleExtractor.article(fromHTML: html, item: item("https://g1.globo.com/a"), finalURL: URL(string: "https://g1.globo.com/a")!)
        #expect(article.provenance == .structuredData)
        #expect(article.author == "Autora")
        #expect(article.publishedAt != nil)
        #expect(article.text.contains("experimental"))
        let paid = html.replacingOccurrences(of: "\"headline\"", with: "\"isAccessibleForFree\":false,\"headline\"")
        let partial = try ArticleExtractor.article(fromHTML: paid, item: item("https://g1.globo.com/a"), finalURL: URL(string: "https://g1.globo.com/a")!)
        #expect(partial.isPartial)
        #expect(partial.provenance != .structuredData)
        let preview = "<html><meta property='og:type' content='article'><article class='article-preview'><p>" + String(repeating: "O estudo apresentou os resultados completos aos pesquisadores. ", count: 8) + "</p></article></html>"
        let previewArticle = try ArticleExtractor.article(fromHTML: preview, item: item("https://g1.globo.com/a"), finalURL: URL(string: "https://g1.globo.com/a")!)
        #expect(previewArticle.text.count > 200)
        #expect(previewArticle.isPartial)
    }

    @Test("BM25 preserva números e o ranking híbrido resgata passagens complementares")
    func hybridRanking() {
        let scores = HybridRetrieval.bm25(query: "A taxa chegou a 6,2%", documents: ["A taxa chegou a 9,1%", "A taxa chegou a 6,2%"])
        #expect(scores[1] > scores[0])
        #expect(HybridRetrieval.fusedOrder(lexical: [4, 0], semantic: [0.1, 0.9]).count == 2)
        #expect(!HybridRetrieval.nearDuplicate("A cidade gastou 200 milhões na escola.", "A cidade gastou 900 milhões na escola."))
        let longBody = String(repeating: "O relatório descreve a metodologia e apresenta detalhes do levantamento. ", count: 40)
        #expect(!HybridRetrieval.nearDuplicate(longBody + "O investimento foi de 200 milhões.", longBody + "O investimento foi de 900 milhões."))
        #expect(!HybridRetrieval.nearDuplicate(longBody + "O estudo comprovou a hipótese.", longBody + "O estudo não comprovou a hipótese."))
    }

    @Test("Parágrafo jornalístico permanece utilizável antes da recuperação")
    func propositionSurvivesFiltering() {
        let text = "O estudo apresentou novos resultados, e os pesquisadores publicaram os dados completos para avaliação."
        #expect(ChunkQualityFilter.rejection(for: text) == nil)
        let chunks = TextChunker(maxTokens: 126).chunks(from: text)
        #expect(!ChunkQualityFilter.keeping(chunks).isEmpty)
    }

    @Test("Catálogo exige revisão independente, entidades e período exatos")
    func catalogDoesNotTransferOldChecks() throws {
        let entry = ReviewedFactCatalog.Entry(id: "unit", claim: "Em 2023, o programa Alfa funcionava no Brasil.",
                                             entities: ["Alfa"], eventYear: 2023, verdict: .confirmado,
                                             url: "https://g1.globo.com/unit", title: "Checagem", excerpt: "O programa Alfa funcionava no Brasil.",
                                             publishedAt: "2023-12-01", status: "reviewed", reviewerIDs: ["fixture-a", "fixture-b"])
        let catalog = ReviewedFactCatalog(entries: [entry])
        #expect(catalog.match(ClaimAnalyzer.context(for: entry.claim)) != nil)
        #expect(catalog.match(ClaimAnalyzer.context(for: "Em 2024, o programa Alfa funcionava no Brasil.")) == nil)
        #expect(catalog.match(ClaimAnalyzer.context(for: "Em 2023, o programa Beta funcionava no Brasil.")) == nil)
        #expect(catalog.match(ClaimAnalyzer.context(for: "O programa Alfa funciona atualmente no Brasil.")) == nil)
        #expect(ReviewedFactCatalog.load().entries.allSatisfy { $0.status != "reviewed" || Set($0.reviewerIDs).count >= 2 })
    }

    @Test("Critério de fonte única é aplicado a cada passagem, não ao maior score do artigo")
    func singleThresholdDoesNotBorrowOppositeConfidence() {
        let policy = EvidencePolicy(version: "fixture", modelVersion: "fixture", temperature: 1,
                                    minimumConfidence: 0.5, singleSourceMinimumConfidence: 0.9, calibrated: false)
        var source = source(.entailment, origin: "single")
        source.stance = .mixed
        source.evidence = [EvidencePassage(text: "Apoio.", probabilities: .init(entailment: 0.95, neutral: 0.03, contradiction: 0.02), similarity: 0.8),
                           EvidencePassage(text: "Refutação fraca.", probabilities: .init(entailment: 0.15, neutral: 0.20, contradiction: 0.65), similarity: 0.8)]
        #expect(VerdictAggregator.verdict(for: [source], policy: policy) == .confirmado)
        let neutral = self.source(.neutral, origin: "other")
        #expect(VerdictAggregator.verdict(for: [source, neutral], policy: policy) == .confirmado)
    }

    @Test("Política calibrada exige versão compatível e digest de calibração")
    func policyVersionGuard() {
        var policy = EvidencePolicy(version: "fixture", modelVersion: "model-a", temperature: 1,
                                    minimumConfidence: 0.6, singleSourceMinimumConfidence: 0.8, calibrated: true)
        #expect(!policy.isValid(for: "model-a"))
        policy.calibrationDigest = String(repeating: "a", count: 64)
        #expect(policy.isValid(for: "model-a"))
        #expect(!policy.isValid(for: "model-b"))
    }

    @MainActor
    @Test("ViewModel pede seleção e verifica somente a frase escolhida")
    func viewModelSelectsOneClaim() async throws {
        let model = VerificationViewModel(runner: VerificationRunner {
            VerificationPipeline(search: EvidenceSearch(items: []), extractor: EvidenceExtractor(),
                                 embeddings: EvidenceEmbeddings(), nli: EvidenceNLI())
        })
        model.claimText = "A cidade inaugurou um hospital. A escola recebeu novos livros."
        model.verify()
        #expect(model.claimCandidates.count == 2)
        #expect(!model.isVerifying)
        model.selectClaim(model.claimCandidates[1])
        for _ in 0..<100 where model.isVerifying { try await Task.sleep(nanoseconds: 2_000_000) }
        #expect(model.result?.claim == "A escola recebeu novos livros.")
        #expect(model.claimCandidates.isEmpty)
    }

    private func item(_ url: String) -> SearchResultItem {
        SearchResultItem(title: "O estudo apresentou resultados", url: url, content: "Estudo e resultados", score: 0.8)
    }
    private func source(_ label: NLILabel, origin: String) -> SourceResult {
        SourceResult(url: "https://g1.globo.com/" + origin, domain: "g1.globo.com", title: "Estudo", label: label,
                     confidence: 0.95, similarity: 0.8, excerpt: "O estudo apresentou resultados.", originGroup: origin)
    }
    private func pipeline(search: EvidenceSearch, extractor: EvidenceExtractor = EvidenceExtractor(),
                          makeBudget: @escaping @Sendable () -> VerificationBudget = { VerificationBudget() }) -> VerificationPipeline {
        VerificationPipeline(search: search, extractor: extractor, embeddings: EvidenceEmbeddings(), nli: EvidenceNLI(), makeBudget: makeBudget)
    }
}

private final class EvidenceClock: @unchecked Sendable {
    private let lock = NSLock(); private var time: TimeInterval = 0
    var value: TimeInterval { lock.withLock { time } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
}
private final class EvidenceSearch: ArticleSearching, @unchecked Sendable {
    let consultedDomains = ["g1.globo.com", "bbc.com"]
    let items: [SearchResultItem]; let delay: Double
    private let lock = NSLock(); private var count = 0
    var calls: Int { lock.withLock { count } }
    init(items: [SearchResultItem], delay: Double = 0) { self.items = items; self.delay = delay }
    func search(query: String) async throws -> [SearchResultItem] {
        lock.withLock { count += 1 }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return items
    }
}
private struct EvidenceExtractor: ArticleTextExtracting {
    var provenance: TextProvenance = .articleBody; var partial = false; var fails = false
    func extractText(from item: SearchResultItem) async -> String? { "O estudo apresentou novos resultados, e os pesquisadores publicaram os dados completos para avaliação." }
    func extract(_ item: SearchResultItem, budget: VerificationBudget) async -> ArticleExtraction {
        if fails { return ArticleExtraction(article: nil, discardReason: .network) }
        return ArticleExtraction(article: ExtractedArticle(item: item, text: await extractText(from: item)!, finalURL: item.url,
                                                           provenance: provenance, isPartial: partial))
    }
}
private struct EvidenceEmbeddings: ChunkSelecting {
    func selectTopChunks(claim: String, chunks: [String]) throws -> [EmbeddingService.ScoredChunk] {
        chunks.prefix(3).map { .init(text: $0, similarity: 0.8) }
    }
}
private struct EvidenceNLI: ChunkClassifying {
    func label(for claim: String, chunks: [EmbeddingService.ScoredChunk]) throws -> NLIService.ArticleLabel? {
        chunks.first.map { .init(label: .entailment, confidence: 0.95, similarity: $0.similarity, excerpt: $0.text) }
    }
}
