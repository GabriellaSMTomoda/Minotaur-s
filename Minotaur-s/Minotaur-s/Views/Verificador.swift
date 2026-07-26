import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Representa um resultado simples de busca na web
struct WebSearchResult {
    let title: String
    let url: String
    let host: String
}

// Modelos para a API Google Fact Check (ClaimReview)
private struct FactCheckResponse: Decodable {
    let claims: [FCClaim]?
}

private struct FCClaim: Decodable {
    let text: String?
    let claimReview: [FCClaimReview]?
}

private struct FCClaimReview: Decodable {
    let publisher: FCPublisher?
    let url: String?
    let title: String?
    let textualRating: String?
    let languageCode: String?
    let reviewDate: String?
}

private struct FCPublisher: Decodable {
    let name: String?
    let site: String?
}

struct VerificadorView: View {
    // Instruções para o modelo
    @State private var instructions: String = """
    Sua função é resumir a ideia principal da notícia em uma frase clara, objetiva e específica.
    - Mantenha tom neutro e jornalístico.
    - Não repita linguagem ofensiva; substitua por "[conteúdo sensível]".
    - Se o texto for sensível, produza mesmo assim um resumo neutro sem detalhes gráficos.
    - Não responda com mensagens de recusa; entregue um resumo seguro do tópico geral.
    - Não invente fatos, fontes, números ou datas.
    """

    // Entrada e saída
    @State private var newsText: String = ""
    @State private var output: String = ""

    // Estado de UI
    @State private var isResponding: Bool = false
    @State private var errorMessage: String?

    // Chave da API Google Fact Check Tools.
    //
    // O valor estava hardcoded aqui e foi removido: chave em código-fonte é extraível do
    // binário e já ficou exposta no histórico do git — precisa ser revogada e rotacionada
    // no Google Cloud Console, e reintroduzida por configuração segura (nunca literal).
    // Enquanto vazia, `evaluateFactChecks` retorna nil no guard abaixo e o fluxo legado
    // degrada para a busca web, sem quebrar.
    private let factCheckAPIKey: String? = ""

    var body: some View {
        NavigationStack {
            ScrollView{
                VStack(spacing: 16) {
                    availabilityBanner
                    
                    if isResponding {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Pensando...")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }
                    
                    GroupBox("Sua Notícia") {
                        TextField("Cole ou digite a notícia aqui", text: $newsText, axis: .vertical)
                            .lineLimit(4...8)
                    }
                    
                    HStack {
                        Spacer()
                        Button {
                            Task { await runCheck() }
                        } label: {
                            Label("Verificar", systemImage: "globe")
                                .labelStyle(.titleAndIcon)
                        }
                        .font(.headline)
                        .bold()
                        .foregroundColor(Color.white)
                        .frame(height: 48)
                        .frame(minWidth: 160)
                        .background(Color("azul"))
                        .cornerRadius(20)
                        .padding(.vertical, -4)
                        .accessibilityLabel("Verificar")
                        .accessibilityHint("Toque para verificar se a notícia é verdadeira.")
                        .disabled(isResponding || newsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    GroupBox("Resultado") {
                        ScrollView {
                            if let attributed = try? AttributedString(markdown: output) {
                                Text(attributed)
                                    .textSelection(.enabled)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(output)
                                    .textSelection(.enabled)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(minHeight: 180)
                    }
                    
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding()
                .navigationTitle("Verificar Notícia")
                .toolbarBackground(Color("azul"), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
    }

    // MARK: - Subviews

    private var availabilityBanner: some View {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return AnyView(
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Modelo disponível no dispositivo")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                )
            case .unavailable(.deviceNotEligible):
                return AnyView(fallbackView(text: "Apple Intelligence indisponível neste dispositivo. Usando resumo local e busca web."))
            case .unavailable(.appleIntelligenceNotEnabled):
                return AnyView(fallbackView(text: "Apple Intelligence desativado. Usando resumo local e busca web."))
            case .unavailable(.modelNotReady):
                return AnyView(fallbackView(text: "Modelo local ainda não está pronto. Usando resumo local e busca web."))
            case .unavailable:
                return AnyView(fallbackView(text: "Modelo local indisponível. Usando resumo local e busca web."))
            @unknown default:
                return AnyView(fallbackView(text: "Modelo local indisponível. Usando resumo local e busca web."))
            }
        }
#endif
        return AnyView(fallbackView(text: "Modelo local indisponível. Usando resumo local e busca web."))
    }

    private func fallbackView(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Pipeline simplificado

    @MainActor
    private func runCheck() async {
        errorMessage = nil
        isResponding = true
        output = ""
        defer { isResponding = false }

        do {
            // 1) Extrair ideia principal
            let idea = await extractMainIdea(text: newsText)

            // 2) Consultar checagens (Google Fact Check). Se não houver veredito, buscar na web.
            let verdict: Verdict
            if let v = await evaluateFactChecks(for: idea) {
                verdict = v
            } else {
                let results = try await fetchSearchResults(query: idea)
                verdict = await evaluateEvidence(from: results)
            }

            // 3) Mensagem final curta
            let verdictLine: String
            var explanation: String
            switch verdict {
            case .supported(let links):
                verdictLine = "Notícia parece Verdadeira."
                let shownLinks = Array(links.prefix(2))
                if shownLinks.isEmpty {
                    explanation = "Encontramos possíveis menções concordantes em domínios confiáveis."
                } else {
                    let list = shownLinks.map { "<\($0)>" }.joined(separator: "\n")
                    explanation = "Verifique a veracidade no link:  \n\(list)"
                }
            case .refuted(let links):
                verdictLine = "Notícia parece Falsa."
                let shownLinks = Array(links.prefix(2))
                if shownLinks.isEmpty {
                    explanation = "Encontramos checagens em domínios confiáveis que indicam ser falsa."
                } else {
                    let list = shownLinks.map { "<\($0)>" }.joined(separator: "\n")
                    explanation = "Verifique a veracidade no link:  \n\(list)"
                }
            case .unverified:
                verdictLine = "Não foi possível verificar."
                explanation = "Não encontramos confirmação nem desmentido em fontes confiáveis. Isso não significa que a notícia seja falsa — verifique diretamente em veículos confiáveis."
            }

            let disclaimer = "Atenção: este veredito é apenas indicativo. Para ter mais certeza, verifique diretamente em veículos confiáveis."

            // Construção do output conforme instruções
            output = "\(verdictLine)\n\(explanation)\n\(disclaimer)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func extractMainIdea(text: String) async -> String {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: instructions)
                return try await extractMainIdeaWithFoundationModels(session: session, text: text)
            } catch {
                return safeFallbackSummary(from: text)
            }
        }
#endif
        return safeFallbackSummary(from: text)
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func extractMainIdeaWithFoundationModels(session: LanguageModelSession, text: String) async throws -> String {
        let prompt = """
        Notícia do usuário:
        \(text)

        Tarefa: Extraia a ideia principal em 1 frase clara, objetiva e específica.
        """
        let response = try await session.respond(to: prompt)
        let idea = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Se o modelo recusou ou não preencheu, use um fallback local seguro
        if idea.isEmpty || looksLikeSafetyRefusal(idea) {
            return safeFallbackSummary(from: text)
        }
        return idea
    }
#endif

    private func looksLikeSafetyRefusal(_ s: String) -> Bool {
        let markers = [
            "conteúdo potencialmente inseguro",
            "não posso ajudar com isso",
            "não posso fornecer",
            "não posso ajudar",
            "não posso atender a essa solicitação"
        ]
        let l = s.lowercased()
        return markers.contains { l.contains($0) }
    }

    private func safeFallbackSummary(from text: String) -> String {
        // Pega a primeira sentença (até o primeiro ponto) ou limita a 180 caracteres
        if let first = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first {
            let trimmed = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(180))
        } else {
            return String(text.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Google Fact Check (ClaimReview)
    private func evaluateFactChecks(for query: String) async -> Verdict? {
        // Requer API key; se não houver, não tenta.
        guard let apiKey = factCheckAPIKey, !apiKey.isEmpty else { return nil }
        do {
            let reviews = try await fetchFactChecks(query: query, apiKey: apiKey)
            return interpretFactCheckReviews(reviews)
        } catch {
            // Em caso de erro na API, siga para a busca web normal
            return nil
        }
    }

    private func fetchFactChecks(query: String, apiKey: String, pageSize: Int = 6) async throws -> [FCClaimReview] {
        var comps = URLComponents(string: "https://factchecktools.googleapis.com/v1alpha1/claims:search")!
        comps.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languageCode", value: "pt-BR"),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        let url = comps.url!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Ex.: 403 quando a Fact Check Tools API está desabilitada no projeto Google Cloud
            // ou quando a chave está restrita. Tratar como indisponível para cair na busca web.
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(FactCheckResponse.self, from: data)
        let allReviews = (decoded.claims ?? []).flatMap { $0.claimReview ?? [] }
        return allReviews
    }

    private func interpretFactCheckReviews(_ reviews: [FCClaimReview]) -> Verdict? {
        if reviews.isEmpty { return nil }
        let negativeKeywords = ["rumor", "falso", "enganoso", "fake", "mentira", "impreciso", "inverídico", "não procede", "não é verdade"]
        let positiveKeywords = ["verdadeiro", "correto", "verdade", "exato", "procedente"]

        var negativeLinks = [String]()
        var positiveLinks = [String]()
        var seen = Set<String>()

        for r in reviews {
            guard let urlStr = r.url, !urlStr.isEmpty else { continue }
            let rating = (r.textualRating ?? "").lowercased()
            if negativeKeywords.contains(where: { rating.contains($0) }) {
                if !seen.contains(urlStr) {
                    seen.insert(urlStr)
                    negativeLinks.append(urlStr)
                }
            } else if positiveKeywords.contains(where: { rating.contains($0) }) {
                if !seen.contains(urlStr) {
                    seen.insert(urlStr)
                    positiveLinks.append(urlStr)
                }
            }
        }

        // Regra conservadora: qualquer negativo => refutado (retorna links específicos)
        if !negativeLinks.isEmpty {
            return .refuted(links: Array(negativeLinks.prefix(2)))
        }

        // Caso contrário, se houver pelo menos 2 positivos independentes => suportado (retorna links específicos)
        if positiveLinks.count >= 2 {
            return .supported(links: Array(positiveLinks.prefix(2)))
        }

        return nil
    }

    // MARK: - Busca web (DuckDuckGo HTML)

    private func fetchSearchResults(query: String, maxCount: Int = 8) async throws -> [WebSearchResult] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // Usa o host canônico de scraping do DuckDuckGo. O antigo "duckduckgo.com/html/"
        // passou a responder 302/sem resultados dependendo de IP, região e rate-limit,
        // o que fazia a verificação funcionar em um dispositivo/rede e falhar em outro.
        let url = URL(string: "https://html.duckduckgo.com/html/?q=\(q)&kl=wt-wt")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("pt-BR,pt;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let html = String(data: data, encoding: .utf8) ?? ""

        let pattern = "uddg=([^&\"]+)"
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))

        var results: [WebSearchResult] = []
        var seen: Set<String> = []
        for m in matches {
            guard m.numberOfRanges >= 2, let range = Range(m.range(at: 1), in: html) else { continue }
            let enc = String(html[range])
            let decoded = enc.removingPercentEncoding ?? enc
            guard let u = URL(string: decoded), let host = u.host else { continue }
            let base = normalizeHost(host)
            if seen.contains(decoded) { continue }
            seen.insert(decoded)
            results.append(WebSearchResult(title: base, url: decoded, host: base))
            if results.count >= maxCount { break }
        }
        return results
    }

    private func normalizeHost(_ host: String) -> String {
        let h = host.lowercased()
        if h.hasPrefix("www.") { return String(h.dropFirst(4)) }
        return h
    }

    // MARK: - Avaliação de evidências (mais rigorosa)
    private enum Verdict {
        case supported(links: [String])
        case refuted(links: [String])
        case unverified
    }

    private func evaluateEvidence(from results: [WebSearchResult]) async -> Verdict {
        // Filtra apenas resultados em domínios confiáveis
        let trusted = results.filter { TrustedDomain.allowlist.contains($0.host) }
        if trusted.isEmpty {
            return .unverified
        }

        // Procura por desmentidos/checagens e guarda os links específicos
        var debunkingLinks = Set<String>()
        await withTaskGroup(of: (WebSearchResult, Bool).self) { group in
            for r in trusted {
                group.addTask {
                    let isDebunk = await checkIfDebunking(for: r)
                    return (r, isDebunk)
                }
            }
            for await (result, isDebunk) in group {
                if isDebunk { debunkingLinks.insert(result.url) }
            }
        }

        if !debunkingLinks.isEmpty {
            return .refuted(links: Array(debunkingLinks).sorted())
        }

        // Exige pelo menos 2 domínios distintos corroborando e retorna os links específicos
        var seenHosts = Set<String>()
        var corroboratingLinks: [String] = []
        for r in trusted {
            if !seenHosts.contains(r.host) {
                seenHosts.insert(r.host)
                corroboratingLinks.append(r.url)
                if corroboratingLinks.count >= 2 { break }
            }
        }

        if corroboratingLinks.count >= 2 {
            return .supported(links: corroboratingLinks)
        } else {
            return .unverified
        }
    }

    private func checkIfDebunking(for result: WebSearchResult) async -> Bool {
        // Palavras-chave comuns em checagens/desmentidos (pt-BR)
        let debunkingKeywords = [
            "é falso", "falso", "fake", "boato", "mentira", "enganoso",
            "não procede", "não é verdade", "desment", "checagem", "fact-check",
            "fato ou fake", "fato-ou-fake", "boatos", "aos fatos", "aosfatos", "agência lupa", "lupa", "verificação"
        ]

        // Sinaliza se o título/URL já contém indicativo de desmentido
        let urlLower = result.url.lowercased()
        let titleLower = result.title.lowercased()
        for kw in debunkingKeywords {
            if urlLower.contains(kw) || titleLower.contains(kw) {
                return true
            }
        }

        // Caso contrário, tenta obter o <title> da página
        if let pageTitle = await fetchPageTitle(for: result.url) {
            let t = pageTitle.lowercased()
            for kw in debunkingKeywords {
                if t.contains(kw) { return true }
            }
        }

        return false
    }

    private func fetchPageTitle(for urlString: String) async -> String? {
        // Só busca páginas via HTTPS: o App Transport Security bloqueia HTTP (cleartext)
        // por padrão, então tentar http:// falharia silenciosamente em qualquer dispositivo.
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            guard let html = String(data: data, encoding: .utf8) else { return nil }

            let pattern = "<title[^>]*>(.*?)</title>"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            if let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: html) {
                return String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return nil
        }

        return nil
    }
}

#Preview {
    VerificadorView()
}
