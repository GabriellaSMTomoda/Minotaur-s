//
//  VerificationPipelineTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// CA-01 / CA-02 / CA-09 e o mapeamento de erros da RF-10, com **todos** os serviços mockados.
///
/// Nenhum teste desta suíte toca a rede, o proxy da Tavily ou os modelos Core ML: o que está
/// sob teste é a orquestração — ordem das etapas, short-circuit, cancelamento e categoria de
/// erro. A qualidade dos modelos e o formato da resposta da Tavily são medidos em
/// `MLServicesTests` e `TavilySearchServiceTests`, onde as dependências reais são o objetivo.
struct VerificationPipelineTests {

    /// 59 caracteres — acima do mínimo da RF-01.2 e no tamanho descrito pela CA-01.
    private static let claim = "O desemprego caiu para 6,2% no trimestre encerrado em maio."

    private static let articleText = """
    O Instituto Brasileiro de Geografia e Estatística divulgou nesta quinta-feira os dados da \
    Pnad Contínua referentes ao trimestre encerrado em maio.
    A taxa de desocupação ficou em 6,2%, segundo o levantamento, com recuo em relação ao \
    trimestre anterior e ao mesmo período do ano passado.
    """

    // MARK: - CA-01: verificação com afirmação confirmada

    @Test("CA-01: fluxo completo com fontes confirmando devolve CONFIRMADO com as fontes")
    func confirmedVerificationRunsFullPipeline() async throws {
        let items = [
            item("https://g1.globo.com/economia/desemprego", title: "Desemprego cai a 6,2%"),
            item("https://bbc.com/portuguese/desemprego", title: "Taxa de desocupação recua"),
            item("https://estadao.com.br/economia/pnad", title: "Pnad mostra queda"),
        ]
        let search = MockSearch(returning: items)
        let extractor = MockExtractor(texts: Dictionary(
            uniqueKeysWithValues: items.map { ($0.url, Self.articleText) }
        ))
        let embeddings = MockEmbeddings { _, _ in [scored(similarity: 0.81)] }
        let nli = MockNLI { _, _ in label(.entailment, confidence: 0.93, similarity: 0.81) }
        let stages = StageLog()

        let pipeline = VerificationPipeline(
            search: search, extractor: extractor, embeddings: embeddings, nli: nli
        )
        let result = try await pipeline.verify(claim: Self.claim, onProgress: stages.handler)

        // Veredito e fontes (RF-08.1 / RF-09.2).
        #expect(result.verdict == .confirmado)
        #expect(result.sources.count == 3)
        #expect(result.sources.allSatisfy { $0.label == .entailment })
        #expect(result.claim == Self.claim)

        // A ordem das fontes acompanha o ranking da busca, apesar da extração paralela.
        #expect(result.sources.map(\.domain) == ["g1.globo.com", "bbc.com", "estadao.com.br"])
        #expect(result.sources.map(\.title) == items.map(\.title))

        // Cada fonte carrega rótulo, score e trecho exibível (RF-09.2 / RF-09.4 / CA-10).
        for source in result.sources {
            #expect(source.confidence == 0.93)
            #expect(source.similarity == 0.81)
            #expect(!source.excerpt.isEmpty)
            #expect(source.excerpt.count <= 300)
            #expect(!source.url.isEmpty)
        }

        // Todas as etapas rodaram, uma vez por artigo.
        #expect(embeddings.callCount == 3)
        #expect(nli.callCount == 3)
        #expect(extractor.startedCount == 3)

        // RF-01.4: progresso na ordem buscando → lendo fontes → analisando.
        #expect(stages.recorded == [.searching, .readingSources, .analyzing])

        // RF-02: quem vai para a busca é a query reduzida, não a afirmação crua.
        #expect(search.lastQuery == SearchQueryBuilder.query(from: Self.claim))

        // O limite de 15 s da CA-01 (NF-03) não é asserível com mocks — é medição de rede e
        // device real. O que este teste garante é que o coordenador não acrescenta etapa
        // nenhuma além das do pipeline.
    }

    // MARK: - CA-02: nenhum resultado encontrado

    @Test("CA-02: zero resultados vira NÃO ENCONTRADO sem extração, embeddings ou NLI")
    func emptySearchShortCircuits() async throws {
        let search = MockSearch(returning: [])
        let extractor = MockExtractor(texts: [:])
        let embeddings = MockEmbeddings { _, _ in [scored()] }
        let nli = MockNLI { _, _ in label() }
        let stages = StageLog()

        let pipeline = VerificationPipeline(
            search: search, extractor: extractor, embeddings: embeddings, nli: nli
        )
        let result = try await pipeline.verify(claim: Self.claim, onProgress: stages.handler)

        #expect(result.verdict == .naoEncontrado)
        #expect(result.sources.isEmpty)

        // RF-04.4: "sem executar as etapas seguintes" — nenhuma delas foi tocada.
        #expect(extractor.startedCount == 0)
        #expect(embeddings.callCount == 0)
        #expect(nli.callCount == 0)

        // O progresso para em "buscando": não há fonte para ler nem nada para analisar.
        #expect(stages.recorded == [.searching])

        // CA-02 também exige informar quais domínios foram consultados — a allowlist inteira,
        // já que a restrição vai em `include_domains` numa única chamada (RF-02.3 / RF-09.6),
        // e chega pelo `VerificationResult` (DT-32), não por um utilitário estático à parte.
        #expect(result.consultedDomains.count == TrustedDomain.allowlist.count)
        #expect(!result.consultedDomains.isEmpty)
    }

    @Test("NF-08: pipeline envia ao corpo do proxy só a primeira frase limitada a 200")
    func searchRequestContainsOnlyReducedQuery() async throws {
        let (session, scenario) = MockURLProtocol.makeSession([
            .success(status: 200, body: Data(#"{"results":[]}"#.utf8)),
        ])
        let search = ServiceBackedSearch(
            service: TavilySearchService(
                session: session,
                endpoint: "https://proxy.exemplo.workers.dev"
            )
        )
        let pipeline = VerificationPipeline(
            search: search,
            extractor: MockExtractor(texts: [:]),
            embeddings: MockEmbeddings { _, _ in [scored()] },
            nli: MockNLI { _, _ in label() }
        )
        let privateRemainder = "DADO-QUE-NAO-PODE-SAIR"
        let longFirstSentence = String(repeating: "palavra ", count: 40) + "."
        let claim = "\(longFirstSentence) \(privateRemainder)"

        _ = try await pipeline.verify(claim: claim)

        let body = try #require(scenario.lastBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let transmitted = try #require(json["query"] as? String)

        #expect(transmitted == SearchQueryBuilder.query(from: claim))
        #expect(transmitted.count <= SearchQueryBuilder.maxQueryLength)
        #expect(!transmitted.contains(privateRemainder))
    }

    @Test("Busca com resultados, mas todos descartados na extração → NÃO ENCONTRADO")
    func allSourcesDiscardedIsNotFound() async throws {
        let items = [item("https://g1.globo.com/a"), item("https://bbc.com/b")]
        // Nenhum texto para nenhuma URL: é o que o extrator devolve em paywall, conteúdo via
        // JavaScript ou timeout (RF-05.3/RF-05.4).
        let extractor = MockExtractor(texts: [:])
        let nli = MockNLI { _, _ in label() }

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: MockEmbeddings { _, _ in [scored()] },
            nli: nli
        )
        let result = try await pipeline.verify(claim: Self.claim)

        // "Nenhuma fonte válida analisada → NÃO ENCONTRADO" (RF-08.1), distinto de busca vazia.
        #expect(result.verdict == .naoEncontrado)
        #expect(result.sources.isEmpty)
        #expect(nli.callCount == 0)
    }

    // MARK: - CA-09: cancelamento

    @Test("CA-09: cancelar durante a leitura aborta a rede pendente e não roda inferência")
    func cancellationDuringExtractionAbortsEverything() async throws {
        let items = [
            item("https://g1.globo.com/a"),
            item("https://bbc.com/b"),
            item("https://estadao.com.br/c"),
        ]
        // Requisições que ficam pendentes até serem canceladas, como um download real em curso.
        let extractor = MockExtractor(texts: [:], blocksUntilCancelled: true)
        let embeddings = MockEmbeddings { _, _ in [scored()] }
        let nli = MockNLI { _, _ in label() }

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: embeddings,
            nli: nli
        )

        let task = Task { try await pipeline.verify(claim: Self.claim) }
        try await waitUntil { extractor.startedCount == items.count }
        task.cancel()

        // Cancelar não é falha de rede nem veredito: é `CancellationError` (RF-10 não tem
        // categoria para cancelamento porque cancelamento não é erro a exibir).
        await #expect(throws: CancellationError.self) { try await task.value }

        // "Todas as requisições de rede pendentes são canceladas": as 3 estavam em voo.
        #expect(extractor.cancelledCount == items.count)
        #expect(extractor.finishedCount == 0)

        // "Nenhuma inferência adicional é executada."
        #expect(embeddings.callCount == 0)
        #expect(nli.callCount == 0)
    }

    @Test("CA-09: cancelamento antes do início não dispara nem a busca")
    func cancellationBeforeSearchDoesNothing() async {
        let search = MockSearch(returning: [item("https://g1.globo.com/a")])
        let extractor = MockExtractor(texts: [:])

        let pipeline = VerificationPipeline(
            search: search,
            extractor: extractor,
            embeddings: MockEmbeddings { _, _ in [scored()] },
            nli: MockNLI { _, _ in label() }
        )

        let task = Task { () throws -> VerificationResult in
            // Cancela a si mesmo antes de chamar: equivale ao usuário cancelar no instante em
            // que a verificação começa.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.verify(claim: Self.claim)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(search.callCount == 0)
        #expect(extractor.startedCount == 0)
    }

    @Test("CA-09: cancelar durante a análise não roda a inferência do próximo passo")
    func cancellationDuringAnalysisStopsInference() async {
        let items = [
            item("https://g1.globo.com/a"),
            item("https://bbc.com/b"),
            item("https://estadao.com.br/c"),
        ]
        let extractor = MockExtractor(texts: Dictionary(
            uniqueKeysWithValues: items.map { ($0.url, Self.articleText) }
        ))
        let nli = MockNLI { _, _ in label() }
        // O usuário toca em Cancelar enquanto o primeiro artigo está nos embeddings.
        let embeddings = MockEmbeddings { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return [scored()]
        }

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: embeddings,
            nli: nli
        )

        let task = Task { try await pipeline.verify(claim: Self.claim) }
        await #expect(throws: CancellationError.self) { try await task.value }

        // A inferência de NLI é a cara (RF-07): ela não pode começar depois do cancelamento,
        // nem para o artigo que estava em análise, nem para os dois seguintes.
        #expect(nli.callCount == 0)
        #expect(embeddings.callCount == 1)
    }

    // MARK: - Fontes descartadas não abortam o fluxo (CA-05 / CA-06 no coordenador)

    @Test("Fonte sem texto utilizável é descartada e as demais são analisadas")
    func discardedSourceDoesNotAbortFlow() async throws {
        let items = [
            item("https://g1.globo.com/a"),
            item("https://bbc.com/b"),   // paywall: sem texto
            item("https://estadao.com.br/c"),
        ]
        let extractor = MockExtractor(texts: [
            items[0].url: Self.articleText,
            items[2].url: Self.articleText,
        ])
        let nli = MockNLI { _, _ in label(.entailment) }

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: MockEmbeddings { _, _ in [scored()] },
            nli: nli
        )
        let result = try await pipeline.verify(claim: Self.claim)

        #expect(result.verdict == .confirmado)
        #expect(result.sources.count == 2)
        #expect(result.sources.map(\.domain) == ["g1.globo.com", "estadao.com.br"])
        // A fonte descartada não gera inferência nenhuma.
        #expect(nli.callCount == 2)
    }

    @Test("Artigo sem chunk acima do limiar não gera NLI nem vira fonte (RF-06.6 / CA-07)")
    func irrelevantArticleSkipsNLI() async throws {
        let items = [item("https://g1.globo.com/a"), item("https://bbc.com/b")]
        let extractor = MockExtractor(texts: Dictionary(
            uniqueKeysWithValues: items.map { ($0.url, Self.articleText) }
        ))
        let nli = MockNLI { _, _ in label(.entailment) }
        // Segundo artigo: nenhum chunk passou do limiar de similaridade (RF-06.7).
        let embeddings = MockEmbeddings.sequence([[scored()], []])

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: embeddings,
            nli: nli
        )
        let result = try await pipeline.verify(claim: Self.claim)

        #expect(result.sources.count == 1)
        #expect(result.sources.first?.domain == "g1.globo.com")
        // O artigo irrelevante custou embeddings, mas nenhuma inferência de NLI.
        #expect(embeddings.callCount == 2)
        #expect(nli.callCount == 1)
    }

    @Test("DT-33: artigo cujo único chunk é ruído não vira fonte e não custa inferência")
    func noiseOnlyArticleIsDiscardedLikeAFailedExtraction() async throws {
        let items = [
            item("https://g1.globo.com/a"),
            item("https://cnnbrasil.com.br/webstories/bahia"),
        ]
        let extractor = MockExtractor(texts: [
            items[0].url: Self.articleText,
            // O caso real: extração "bem-sucedida", mas o texto inteiro é o título da página.
            items[1].url: "Title: Torcida do Bahia faz mosaico para Everton Ribeiro após cura do câncer | Web Stories CNN Brasil",
        ])
        let embeddings = MockEmbeddings { _, _ in [scored()] }
        let nli = MockNLI { _, _ in label(.entailment) }

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: embeddings,
            nli: nli
        )
        let result = try await pipeline.verify(claim: Self.claim)

        // Mesmo caminho de uma extração fracassada (RF-05.3): a fonte some da lista sem abortar
        // a verificação — e sem votar na agregação da RF-08.3, que era o dano.
        #expect(result.sources.count == 1)
        #expect(result.sources.first?.domain == "g1.globo.com")

        // Descartado antes dos embeddings: o artigo de ruído não custa nenhuma das duas
        // inferências, nem a barata nem a cara.
        #expect(embeddings.callCount == 1)
        #expect(nli.callCount == 1)
    }

    @Test("Artigo cujo NLI não devolve rótulo não entra na lista de fontes")
    func articleWithoutLabelIsNotASource() async throws {
        let items = [item("https://g1.globo.com/a")]
        let extractor = MockExtractor(texts: [items[0].url: Self.articleText])

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: MockEmbeddings { _, _ in [scored()] },
            nli: MockNLI { _, _ in nil }
        )
        let result = try await pipeline.verify(claim: Self.claim)

        #expect(result.sources.isEmpty)
        #expect(result.verdict == .naoEncontrado)
    }

    // MARK: - RF-10: todo erro tem categoria

    @Test("Erro de busca já categorizado chega intacto à tela")
    func searchErrorsKeepTheirCategory() async {
        // CA-08 e RF-10.2 dependem de a categoria não ser reescrita pelo coordenador.
        for expected in [VerificationError.noConnection, .searchQuotaExceeded, .searchRequestFailed] {
            let pipeline = VerificationPipeline(
                search: MockSearch(failingWith: expected),
                extractor: MockExtractor(texts: [:]),
                embeddings: MockEmbeddings { _, _ in [scored()] },
                nli: MockNLI { _, _ in label() }
            )

            await #expect(throws: expected) { try await pipeline.verify(claim: Self.claim) }
        }
    }

    @Test("Erro cru de rede na busca vira falha de busca, nunca erro genérico")
    func rawSearchErrorIsCategorized() async {
        let pipeline = VerificationPipeline(
            search: MockSearch(failingWith: URLError(.badServerResponse)),
            extractor: MockExtractor(texts: [:]),
            embeddings: MockEmbeddings { _, _ in [scored()] },
            nli: MockNLI { _, _ in label() }
        )

        // RF-04.5 / RF-10.4: distinto de "não encontrado" e com categoria própria.
        await #expect(throws: VerificationError.searchRequestFailed) {
            try await pipeline.verify(claim: Self.claim)
        }
    }

    @Test("Falha de inferência vira modelLoadFailed e aborta a verificação")
    func inferenceFailureIsModelLoadFailed() async {
        let items = [item("https://g1.globo.com/a"), item("https://bbc.com/b")]
        let extractor = MockExtractor(texts: Dictionary(
            uniqueKeysWithValues: items.map { ($0.url, Self.articleText) }
        ))
        let nli = MockNLI { _, _ in label() }

        let pipeline = VerificationPipeline(
            search: MockSearch(returning: items),
            extractor: extractor,
            embeddings: MockEmbeddings { _, _ in throw NSError(domain: "CoreML", code: -1) },
            nli: nli
        )

        // RF-10.3: o modelo é o mesmo para todos os artigos, então falhar em um significa
        // análise quebrada — melhor a mensagem específica do que um veredito com menos fontes.
        await #expect(throws: VerificationError.modelLoadFailed) {
            try await pipeline.verify(claim: Self.claim)
        }
        #expect(nli.callCount == 0)
    }

    // MARK: - Auxiliares

    private func item(_ url: String, title: String = "Título") -> SearchResultItem {
        SearchResultItem(
            title: title,
            url: url,
            content: String(repeating: "conteúdo ", count: 40),
            score: 0.9
        )
    }

    private func scored(
        _ text: String = "A taxa de desocupação ficou em 6,2%, segundo o levantamento.",
        similarity: Double = 0.8
    ) -> EmbeddingService.ScoredChunk {
        EmbeddingService.ScoredChunk(text: text, similarity: similarity)
    }

    private func label(
        _ label: NLILabel = .entailment,
        confidence: Double = 0.9,
        similarity: Double = 0.8
    ) -> NLIService.ArticleLabel {
        NLIService.ArticleLabel(
            label: label,
            confidence: confidence,
            similarity: similarity,
            excerpt: "A taxa de desocupação ficou em 6,2%, segundo o levantamento."
        )
    }

    /// Espera uma condição ficar verdadeira, com teto de tempo para que um teste quebrado
    /// falhe em vez de travar a suíte inteira.
    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        struct WaitTimeout: Error {}

        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw WaitTimeout() }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

// MARK: - Mocks

/// Registro thread-safe das etapas de progresso (RF-01.4).
///
/// O `ProgressHandler` é `@Sendable` e chamado fora da main thread, então acumular num array
/// solto seria corrida de dados justamente no teste que verifica a ordem das etapas.
private final class StageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [VerificationStage] = []

    var recorded: [VerificationStage] { lock.withLock { stages } }

    var handler: VerificationPipeline.ProgressHandler {
        { stage in
            self.lock.withLock { self.stages.append(stage) }
        }
    }
}

private final class MockSearch: ArticleSearching, @unchecked Sendable {
    private let outcome: Result<[SearchResultItem], Error>
    private let lock = NSLock()
    private var calls = 0
    private var query: String?

    init(returning items: [SearchResultItem]) { outcome = .success(items) }
    init(failingWith error: Error) { outcome = .failure(error) }

    let consultedDomains = TrustedDomain.allowlist.sorted()

    var callCount: Int { lock.withLock { calls } }
    var lastQuery: String? { lock.withLock { query } }

    func search(query: String) async throws -> [SearchResultItem] {
        lock.withLock {
            calls += 1
            self.query = query
        }
        return try outcome.get()
    }
}

/// Usa o serviço HTTP real sobre `MockURLProtocol` para cobrir query builder → pipeline → JSON.
private struct ServiceBackedSearch: ArticleSearching, Sendable {
    let service: TavilySearchService
    let consultedDomains = TrustedDomain.allowlist.sorted()

    func search(query: String) async throws -> [SearchResultItem] {
        try await service.search(query: query)
    }
}

/// Extrator falso com a característica que mais importa para o coordenador: assim como o
/// `ArticleExtractor` real, **nunca lança** — qualquer falha, inclusive cancelamento, sai como
/// `nil`. É por isso que o coordenador precisa checar cancelamento por conta própria.
private final class MockExtractor: ArticleTextExtracting, @unchecked Sendable {
    /// Texto por URL. URL ausente = fonte descartada (paywall, JavaScript, timeout).
    private let texts: [String: String]
    /// Simula requisição em voo: espera até ser cancelada.
    private let blocksUntilCancelled: Bool

    private let lock = NSLock()
    private var started = 0
    private var finished = 0
    private var cancelled = 0

    init(texts: [String: String], blocksUntilCancelled: Bool = false) {
        self.texts = texts
        self.blocksUntilCancelled = blocksUntilCancelled
    }

    var startedCount: Int { lock.withLock { started } }
    var finishedCount: Int { lock.withLock { finished } }
    var cancelledCount: Int { lock.withLock { cancelled } }

    func extractText(from item: SearchResultItem) async -> String? {
        lock.withLock { started += 1 }

        if blocksUntilCancelled {
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                lock.withLock { cancelled += 1 }
                return nil
            }
        }

        lock.withLock { finished += 1 }
        return texts[item.url]
    }
}

private final class MockEmbeddings: ChunkSelecting, @unchecked Sendable {
    private let handler: @Sendable (String, [String]) throws -> [EmbeddingService.ScoredChunk]
    private let lock = NSLock()
    private var calls = 0

    init(handler: @escaping @Sendable (String, [String]) throws -> [EmbeddingService.ScoredChunk]) {
        self.handler = handler
    }

    /// Resposta diferente por artigo, na ordem das chamadas.
    static func sequence(_ responses: [[EmbeddingService.ScoredChunk]]) -> MockEmbeddings {
        let index = Counter()
        return MockEmbeddings { _, _ in
            let position = index.next()
            return responses.indices.contains(position) ? responses[position] : []
        }
    }

    var callCount: Int { lock.withLock { calls } }

    func selectTopChunks(claim: String, chunks: [String]) throws -> [EmbeddingService.ScoredChunk] {
        lock.withLock { calls += 1 }
        return try handler(claim, chunks)
    }
}

private final class MockNLI: ChunkClassifying, @unchecked Sendable {
    private let handler: @Sendable (String, [EmbeddingService.ScoredChunk]) throws -> NLIService.ArticleLabel?
    private let lock = NSLock()
    private var calls = 0

    init(
        handler: @escaping @Sendable (String, [EmbeddingService.ScoredChunk]) throws -> NLIService.ArticleLabel?
    ) {
        self.handler = handler
    }

    var callCount: Int { lock.withLock { calls } }

    func label(
        for claim: String,
        chunks: [EmbeddingService.ScoredChunk]
    ) throws -> NLIService.ArticleLabel? {
        lock.withLock { calls += 1 }
        return try handler(claim, chunks)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}
