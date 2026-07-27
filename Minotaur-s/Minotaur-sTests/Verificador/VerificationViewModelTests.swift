//
//  VerificationViewModelTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// O estado da tela: habilitação do botão (CA-03), progresso (RF-01.4), cancelamento (CA-09) e
/// categoria de erro (CA-08 / RF-10.3).
///
/// Roda com o `VerificationPipeline` real, mas com as quatro portas mockadas — o que está sob
/// teste é o modelo de tela, não o coordenador (isso é `VerificationPipelineTests`) nem os
/// modelos de ML (`MLServicesTests`). Nada aqui toca rede, proxy da Tavily ou Core ML.
@MainActor
struct VerificationViewModelTests {

    private static let claim = "O desemprego caiu para 6,2% no trimestre encerrado em maio."

    // MARK: - CA-03: botão desabilitado fora do intervalo válido

    @Test("CA-03: texto curto demais mantém o botão desabilitado, com o motivo na tela")
    func shortClaimKeepsButtonDisabled() {
        let viewModel = makeViewModel()

        viewModel.claimText = "Boato no zap"  // 12 caracteres

        #expect(!viewModel.canVerify)
        #expect(viewModel.validation.message?.contains("15") == true)
    }

    @Test("CA-03: entrada válida habilita o botão")
    func validClaimEnablesButton() {
        let viewModel = makeViewModel()

        viewModel.claimText = Self.claim

        #expect(viewModel.canVerify)
        #expect(viewModel.validation.message == nil)
    }

    @Test("CA-03: texto acima de 1.000 caracteres desabilita o botão")
    func longClaimDisablesButton() {
        let viewModel = makeViewModel()

        viewModel.claimText = String(repeating: "a", count: 1_001)

        #expect(!viewModel.canVerify)
    }

    @Test("Tocar em Verificar com entrada inválida não dispara verificação")
    func invalidClaimNeverStartsVerification() async throws {
        let search = MockSearch(returning: [])
        let viewModel = makeViewModel(search: search)

        viewModel.claimText = "curto"
        viewModel.verify()

        #expect(!viewModel.isVerifying)
        #expect(search.callCount == 0)
    }

    // MARK: - Fluxo completo (RF-01.3 / RF-01.4 / RF-09.6)

    @Test("Verificação bem-sucedida entrega resultado com veredito, fontes e domínios")
    func successfulVerificationProducesResult() async throws {
        let viewModel = makeViewModel(
            search: MockSearch(returning: [item("https://g1.globo.com/economia/desemprego")])
        )
        viewModel.claimText = Self.claim

        viewModel.verify()
        // O botão sai de cena assim que a verificação começa (RF-01.4).
        #expect(viewModel.isVerifying)
        #expect(!viewModel.canVerify)

        try await waitUntil { viewModel.result != nil }

        let result = try #require(viewModel.result)
        #expect(result.verdict == .confirmado)
        #expect(result.sources.count == 1)
        // RF-09.6 / DT-32: a tela recebe os domínios consultados dentro do resultado.
        #expect(!result.consultedDomains.isEmpty)

        // Terminou: nada de progresso preso na tela, nem erro.
        #expect(!viewModel.isVerifying)
        #expect(viewModel.failure == nil)
        // O texto continua no campo: só o usuário apaga.
        #expect(viewModel.claimText == Self.claim)
    }

    @Test("Voltar da tela de resultado limpa o resultado e libera nova verificação")
    func dismissingResultAllowsANewVerification() async throws {
        let viewModel = makeViewModel()
        viewModel.claimText = Self.claim

        viewModel.verify()
        try await waitUntil { viewModel.result != nil }

        viewModel.dismissResult()

        #expect(viewModel.result == nil)
        #expect(viewModel.canVerify)
        #expect(viewModel.claimText == Self.claim)
    }

    // MARK: - CA-09: cancelamento

    @Test("CA-09: cancelar volta à tela inicial com o texto preservado")
    func cancelPreservesTheTypedText() async throws {
        // Extração que fica pendente até ser cancelada: é o meio da verificação.
        let extractor = MockExtractor(blocksUntilCancelled: true)
        let viewModel = makeViewModel(
            search: MockSearch(returning: [item("https://g1.globo.com/a")]),
            extractor: extractor
        )
        viewModel.claimText = Self.claim

        viewModel.verify()
        try await waitUntil { extractor.startedCount == 1 }

        viewModel.cancel()

        // "retorna à tela inicial com o texto preservado"
        #expect(viewModel.claimText == Self.claim)
        #expect(!viewModel.isVerifying)
        #expect(viewModel.stage == nil)
        #expect(viewModel.result == nil)
        // Cancelar não é erro: nenhuma mensagem de falha aparece (RF-10.4).
        #expect(viewModel.failure == nil)
        #expect(viewModel.canVerify)

        // A requisição pendente foi de fato cancelada, e o resultado tardio não aparece.
        try await waitUntil { extractor.cancelledCount == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.result == nil)
    }

    // MARK: - CA-08 / RF-10: erros com categoria

    @Test("CA-08: falta de conexão vira mensagem específica, não 'não encontrado'")
    func noConnectionSurfacesItsOwnMessage() async throws {
        let viewModel = makeViewModel(search: MockSearch(failingWith: VerificationError.noConnection))
        viewModel.claimText = Self.claim

        viewModel.verify()
        try await waitUntil { viewModel.failure != nil }

        #expect(viewModel.failure == .noConnection)
        // Não virou veredito: "não encontrado" é resultado, isto é falha (RF-04.5).
        #expect(viewModel.result == nil)
        #expect(!viewModel.isVerifying)
        // A funcionalidade continua disponível — dá para tentar de novo (RF-10.1).
        #expect(viewModel.isAvailable)
        #expect(viewModel.canVerify)
    }

    @Test("RF-10.2: quota esgotada chega à tela com a própria categoria")
    func quotaExceededKeepsItsCategory() async throws {
        let viewModel = makeViewModel(
            search: MockSearch(failingWith: VerificationError.searchQuotaExceeded)
        )
        viewModel.claimText = Self.claim

        viewModel.verify()
        try await waitUntil { viewModel.failure != nil }

        #expect(viewModel.failure == .searchQuotaExceeded)
    }

    @Test("RF-10.3: falha ao carregar o modelo bloqueia a funcionalidade sem derrubar o app")
    func modelLoadFailureBlocksTheFeature() async {
        struct LoadFailure: Error {}
        let viewModel = VerificationViewModel(
            runner: VerificationRunner { throw LoadFailure() }
        )
        viewModel.claimText = Self.claim

        await viewModel.prepare()

        #expect(viewModel.failure == .modelLoadFailed)
        #expect(!viewModel.isAvailable)
        // "bloqueio da funcionalidade": o botão não habilita nem com entrada válida.
        #expect(!viewModel.canVerify)
        // "não deve travar o app": o texto e o resto do estado continuam íntegros.
        #expect(viewModel.claimText == Self.claim)
    }

    @Test("Dispensar o erro limpa a mensagem sem repetir a verificação")
    func dismissingErrorClearsIt() async throws {
        let search = MockSearch(failingWith: VerificationError.searchRequestFailed)
        let viewModel = makeViewModel(search: search)
        viewModel.claimText = Self.claim

        viewModel.verify()
        try await waitUntil { viewModel.failure != nil }

        viewModel.dismissError()

        #expect(viewModel.failure == nil)
        #expect(search.callCount == 1)
    }

    // MARK: - Auxiliares

    private func makeViewModel(
        search: MockSearch? = nil,
        extractor: MockExtractor = MockExtractor()
    ) -> VerificationViewModel {
        let search = search ?? MockSearch(returning: [Self.item("https://g1.globo.com/a")])

        return VerificationViewModel(
            runner: VerificationRunner {
                VerificationPipeline(
                    search: search,
                    extractor: extractor,
                    embeddings: MockEmbeddings(),
                    nli: MockNLI()
                )
            }
        )
    }

    private func item(_ url: String) -> SearchResultItem {
        Self.item(url)
    }

    private static func item(_ url: String) -> SearchResultItem {
        SearchResultItem(
            title: "Desemprego cai a 6,2%",
            url: url,
            content: String(repeating: "conteúdo ", count: 40),
            score: 0.9
        )
    }

    /// Espera uma condição, com teto de tempo para o teste falhar em vez de travar a suíte.
    private func waitUntil(_ condition: () -> Bool) async throws {
        struct WaitTimeout: Error {}

        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw WaitTimeout() }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

// MARK: - Mocks

/// Busca que devolve resultados fixos ou falha com a categoria pedida.
private final class MockSearch: ArticleSearching, @unchecked Sendable {
    private let outcome: Result<[SearchResultItem], Error>
    private let lock = NSLock()
    private var calls = 0

    init(returning items: [SearchResultItem]) { outcome = .success(items) }
    init(failingWith error: Error) { outcome = .failure(error) }

    let consultedDomains = ["g1.globo.com", "bbc.com"]

    var callCount: Int { lock.withLock { calls } }

    func search(query: String) async throws -> [SearchResultItem] {
        lock.withLock { calls += 1 }
        return try outcome.get()
    }
}

/// Extrator que devolve sempre o mesmo texto — ou fica pendente até ser cancelado, para o
/// teste de cancelamento ter uma verificação de fato em andamento.
private final class MockExtractor: ArticleTextExtracting, @unchecked Sendable {
    private let blocksUntilCancelled: Bool
    private let lock = NSLock()
    private var started = 0
    private var cancelled = 0

    init(blocksUntilCancelled: Bool = false) {
        self.blocksUntilCancelled = blocksUntilCancelled
    }

    var startedCount: Int { lock.withLock { started } }
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

        return """
        O Instituto Brasileiro de Geografia e Estatística divulgou os dados da Pnad Contínua.
        A taxa de desocupação ficou em 6,2%, segundo o levantamento.
        """
    }
}

private struct MockEmbeddings: ChunkSelecting {
    func selectTopChunks(claim: String, chunks: [String]) throws -> [EmbeddingService.ScoredChunk] {
        [EmbeddingService.ScoredChunk(text: chunks.first ?? "", similarity: 0.81)]
    }
}

private struct MockNLI: ChunkClassifying {
    func label(
        for claim: String,
        chunks: [EmbeddingService.ScoredChunk]
    ) throws -> NLIService.ArticleLabel? {
        NLIService.ArticleLabel(
            label: .entailment,
            confidence: 0.93,
            similarity: 0.81,
            excerpt: chunks.first?.text ?? ""
        )
    }
}
