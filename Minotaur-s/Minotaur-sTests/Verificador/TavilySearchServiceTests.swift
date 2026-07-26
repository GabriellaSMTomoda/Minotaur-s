//
//  TavilySearchServiceTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// RF-04.3 / RF-04.5 / RF-04.6 / RF-10 / DT-19 / DT-27.
struct TavilySearchServiceTests {

    private let endpoint = "https://proxy.exemplo.workers.dev"

    private func makeService(
        _ responses: [MockURLProtocol.Outcome]
    ) -> (TavilySearchService, MockURLProtocol.Scenario) {
        let (session, scenario) = MockURLProtocol.makeSession(responses)
        return (TavilySearchService(session: session, endpoint: endpoint), scenario)
    }

    // MARK: - RF-04.6 / DT-27: retry

    @Test("Erro 5xx: exatamente 1 tentativa extra")
    func retriesOnceOnServerError() async throws {
        let (service, scenario) = makeService([
            .success(status: 503, body: Data()),
            .success(status: 200, body: MockURLProtocol.tavilyBody(urls: ["https://g1.globo.com/a"])),
        ])

        let results = try await service.search(query: "teste")

        #expect(scenario.requestCount == 2)
        #expect(results.count == 1)
    }

    @Test("Timeout: exatamente 1 tentativa extra")
    func retriesOnceOnTimeout() async throws {
        let (service, scenario) = makeService([
            .failure(.timedOut),
            .success(status: 200, body: MockURLProtocol.tavilyBody(urls: ["https://bbc.com/a"])),
        ])

        let results = try await service.search(query: "teste")

        #expect(scenario.requestCount == 2)
        #expect(results.count == 1)
    }

    @Test("5xx nas duas tentativas: para em 2, não insiste")
    func retriesAtMostOnce() async {
        let (service, scenario) = makeService([.success(status: 500, body: Data())])

        await #expect(throws: VerificationError.searchRequestFailed) {
            try await service.search(query: "teste")
        }
        // "Uma única tentativa adicional" (RF-04.6) — nunca um laço de retry.
        #expect(scenario.requestCount == 2)
    }

    @Test("401 nunca é reafetado")
    func neverRetriesOnUnauthorized() async {
        // Formato real documentado no Spike 5.
        let body = Data(#"{"detail":{"error":"Unauthorized: missing or invalid API key."}}"#.utf8)
        let (service, scenario) = makeService([.success(status: 401, body: body)])

        await #expect(throws: VerificationError.searchRequestFailed) {
            try await service.search(query: "teste")
        }
        // Repetir uma chave inválida não a torna válida (DT-27).
        #expect(scenario.requestCount == 1)
    }

    @Test("429 nunca é reafetado e vira quota esgotada")
    func neverRetriesOnRateLimit() async {
        let (service, scenario) = makeService([.success(status: 429, body: Data())])

        // RF-10.2: mensagem específica de limite atingido, não erro genérico.
        await #expect(throws: VerificationError.searchQuotaExceeded) {
            try await service.search(query: "teste")
        }
        #expect(scenario.requestCount == 1)
    }

    @Test("Sem conexão não é reafetado e é distinto de falha de busca")
    func noConnectionIsDistinct() async {
        let (service, scenario) = makeService([.failure(.notConnectedToInternet)])

        // CA-08: mensagem específica de ausência de conexão.
        await #expect(throws: VerificationError.noConnection) {
            try await service.search(query: "teste")
        }
        #expect(scenario.requestCount == 1)
    }

    // MARK: - RF-04.3 / DT-19: over-fetch, filtrar, truncar

    @Test("Pede 10 resultados à API")
    func requestsTenResults() {
        #expect(TavilySearchService.requestedResultCount == 10)
    }

    @Test("Filtra a allowlist e trunca em 5, nessa ordem")
    func filtersThenTruncates() async throws {
        // 3 vazados no topo do ranking + 6 válidos: truncar antes de filtrar devolveria 2.
        let urls = ["https://pt.wikipedia.org/1", "https://cnn.com/2", "https://dicio.com.br/3",
                    "https://g1.globo.com/4", "https://estadao.com.br/5", "https://bbc.com/6",
                    "https://exame.com/7", "https://r7.com/8", "https://dw.com/9"]
        let (service, _) = makeService([
            .success(status: 200, body: MockURLProtocol.tavilyBody(urls: urls)),
        ])

        let results = try await service.search(query: "teste")

        #expect(results.count == AllowlistFilter.maxAcceptedSources)
        #expect(results.allSatisfy { AllowlistFilter.isAllowed(urlString: $0.url) })
    }

    @Test("Zero resultados devolve vazio, não erro (RF-04.4)")
    func emptyResultsIsNotAnError() async throws {
        let (service, _) = makeService([
            .success(status: 200, body: Data(#"{"results":[]}"#.utf8)),
        ])

        // O veredito NÃO ENCONTRADO é do agregador; a busca só reporta que não veio nada.
        #expect(try await service.search(query: "asdfghjkl").isEmpty)
    }

    @Test("Tudo fora da allowlist devolve vazio, não erro")
    func allLeakedIsEmptyNotError() async throws {
        // Caso real do Spike 5: 100% dos resultados vieram de fora da allowlist.
        let (service, _) = makeService([
            .success(status: 200, body: MockURLProtocol.tavilyBody(
                urls: ["https://pt.wikipedia.org/1", "https://dicio.com.br/2"])),
        ])

        #expect(try await service.search(query: "teste").isEmpty)
    }

    // MARK: - RF-04.5: falha de rede é distinta de "não encontrado"

    @Test("Corpo malformado com status 200 é falha, não vazio")
    func malformedBodyIsFailure() async {
        let (service, _) = makeService([
            .success(status: 200, body: Data("não é json".utf8)),
        ])

        await #expect(throws: VerificationError.searchRequestFailed) {
            try await service.search(query: "teste")
        }
    }

    // MARK: - Contrato do proxy

    @Test("Requisição vai como POST JSON, sem chave de API")
    func requestShape() async throws {
        let (service, scenario) = makeService([
            .success(status: 200, body: MockURLProtocol.tavilyBody(urls: ["https://g1.globo.com/a"])),
        ])

        _ = try await service.search(query: "a inflação subiu")

        let request = try #require(scenario.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(scenario.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["query"] as? String == "a inflação subiu")
        #expect(json["max_results"] as? Int == 10)
        #expect(json["search_depth"] as? String == "basic")
        #expect((json["include_domains"] as? [String])?.count == TrustedDomain.allowlist.count)
        // NF-09: a chave nunca sai do proxy. Se ela aparecer aqui, o modelo de segurança caiu.
        #expect(json["api_key"] == nil)
    }

    // MARK: - Endpoint não configurado

    @Test("Endpoint vazio falha antes de tocar a rede")
    func emptyEndpointFailsFast() async {
        let (session, scenario) = MockURLProtocol.makeSession([])
        let service = TavilySearchService(session: session, endpoint: "")

        await #expect(throws: VerificationError.searchRequestFailed) {
            try await service.search(query: "teste")
        }
        // Worker ainda não deployado: nenhuma requisição, e nenhum retry inútil.
        #expect(scenario.requestCount == 0)
    }
}
