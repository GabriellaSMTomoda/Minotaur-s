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

    /// Maximum total per-article attempt allowance: two attempts of up to four seconds.
    static let timeout: TimeInterval = 8

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Pipeline por artigo

    /// Compatibility text-only entry point. Production uses `extract(_:budget:)` so
    /// snippets, partial bodies, dates and network failures retain their provenance.
    func extractText(from item: SearchResultItem) async -> String? {
        await extract(item, budget: VerificationBudget()).article?.text
    }

    func extract(_ item: SearchResultItem, budget: VerificationBudget) async -> ArticleExtraction {
        guard let url = item.resolvedURL, url.scheme == "https", AllowlistFilter.isAllowed(url) else {
            return ArticleExtraction(article: nil, discardReason: .disallowedURL)
        }
        var discard: ArticleDiscardReason = .unusable
        for attempt in 0..<2 {
            guard !Task.isCancelled, budget.networkRemaining > 0.1 else { break }
            var request = URLRequest(url: url)
            request.timeoutInterval = min(Self.timeout / 2, budget.networkRemaining)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("pt-BR,pt;q=0.9", forHTTPHeaderField: "Accept-Language")
            do {
                let (data, response) = try await session.data(for: request)
                guard let finalURL = response.url, finalURL.scheme == "https", AllowlistFilter.isAllowed(finalURL) else {
                    return ArticleExtraction(article: nil, discardReason: .disallowedURL)
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    discard = .network
                    if attempt == 0 && (500...599).contains(http.statusCode) && budget.networkRemaining > 1 { continue }
                    break
                }
                guard data.count <= 3 * 1024 * 1024, let html = Self.decodeHTML(data) else { break }
                let article = try Self.article(fromHTML: html, item: item, finalURL: finalURL)
                if article.text.count >= Self.minimumTextLength {
                    return ArticleExtraction(article: article)
                }
                discard = article.isPartial ? .paywall : .unusable
                break
            } catch {
                if Task.isCancelled { return ArticleExtraction(article: nil, discardReason: .timeout) }
                let timedOut = (error as? URLError)?.code == .timedOut
                discard = timedOut ? .timeout : .network
                if attempt == 0 && timedOut && budget.networkRemaining > 1 { continue }
                break
            }
        }
        let snippet = Self.normalize(item.content)
        guard snippet.count >= Self.minimumTextLength else { return ArticleExtraction(article: nil, discardReason: discard) }
        return ArticleExtraction(article: ExtractedArticle(item: item, text: snippet, finalURL: item.url,
                                                           provenance: .searchSnippet, isPartial: true), discardReason: discard)
    }

    static func article(fromHTML html: String, item: SearchResultItem, finalURL: URL) throws -> ExtractedArticle {
        let document = try SwiftSoup.parse(html)
        func meta(_ key: String) -> String? {
            guard let value = try? document.select("meta[property='\(key)'],meta[name='\(key)']").first()?.attr("content"),
                  !value.isEmpty else { return nil }
            return value
        }
        var structured: [[String: Any]] = []
        func visit(_ object: Any) {
            if let array = object as? [Any] { array.forEach(visit); return }
            guard let dictionary = object as? [String: Any] else { return }
            let types = (dictionary["@type"] as? [String]) ?? [dictionary["@type"] as? String ?? ""]
            if types.contains(where: { ["NewsArticle", "Article", "ReportageNewsArticle", "ClaimReview"].contains($0) }) {
                structured.append(dictionary)
            }
            if let graph = dictionary["@graph"] { visit(graph) }
            if let page = dictionary["mainEntity"] { visit(page) }
        }
        for script in try document.select("script[type='application/ld+json']").array() {
            if let data = script.data().data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) { visit(object) }
        }
        let data = structured.first ?? [:]
        let freeValue = data["isAccessibleForFree"]
        let paywalled = (freeValue as? Bool == false) || (freeValue as? String)?.lowercased() == "false"
        let visible = try mainText(fromHTML: html)
        let structuredBody = data["articleBody"] as? String
        // Never use hidden JSON-LD to recover paid content.
        let useStructured = !paywalled && visible.count < minimumTextLength && (structuredBody?.count ?? 0) >= minimumTextLength
        let text = useStructured ? normalize(structuredBody ?? "") : visible
        let type = meta("og:type") ?? ""
        // Exact markers only: '-paywall-parent' can be a legitimate free container.
        let hasPaidMarker = try document.select("[itemprop='isAccessibleForFree'][content='false'],[data-paywall='true'],[data-article-access='paid'],.paywall,.subscription-required,.article-preview").size() > 0
        let partial = paywalled || type == "website" || hasPaidMarker
        let canonical = try document.select("link[rel='canonical']").first()?.attr("href")
        let canonicalURL = canonical.flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL }
        let author = (data["author"] as? [String: Any])?["name"] as? String
        let original = (data["isBasedOn"] as? String) ?? meta("citation_source")
        return ExtractedArticle(item: item, text: text, finalURL: finalURL.absoluteString,
                                canonicalURL: canonicalURL.flatMap { AllowlistFilter.isAllowed($0) && $0.scheme == "https" ? $0.absoluteString : nil },
                                title: data["headline"] as? String ?? meta("og:title") ?? item.title,
                                author: author ?? meta("author"),
                                publishedAt: parseDate(data["datePublished"] as? String ?? meta("article:published_time") ?? item.publishedDate),
                                modifiedAt: parseDate(data["dateModified"] as? String ?? meta("article:modified_time")),
                                provenance: useStructured ? .structuredData : .articleBody, isPartial: partial,
                                originalSource: original)
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return date }
        let simple = DateFormatter()
        simple.locale = Locale(identifier: "en_US_POSIX")
        simple.timeZone = TimeZone(secondsFromGMT: 0)
        simple.dateFormat = "yyyy-MM-dd"
        return simple.date(from: text)
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
