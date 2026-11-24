import Foundation
import Testing
@testable import Minotaur_s

/// Rules added after the dev-set error analysis (evidence v3, harness run v3b) and the
/// Wikipédia PT source. Mirrors `evaluation/harness/evidence.py`.
struct EvidenceV3RulesTests {
    private func passage(_ text: String, e: Double = 0.02, c: Double = 0.02, similarity: Double = 0.8) -> EvidencePassage {
        EvidencePassage(text: text, probabilities: .init(entailment: e, neutral: 1 - e - c, contradiction: c), similarity: similarity)
    }

    @Test("Frase que relata o boato circulando não apoia a afirmação")
    func reportedClaimDoesNotSupport() {
        let features = ClaimFeatures(claim: "Lula decreta fim do seguro-desemprego")
        let score = EvidenceScorer.score(passage("Circula nas redes sociais que Lula decreta fim do seguro-desemprego.", e: 0.97), features: features)
        #expect(score.support == 0)
        #expect(score.reasons.contains("support_blocked_reported"))
    }

    @Test("Checagem que cita o boato e o rotula como falso refuta")
    func debunkedReportRefutes() {
        let features = ClaimFeatures(claim: "Lula decreta fim do seguro-desemprego")
        var source = SourceResult(url: "https://aosfatos.org/a", domain: "aosfatos.org", title: "É falso que Lula acabou com o seguro-desemprego",
                                  label: .entailment, confidence: 0.97, similarity: 0.8, excerpt: "x", originGroup: "aosfatos")
        source.evidence = [passage("Circula nas redes sociais que Lula decreta fim do seguro-desemprego.", e: 0.97)]
        #expect(VerdictAggregator.verdict(for: [source], features: features) == .contradito)
    }

    @Test("Posição no ranking refuta um superlativo")
    func rankMismatch() {
        let features = ClaimFeatures(claim: "O Brasil é o maior produtor de petróleo do mundo.")
        let score = EvidenceScorer.score(passage("Segundo a EIA, o Brasil é o 7º maior produtor de petróleo do mundo.", e: 0.89), features: features)
        #expect(score.support == 0)
        #expect(score.refute == EvidenceRules.default.rankMismatchScore)
    }

    @Test("Mesmo predicado sem outro sujeito nomeado não refuta")
    func samePredicateNeedsCompetitor() {
        let features = ClaimFeatures(claim: "A Terra gira em torno do Sol.")
        let score = EvidenceScorer.score(passage("Outro movimento que lhe ensinaram foi o de rotação: a Terra gira em torno de seu próprio eixo.", c: 0.95), features: features)
        #expect(score.refute == 0)
    }

    @Test("Sujeito depois do predicado não conta como mesmo sujeito")
    func subjectOrder() {
        let features = ClaimFeatures(claim: "Salvador foi a primeira capital do Brasil.")
        let score = EvidenceScorer.score(passage("Como foi a mudança da capital do Brasil de Salvador ao Rio de Janeiro há 260 anos", c: 0.83), features: features)
        #expect(score.refute == 0)
    }

    @Test("Negação hesitante não recebe reforço")
    func hedgedNegation() {
        let features = ClaimFeatures(claim: "O Monte Everest é a montanha mais alta do mundo.")
        let score = EvidenceScorer.score(passage("O Monte Everest pode não ser a montanha mais alta do mundo, dizem geólogos.", c: 0.9), features: features)
        #expect(!score.reasons.contains("explicit_negation"))
        #expect(score.refute <= 0.9)
    }

    @Test("Créditos e chamadas de canal saem da premissa")
    func boilerplateIsRemoved() {
        #expect(EvidenceScorer.cleanPremise("O Brics não tem orçamento próprio. >> Siga o canal da Agência Brasil no WhatsApp") == "O Brics não tem orçamento próprio.")
        #expect(EvidenceScorer.cleanPremise("O SUS foi criado em 1988 — Foto: Fernando Frazão/Agência Brasil") == "O SUS foi criado em 1988")
        #expect(EvidenceScorer.cleanPremise("Ibama concede licença prévia | G1") == "Ibama concede licença prévia")
    }

    @Test("Afirmação histórica com ano errado aceita matéria posterior")
    func historicalAlignment() throws {
        let context = ClaimAnalyzer.context(for: "O Plano Real foi lançado em 2004.")
        #expect(context.temporalKind == .historical)
        #expect(context.alignment(publishedAt: ArticleExtractor.parseDate("2014-07-01"), text: "O Plano Real foi lançado em 1994.") == .compatible)
        #expect(context.alignment(publishedAt: nil, text: "O Plano Real foi lançado em 1994.") == .compatible)
        #expect(context.alignment(publishedAt: ArticleExtractor.parseDate("1999-01-01"), text: "Plano econômico") == .incompatible)
    }

    // MARK: - Wikipédia

    @Test("Wikipédia usa a rota /wiki do proxy e devolve artigos completos")
    func wikipediaService() async throws {
        let body = #"{"query":"q","results":[{"title":"Salvador","url":"https://pt.wikipedia.org/wiki/Salvador","content":"Salvador","raw_content":"\#(String(repeating: "Salvador foi a primeira capital do Brasil. ", count: 8))","score":1}]}"#
        let (session, scenario) = MockURLProtocol.makeSession([.success(status: 200, body: Data(body.utf8))])
        let service = WikipediaSearchService(session: session, endpoint: "https://proxy.example/wiki")
        let articles = await service.articles(for: ClaimAnalyzer.context(for: "Salvador foi a primeira capital do Brasil."), budget: VerificationBudget())
        #expect(articles.count == 1)
        #expect(articles.first?.finalURL == "https://pt.wikipedia.org/wiki/Salvador")
        #expect(scenario.lastRequest?.url?.path == "/wiki")
        let sent = try #require(scenario.lastBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect((sent["query"] as? String)?.contains("Salvador") == true)
        #expect(sent.keys.sorted() == ["query"])
        #expect(TrustedDomain.profile(for: "pt.wikipedia.org").kind == .encyclopedia)
    }

    @Test("Falha da Wikipédia não vira erro nem resultado")
    func wikipediaFailureIsSilent() async {
        let (session, _) = MockURLProtocol.makeSession([.success(status: 502, body: Data())])
        let service = WikipediaSearchService(session: session, endpoint: "https://proxy.example/wiki")
        #expect(await service.articles(for: ClaimAnalyzer.context(for: "A Lua é o satélite natural da Terra."), budget: VerificationBudget()).isEmpty)
    }

    @Test("Artigo enciclopédico é analisado mesmo sem resultados de notícia")
    func pipelineUsesEncyclopedia() async throws {
        let pipeline = VerificationPipeline(search: EmptySearch(), extractor: NoExtractor(), embeddings: StubEmbeddings(),
                                            nli: StubNLI(), encyclopedia: StubEncyclopedia())
        let result = try await pipeline.verify(claim: "O estudo apresentou novos resultados.")
        #expect(result.sources.count == 1)
        #expect(result.sources.first?.domain == "pt.wikipedia.org")
        #expect(result.verdict == .confirmado)
        #expect(result.diagnostics.searchCalls <= 3)
    }
}

private struct EmptySearch: ArticleSearching {
    let consultedDomains = ["g1.globo.com"]
    func search(query: String) async throws -> [SearchResultItem] { [] }
}
private struct NoExtractor: ArticleTextExtracting {
    func extractText(from item: SearchResultItem) async -> String? { nil }
}
private struct StubEncyclopedia: EncyclopediaSearching {
    func articles(for context: ClaimContext, budget: VerificationBudget) async -> [ExtractedArticle] {
        let url = "https://pt.wikipedia.org/wiki/Estudo"
        let item = SearchResultItem(title: "Estudo", url: url, content: "Estudo", score: 1)
        return [ExtractedArticle(item: item, text: "O estudo apresentou novos resultados, e os pesquisadores publicaram os dados completos para avaliação.", finalURL: url)]
    }
}
private struct StubEmbeddings: ChunkSelecting {
    func selectTopChunks(claim: String, chunks: [String]) throws -> [EmbeddingService.ScoredChunk] {
        chunks.prefix(3).map { .init(text: $0, similarity: 0.8) }
    }
}
private struct StubNLI: ChunkClassifying {
    func label(for claim: String, chunks: [EmbeddingService.ScoredChunk]) throws -> NLIService.ArticleLabel? {
        chunks.first.map { .init(label: .entailment, confidence: 0.95, similarity: $0.similarity, excerpt: $0.text) }
    }
}
