//
//  MockURLProtocol.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Intercepta as requisições da `URLSession` para testar rede sem rede.
///
/// O estado é **por sessão**, não global. Um único contador estático não serve: o Swift
/// Testing roda suítes diferentes em paralelo entre si, então a contagem de requisições de
/// uma suíte contaminava a da outra — e é justamente essa contagem que prova quantas
/// tentativas o retry fez. Cada sessão carrega um id num header e só enxerga o próprio estado.
final class MockURLProtocol: URLProtocol {

    enum Outcome {
        case success(status: Int, body: Data)
        case failure(URLError.Code)
    }

    /// Estado de uma sessão de teste.
    final class Scenario: @unchecked Sendable {
        /// Resposta de cada tentativa, na ordem. A última se repete se houver mais tentativas.
        var responses: [Outcome]
        private(set) var requestCount = 0
        private(set) var lastRequest: URLRequest?
        private(set) var lastBody: Data?

        private let lock = NSLock()

        init(responses: [Outcome]) {
            self.responses = responses
        }

        func record(_ request: URLRequest, body: Data?) -> Outcome {
            lock.lock()
            defer { lock.unlock() }

            let index = requestCount
            requestCount += 1
            lastRequest = request
            lastBody = body

            if responses.indices.contains(index) { return responses[index] }
            return responses.last ?? .failure(.badServerResponse)
        }
    }

    private static let headerKey = "X-Mock-Scenario"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var scenarios: [String: Scenario] = [:]

    /// `URLSession` isolada, com o seu próprio cenário.
    static func makeSession(_ responses: [Outcome]) -> (URLSession, Scenario) {
        let id = UUID().uuidString
        let scenario = Scenario(responses: responses)

        lock.lock()
        scenarios[id] = scenario
        lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpAdditionalHeaders = [headerKey: id]

        return (URLSession(configuration: configuration), scenario)
    }

    /// Corpo JSON de uma resposta da Tavily com os URLs dados.
    static func tavilyBody(urls: [String]) -> Data {
        let results = urls.map {
            #"{"title":"Título","url":"\#($0)","content":"\#(String(repeating: "x", count: 300))","score":0.9}"#
        }
        return Data(#"{"results":[\#(results.joined(separator: ","))]}"#.utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: headerKey) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: Self.headerKey),
            let scenario = Self.scenario(for: id)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let outcome = scenario.record(request, body: Self.readBody(from: request))

        switch outcome {
        case let .success(status, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)

        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    private static func scenario(for id: String) -> Scenario? {
        lock.lock()
        defer { lock.unlock() }
        return scenarios[id]
    }

    /// Lê o corpo a partir do stream.
    ///
    /// A `URLSession` converte `httpBody` em `httpBodyStream` antes de chegar ao
    /// `URLProtocol` — ler só `httpBody` devolveria `nil` e o teste de contrato passaria sem
    /// verificar nada.
    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
