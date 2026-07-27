//
//  TavilySearchService.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Busca artigos nos veículos da allowlist via Tavily (RF-04).
///
/// O app **nunca** fala com a Tavily diretamente e **nunca** embarca a chave de API: toda
/// chamada vai para um proxy serverless (Cloudflare Workers) que injeta a chave e repassa a
/// resposta (NF-09 / DT-21). Chave embarcada no binário é extraível por engenharia reversa,
/// então o proxy é a única proteção real. O código do Worker está em `proxy/`.
/// `Sendable` porque o coordenador o usa de dentro de tarefas concorrentes: os dois campos são
/// imutáveis e a `URLSession` já é segura entre threads.
struct TavilySearchService: Sendable {

    /// URL do Worker que faz o proxy da Tavily.
    ///
    /// **Ainda não configurada** — o Worker em `proxy/` existe mas não foi deployado. Até que
    /// haja uma URL aqui, `search` falha com `.searchRequestFailed` antes de tocar a rede.
    /// Preencher com a URL devolvida por `wrangler deploy` (ver `proxy/README.md`).
    /// Nunca colocar a chave da Tavily neste arquivo — é justamente o que o proxy evita.
    static let proxyEndpoint = "https://minotaurs-tavily-proxy.hen-lac-sil.workers.dev"

    /// Quantos resultados pedir à API (RF-04.3 / DT-19).
    ///
    /// Pedimos mais do que os 5 que serão usados porque o `include_domains` da Tavily não é
    /// um filtro rígido: o Spike 5 mediu vazamento em 4 de 20 buscas. Pedir 10 e truncar
    /// depois do filtro local reduziu o vazamento na evidência observada.
    static let requestedResultCount = 10

    /// Timeout da chamada de busca. Mais folgado que os 8 s por artigo (RF-05.4) porque a
    /// busca é ponto único de falha da verificação inteira; a latência média medida no
    /// Spike 5 foi de 1,62 s.
    static let timeout: TimeInterval = 15

    private let session: URLSession
    private let endpoint: String

    /// - Parameters:
    ///   - session: injetável para teste sem rede (`URLProtocol` mock).
    ///   - endpoint: injetável para teste; o padrão é o Worker de produção.
    init(session: URLSession = .shared, endpoint: String = TavilySearchService.proxyEndpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    // MARK: - Busca

    /// Busca artigos para a query, já filtrados pela allowlist e truncados (RF-04.3).
    ///
    /// A ordem é obrigatória e não é intercambiável: **filtrar por allowlist e só então
    /// truncar** em 5. Truncar antes deixaria resultados vazados ocuparem vagas de fontes
    /// válidas (RF-03.5 seguido de RF-04.3).
    ///
    /// - Returns: array vazio quando a busca não encontrou nada, ou quando tudo que voltou
    ///   estava fora da allowlist. Quem transforma isso em `NÃO ENCONTRADO` é o agregador
    ///   (RF-04.4) — o vazio aqui **não** é erro, e é por isso que falha de rede lança em vez
    ///   de devolver vazio (RF-04.5).
    /// - Throws: `VerificationError` mapeado por `mapError`.
    func search(query: String) async throws -> [SearchResultItem] {
        let response = try await performWithRetry(query: query)
        return AllowlistFilter.filter(response.results, url: \.resolvedURL)
    }

    /// Lista de domínios efetivamente consultados numa verificação (RF-09.6).
    /// É a allowlist inteira: a restrição vai em `include_domains` numa única chamada (RF-02.3).
    static var consultedDomains: [String] {
        TrustedDomain.allowlist.sorted()
    }

    /// Satisfaz `ArticleSearching.consultedDomains` (RF-09.6 / DT-32): o coordenador lê essa
    /// lista pela porta, não pelo tipo concreto, para que `VerificationResult.consultedDomains`
    /// venha do mesmo lugar em produção e em teste (mocks têm a própria lista fixa).
    var consultedDomains: [String] { Self.consultedDomains }

    // MARK: - Retry

    /// Executa a busca com **uma única** tentativa adicional (RF-04.6 / DT-27).
    ///
    /// A tentativa extra vale só para erro transitório — HTTP 5xx e timeout. `401` e `429`
    /// **nunca** são reafetados: repetir uma chave inválida não a torna válida, e repetir um
    /// rate-limit só piora o rate-limit.
    ///
    /// Retry por artigo individual continua em aberto (item 14 da seção 7.3) e não é feito
    /// aqui nem no `ArticleExtractor`.
    private func performWithRetry(query: String) async throws -> TavilyResponse {
        do {
            return try await perform(query: query)
        } catch let failure as SearchFailure {
            guard failure.isRetriable else { throw failure.verificationError }

            do {
                return try await perform(query: query)
            } catch let retryFailure as SearchFailure {
                throw retryFailure.verificationError
            }
        }
    }

    private func perform(query: String) async throws -> TavilyResponse {
        guard !endpoint.isEmpty, let url = URL(string: endpoint) else {
            // Worker ainda não deployado (ver `proxyEndpoint`). Falha antes da rede, com a
            // categoria de erro que a UI já sabe exibir (RF-10.4). Não é retriável: repetir
            // não faz surgir um endpoint.
            throw SearchFailure.requestFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.timeout
        request.httpBody = try JSONEncoder().encode(
            TavilyRequest(
                query: query,
                searchDepth: "basic",
                maxResults: Self.requestedResultCount,
                includeDomains: TrustedDomain.allowlist.sorted()
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SearchFailure.requestFailed
        }
        try Self.validate(status: http.statusCode)

        do {
            return try JSONDecoder().decode(TavilyResponse.self, from: data)
        } catch {
            // Resposta 200 malformada é falha de busca, não "nada encontrado" (RF-04.5).
            // Não é retriável: um corpo que não decodifica não decodifica de novo.
            throw SearchFailure.requestFailed
        }
    }

    // MARK: - Classificação de falha

    private static func mapTransportError(_ error: Error) -> SearchFailure {
        guard let urlError = error as? URLError else { return .requestFailed }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .noConnection // RF-10.1 / CA-08
        case .timedOut:
            return .timedOut // transitório: vale a tentativa extra (DT-27)
        default:
            return .requestFailed
        }
    }

    private static func validate(status: Int) throws {
        switch status {
        case 200...299:
            return
        case 401, 403:
            // Chave inválida/ausente no Worker. Formato documentado no Spike 5:
            // {"detail": {"error": "Unauthorized: missing or invalid API key."}}.
            // Nunca reafetado (DT-27) — é erro de configuração, não transitório.
            throw SearchFailure.unauthorized
        case 429:
            throw SearchFailure.rateLimited // RF-10.2, nunca reafetado
        case 500...599:
            throw SearchFailure.serverError // transitório: vale a tentativa extra
        default:
            throw SearchFailure.requestFailed
        }
    }
}

// MARK: - Falha interna

/// Classificação interna da falha de busca, com a informação que o `VerificationError` não
/// carrega: **se vale ou não a tentativa extra** da RF-04.6.
///
/// Existe separado porque `VerificationError` é o contrato voltado ao usuário — um caso por
/// categoria que a tela precisa distinguir (RF-10.4). Timeout e 5xx viram a mesma mensagem
/// para quem lê, mas são a única razão para reafetar, então a distinção fica aqui dentro e
/// some na fronteira.
private enum SearchFailure: Error {
    case noConnection
    case timedOut
    case serverError
    case unauthorized
    case rateLimited
    case requestFailed

    /// Só erro transitório é reafetado. `unauthorized` e `rateLimited` nunca são (DT-27).
    var isRetriable: Bool {
        switch self {
        case .timedOut, .serverError:
            return true
        case .noConnection, .unauthorized, .rateLimited, .requestFailed:
            return false
        }
    }

    var verificationError: VerificationError {
        switch self {
        case .noConnection:
            return .noConnection
        case .rateLimited:
            return .searchQuotaExceeded
        case .timedOut, .serverError, .unauthorized, .requestFailed:
            return .searchRequestFailed
        }
    }
}

// MARK: - Contrato do proxy

/// Corpo enviado ao Worker. **Não contém `api_key`** — quem a injeta é o proxy (DT-21).
private struct TavilyRequest: Encodable {
    let query: String
    let searchDepth: String
    let maxResults: Int
    let includeDomains: [String]

    enum CodingKeys: String, CodingKey {
        case query
        case searchDepth = "search_depth"
        case maxResults = "max_results"
        case includeDomains = "include_domains"
    }
}

/// Resposta da Tavily repassada pelo Worker. Só os campos usados são modelados; os demais
/// (`answer`, `images`, `request_id`, `response_time`) são ignorados pelo decoder.
struct TavilyResponse: Decodable {
    let results: [SearchResultItem]
}
