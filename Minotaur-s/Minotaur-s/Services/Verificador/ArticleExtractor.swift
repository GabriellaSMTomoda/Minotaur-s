//
//  ArticleExtractor.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import SwiftSoup

/// Baixa o HTML de um artigo e extrai o texto principal (RF-05).
///
/// A extração é um **porte de algoritmo tipo Readability sobre SwiftSoup** (DT-23): pontuação
/// por densidade de texto por bloco, não denylist de classes/ids. A escolha vem das armadilhas
/// medidas no Spike 3, que a denylist não cobria:
///
/// 1. classe utilitária de tema na raiz (`share` no `<body>`) batendo por substring e apagando
///    a página inteira;
/// 2. nome de classe enganoso — `-paywall-parent`, no Estadão, é o contêiner do conteúdo
///    **gratuito**;
/// 3. wrapper de menu mobile envolvendo o `<body>` inteiro (`js-mmenu-container`).
///
/// Pontuar blocos por quanto texto real eles carregam é imune às três: nenhuma delas muda a
/// densidade de texto do bloco que de fato contém a matéria.
/// `Sendable` porque a extração dos artigos roda em paralelo, uma tarefa por fonte (RF-05.6):
/// o único campo é imutável e a `URLSession` já é segura entre threads.
struct ArticleExtractor: Sendable {

    /// Mínimo de caracteres para o texto ser considerado utilizável (RF-05.3 / CA-05).
    /// Abaixo disso: paywall, conteúdo via JavaScript, ou falha de extração.
    static let minimumTextLength = 200

    /// Timeout por artigo (RF-05.4). Artigo que estoura é descartado sem abortar o fluxo.
    static let timeout: TimeInterval = 8

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Pipeline por artigo

    /// Texto principal do artigo, pronto para o `TextChunker`.
    ///
    /// Ordem de tentativa, conforme RF-05.3 / DT-23:
    /// 1. extração própria sobre o HTML baixado;
    /// 2. se render menos de `minimumTextLength`, o `content` da busca como **fallback**;
    /// 3. se o fallback também for curto, a fonte é inválida.
    ///
    /// O `content` da busca **nunca** substitui uma extração bem-sucedida — só resgata o caso
    /// em que ela falhou.
    ///
    /// Não há retry por artigo: continua em aberto (item 14 da seção 7.3), a decidir em fase
    /// futura. Um 5xx transitório aqui simplesmente descarta a fonte.
    ///
    /// - Returns: `nil` quando a fonte deve ser descartada — timeout, erro HTTP, HTML ilegível,
    ///   ou texto curto demais nas duas vias. Descartar uma fonte nunca aborta a verificação
    ///   (CA-05 / CA-06); quem decide o que fazer com as fontes restantes é o coordenador.
    func extractText(from item: SearchResultItem) async -> String? {
        let extracted = await downloadAndExtract(item: item)

        if let extracted, extracted.count >= Self.minimumTextLength {
            return extracted
        }

        let fallback = Self.normalize(item.content)
        return fallback.count >= Self.minimumTextLength ? fallback : nil
    }

    private func downloadAndExtract(item: SearchResultItem) async -> String? {
        guard let url = item.resolvedURL else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        // Alguns veículos devolvem 403 sem User-Agent de navegador. Os 4 domínios com
        // bot-blocking duro já saíram da allowlist (RF-03.1), isto cobre o resto.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("pt-BR,pt;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let html = Self.decodeHTML(data) else { return nil }
            return try? Self.mainText(fromHTML: html)
        } catch {
            // Inclui `URLError.timedOut` dos 8 s (RF-05.4 / CA-06).
            return nil
        }
    }

    /// Decodifica o HTML tolerando charset não-UTF-8. Vários veículos brasileiros ainda
    /// servem ISO-8859-1; forçar UTF-8 devolveria `nil` e descartaria a fonte por engano.
    private static func decodeHTML(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(data: data, encoding: .windowsCP1252)
    }

    // MARK: - Extração tipo Readability

    /// Texto principal do documento, um parágrafo por linha.
    ///
    /// O formato de saída importa: o `TextChunker` separa parágrafos por quebra de linha, e é
    /// sobre esses parágrafos que a RF-06.1 monta os chunks.
    static func mainText(fromHTML html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        try stripNonContent(document)

        guard let best = try bestCandidate(in: document) else {
            return normalize(try document.text())
        }
        return try paragraphText(of: best)
    }

    /// Remove o que nunca é corpo de matéria.
    ///
    /// A lista é de **nomes de tag**, não de classes/ids. É essa diferença que evita a
    /// armadilha 1 do Spike 3: `<body class="... share ...">` não some, porque `body` não é
    /// uma tag de navegação — só sumiriam `<nav>`, `<footer>` e afins, que de fato nunca
    /// contêm a matéria.
    private static func stripNonContent(_ document: Document) throws {
        let tags = ["script", "style", "noscript", "iframe", "svg", "form",
                    "nav", "header", "footer", "aside", "figure", "figcaption"]
        for tag in tags {
            try document.select(tag).remove()
        }
    }

    /// Bloco com a maior pontuação de conteúdo.
    ///
    /// Candidatos são só contêineres de bloco (`article`, `main`, `section`, `div`) — nunca
    /// `body`/`html`, senão a raiz venceria sempre por acumular todo o texto da página e a
    /// escolha perderia a função. Isso também neutraliza a armadilha 3 do Spike 3: um wrapper
    /// de menu que envolve o `<body>` inteiro herda o texto da matéria, mas perde para o
    /// contêiner mais interno que tem a mesma matéria com menos ruído em volta.
    private static func bestCandidate(in document: Document) throws -> Element? {
        let candidates = try document.select("article, main, section, div")

        var best: Element?
        var bestScore = 0.0

        for candidate in candidates.array() {
            let score = try self.score(of: candidate)
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    /// Pontuação de um bloco: quanto texto de parágrafo ele tem, penalizado pelo texto que
    /// está dentro de links.
    ///
    /// A penalidade por link é o que separa a matéria de uma lista de "leia também" ou de um
    /// menu: ambos têm bastante texto, mas quase todo ele é âncora. Um corpo de matéria real
    /// tem densidade de link baixa.
    ///
    /// Só conta texto dentro de `<p>`: é o que exclui blocos que acumulam texto solto de
    /// widgets. Nenhum nome de classe ou id entra na conta — é isso que torna a pontuação
    /// imune à armadilha 2 do Spike 3 (`-paywall-parent` sendo o conteúdo gratuito).
    private static func score(of element: Element) throws -> Double {
        let paragraphs = try element.select("p")
        guard !paragraphs.isEmpty else { return 0 }

        var textLength = 0
        for paragraph in paragraphs.array() {
            let text = try paragraph.text().trimmingCharacters(in: .whitespacesAndNewlines)
            // Parágrafo curto costuma ser legenda, crédito ou boilerplate, não corpo.
            if text.count >= 25 { textLength += text.count }
        }
        guard textLength > 0 else { return 0 }

        let linkLength = try element.select("a").array()
            .reduce(0) { total, anchor in
                total + ((try? anchor.text().count) ?? 0)
            }
        let linkDensity = min(1.0, Double(linkLength) / Double(textLength))

        return Double(textLength) * (1.0 - linkDensity)
    }

    /// Serializa os parágrafos do bloco escolhido, um por linha.
    private static func paragraphText(of element: Element) throws -> String {
        let paragraphs = try element.select("p").array()
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return normalize(try element.text()) }
        return normalize(paragraphs.joined(separator: "\n"))
    }

    /// Colapsa espaços em branco preservando as quebras de linha que separam parágrafos.
    private static func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
