//
//  ArticleExtractorTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// RF-05 / DT-23 / CA-05 / CA-06.
///
/// As armadilhas testadas aqui não são hipotéticas: são as três falhas reais que a heurística
/// por denylist do Spike 3 cometeu sobre HTML de produção. Duas delas usam o HTML original
/// baixado naquele spike, não uma reprodução.
struct ArticleExtractorTests {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: name, withExtension: ext),
            "Fixture \(name).\(ext) não está no bundle de teste"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Armadilhas do Spike 3

    @Test("Armadilha 1: classe utilitária na raiz não apaga a página")
    func rootUtilityClassDoesNotWipePage() throws {
        // A denylist por substring casava `share` na classe do <body> e devolvia vazio.
        // Pontuação por bloco não olha nome de classe, então o corpo sobrevive.
        let html = """
        <html><body class="theme-light no-share sharing-enabled">
          <div class="conteudo">
            <p>O Instituto Brasileiro de Geografia e Estatística divulgou nesta quinta-feira \
        que a taxa de desemprego caiu para 6,2% no trimestre encerrado em maio.</p>
            <p>Segundo o órgão, esse é o menor patamar da série histórica iniciada em 2012, \
        quando a pesquisa passou a ser feita no formato atual.</p>
          </div>
        </body></html>
        """

        let text = try ArticleExtractor.mainText(fromHTML: html)

        #expect(text.contains("taxa de desemprego caiu"))
        #expect(text.contains("menor patamar da série histórica"))
        #expect(text.count >= ArticleExtractor.minimumTextLength)
    }

    @Test("Armadilha 2: -paywall-parent do Estadão é conteúdo gratuito, não pago")
    func misleadingPaywallClassName() throws {
        // HTML real do Spike 3. A denylist descartava tudo sob `-paywall-parent`, que no
        // Estadão é justamente o contêiner do conteúdo aberto.
        let html = try fixture("estadao-paywall-parent", "html")

        let text = try ArticleExtractor.mainText(fromHTML: html)

        #expect(text.count >= ArticleExtractor.minimumTextLength,
                Comment(rawValue: "Extraiu só \(text.count) caracteres — "
                    + "a armadilha do -paywall-parent voltou"))
    }

    @Test("Armadilha 3: wrapper de menu envolvendo o body não zera a extração")
    func mobileMenuWrapperAroundBody() throws {
        // HTML real do Spike 3 (camara.leg.br), onde a heurística manual retornava vazio.
        let html = try fixture("camara-mmenu-wrapper", "html")

        let text = try ArticleExtractor.mainText(fromHTML: html)

        #expect(text.count >= ArticleExtractor.minimumTextLength,
                Comment(rawValue: "Extraiu só \(text.count) caracteres — "
                    + "o wrapper de menu voltou a vencer"))
    }

    // MARK: - Qualidade da extração

    @Test("Menu, rodapé e 'leia também' ficam de fora (RF-05.2)")
    func dropsChrome() throws {
        let html = """
        <html><body>
          <nav><a href="/politica">Política</a><a href="/economia">Economia</a></nav>
          <header><p>Assine agora e tenha acesso ilimitado ao conteúdo do jornal hoje.</p></header>
          <article>
            <p>A Câmara dos Deputados aprovou nesta terça-feira o texto-base da proposta que \
        altera as regras de licenciamento ambiental no país.</p>
            <p>O texto seguiu para o Senado, onde deve ser votado ainda neste semestre \
        segundo o relator da matéria.</p>
          </article>
          <aside class="leia-tambem">
            <a href="/1">Leia também: outra matéria</a><a href="/2">Veja mais notícias</a>
          </aside>
          <footer><p>Todos os direitos reservados. Proibida a reprodução do conteúdo.</p></footer>
        </body></html>
        """

        let text = try ArticleExtractor.mainText(fromHTML: html)

        #expect(text.contains("licenciamento ambiental"))
        #expect(!text.contains("Assine agora"))
        #expect(!text.contains("Leia também"))
        #expect(!text.contains("direitos reservados"))
    }

    @Test("Bloco com muito link perde para o corpo da matéria")
    func linkDensityPenalty() throws {
        // A lista de manchetes tem mais caracteres que a matéria, mas quase tudo é âncora.
        let headlines = (1...20).map {
            "<p><a href=\"/n\($0)\">Manchete número \($0) sobre um assunto qualquer do dia de hoje</a></p>"
        }.joined()
        let html = """
        <html><body>
          <div class="mais-lidas">\(headlines)</div>
          <div class="materia">
            <p>O dólar fechou cotado a R$ 5,12 nesta sexta-feira, em queda de 0,8% ante a \
        sessão anterior, segundo dados do Banco Central.</p>
            <p>Analistas atribuem o movimento à expectativa de manutenção da taxa de juros \
        na próxima reunião do Copom.</p>
          </div>
        </body></html>
        """

        let text = try ArticleExtractor.mainText(fromHTML: html)

        #expect(text.contains("dólar fechou cotado"))
        #expect(!text.contains("Manchete número"))
    }

    @Test("Saída tem um parágrafo por linha, como o TextChunker espera")
    func outputIsParagraphPerLine() throws {
        let html = """
        <html><body><article>
          <p>Primeiro parágrafo da matéria, com texto suficiente para não ser descartado \
        como legenda ou crédito de foto.</p>
          <p>Segundo parágrafo da matéria, também com comprimento suficiente para entrar \
        na pontuação do bloco.</p>
        </article></body></html>
        """

        let text = try ArticleExtractor.mainText(fromHTML: html)
        let lines = text.split(whereSeparator: \.isNewline)

        #expect(lines.count == 2)
        // Contrato com TextChunker.paragraphs(in:): uma linha = um parágrafo.
        #expect(!TextChunker().chunks(from: text).isEmpty)
    }

    // MARK: - CA-05: fallback e descarte

    @Test("Extração curta cai para o content da busca (RF-05.3)")
    func fallsBackToSearchSnippet() async throws {
        // Página de paywall: só o teaser vem no HTML.
        let (session, _) = MockURLProtocol.makeSession([
            .success(status: 200, body: Data("<html><body><p>Assine para ler.</p></body></html>".utf8)),
        ])

        let snippet = String(repeating: "conteúdo real do snippet da Tavily. ", count: 10)
        let item = SearchResultItem(title: "t", url: "https://g1.globo.com/a",
                                    content: snippet, score: 0.9)

        let text = await ArticleExtractor(session: session).extractText(from: item)

        #expect(text != nil)
        #expect(text?.contains("conteúdo real do snippet") == true)
    }

    @Test("Fallback também curto descarta a fonte (CA-05)")
    func discardsWhenBothAreShort() async {
        let (session, _) = MockURLProtocol.makeSession([
            .success(status: 200, body: Data("<html><body><p>Assine.</p></body></html>".utf8)),
        ])

        let item = SearchResultItem(title: "t", url: "https://g1.globo.com/a",
                                    content: "trecho curto", score: 0.9)

        let text = await ArticleExtractor(session: session).extractText(from: item)

        #expect(text == nil)
    }

    @Test("Extração bem-sucedida nunca é substituída pelo snippet (DT-23)")
    func neverReplacesSuccessfulExtraction() async throws {
        let body = """
        <html><body><article>
          <p>Texto completo da matéria extraído do HTML da própria página, com bastante \
        conteúdo para passar do mínimo de duzentos caracteres exigido pela RF-05.3 sem \
        precisar de nenhum fallback para o snippet da busca.</p>
        </article></body></html>
        """
        let (session, _) = MockURLProtocol.makeSession([
            .success(status: 200, body: Data(body.utf8)),
        ])

        let item = SearchResultItem(
            title: "t", url: "https://g1.globo.com/a",
            content: String(repeating: "SNIPPET DA TAVILY. ", count: 20), score: 0.9
        )

        let text = try #require(
            await ArticleExtractor(session: session).extractText(from: item)
        )

        #expect(text.contains("Texto completo da matéria"))
        #expect(!text.contains("SNIPPET DA TAVILY"))
    }

    // MARK: - CA-06: timeout

    @Test("Timeout descarta a fonte sem lançar (CA-06)")
    func timeoutDiscardsSource() async {
        let (session, _) = MockURLProtocol.makeSession([.failure(.timedOut)])

        let item = SearchResultItem(title: "t", url: "https://g1.globo.com/a",
                                    content: "curto", score: 0.9)

        // Devolver nil em vez de lançar é o que permite ao coordenador seguir com as demais
        // fontes sem abortar a verificação.
        let text = await ArticleExtractor(session: session).extractText(from: item)

        #expect(text == nil)
    }

    @Test("Timeout configurado é de 8 segundos (RF-05.4)")
    func timeoutIsEightSeconds() {
        #expect(ArticleExtractor.timeout == 8)
    }

    @Test("Erro HTTP descarta a fonte, sem retry (item 14 em aberto)")
    func httpErrorDiscardsWithoutRetry() async {
        let (session, scenario) = MockURLProtocol.makeSession([.success(status: 500, body: Data())])

        let item = SearchResultItem(title: "t", url: "https://camara.leg.br/a",
                                    content: "curto", score: 0.9)

        let text = await ArticleExtractor(session: session).extractText(from: item)

        #expect(text == nil)
        // Retry por artigo continua em aberto e não foi implementado: 1 requisição, só.
        #expect(scenario.requestCount == 1)
    }
}

/// Âncora para localizar o bundle de teste.
private final class BundleToken {}
