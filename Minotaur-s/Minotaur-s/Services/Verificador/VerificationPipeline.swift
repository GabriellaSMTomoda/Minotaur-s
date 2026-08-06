//
//  VerificationPipeline.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Etapa corrente da verificação, exibida como indicador de progresso (RF-01.4).
///
/// Os três casos são exatamente os três da RF-01.4 — buscando → lendo fontes → analisando.
/// O enum não carrega texto de UI: a cópia em português é decisão da tela (fase futura), não
/// do coordenador.
enum VerificationStage: Equatable, Sendable {
    /// Consulta ao provedor de busca (RF-04).
    case searching
    /// Download e extração dos artigos aprovados, em paralelo (RF-05).
    case readingSources
    /// Embeddings, seleção de chunks e NLI (RF-06/RF-07).
    case analyzing
}

// MARK: - Portas do coordenador

/// Busca de artigos na allowlist (RF-04). Implementada por `TavilySearchService`.
protocol ArticleSearching: Sendable {
    /// Domínios efetivamente consultados (RF-09.6 / DT-32) — pela porta, não pelo tipo
    /// concreto, para que produção e mocks de teste alimentem `VerificationResult` do mesmo
    /// jeito.
    var consultedDomains: [String] { get }
    func search(query: String) async throws -> [SearchResultItem]
}

/// Download e extração do texto principal (RF-05). Implementada por `ArticleExtractor`.
protocol ArticleTextExtracting: Sendable {
    func extractText(from item: SearchResultItem) async -> String?
}

/// Seleção dos chunks que seguem para o NLI (RF-06). Implementada por `EmbeddingService`.
protocol ChunkSelecting {
    func selectTopChunks(claim: String, chunks: [String]) throws -> [EmbeddingService.ScoredChunk]
}

/// Rótulo de NLI por artigo (RF-07). Implementada por `NLIService`.
protocol ChunkClassifying {
    func label(for claim: String, chunks: [EmbeddingService.ScoredChunk]) throws -> NLIService.ArticleLabel?
}

extension TavilySearchService: ArticleSearching {}
extension ArticleExtractor: ArticleTextExtracting {}
extension EmbeddingService: ChunkSelecting {}
extension NLIService: ChunkClassifying {}

// MARK: - Coordenador

/// Orquestra a verificação de ponta a ponta: busca → extração → embeddings → NLI → veredito.
///
/// É o único ponto do pipeline que conhece a **ordem** das etapas; cada serviço continua
/// ignorando os demais (DT-17). Não tem estado: uma instância serve para verificações
/// sucessivas, e nada de uma verificação sobrevive à outra (§5 — nenhuma persistência).
///
/// **Dependências por protocolo, não por tipo concreto.** `EmbeddingService` e `NLIService`
/// carregam um `MLModel` do bundle, então um teste que dependesse deles precisaria de 216 MB
/// de modelo e de hardware real. As quatro portas acima existem para que os testes de fluxo
/// (CA-01/CA-02/CA-09) rodem só com mocks — os testes que exercitam os modelos de verdade
/// continuam em `MLServicesTests`, onde a dependência é intencional.
///
/// **Isolamento.** `verify` é uma função async não-isolada, então roda no executor genérico
/// mesmo quando chamada de dentro de um `Task` da View (`@MainActor`) — a inferência de Core
/// ML nunca cai na main thread (NF-04). Marcar este tipo com `@MainActor` na fase de UI
/// desfaria essa garantia.
struct VerificationPipeline {

    /// Recebe cada mudança de etapa (RF-01.4).
    ///
    /// É chamado fora da main thread, pelo motivo do parágrafo de isolamento acima — quem
    /// atualizar estado de UI a partir daqui precisa saltar para o `MainActor`.
    typealias ProgressHandler = @Sendable (VerificationStage) -> Void

    /// Piso do orçamento de tokens por chunk, ver `chunker(for:)`.
    static let minimumChunkTokens = 64

    private let search: any ArticleSearching
    private let extractor: any ArticleTextExtracting
    private let embeddings: any ChunkSelecting
    private let nli: any ChunkClassifying

    init(
        search: any ArticleSearching,
        extractor: any ArticleTextExtracting,
        embeddings: any ChunkSelecting,
        nli: any ChunkClassifying
    ) {
        self.search = search
        self.extractor = extractor
        self.embeddings = embeddings
        self.nli = nli
    }

    /// Monta o pipeline de produção, carregando os dois modelos Core ML do bundle.
    ///
    /// - Throws: `VerificationError.modelLoadFailed` (RF-10.3). Falhar aqui, e não no meio de
    ///   uma verificação, é o comportamento desejado: a tela bloqueia a funcionalidade com
    ///   mensagem própria em vez de o usuário descobrir o problema depois de esperar a busca.
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> VerificationPipeline {
        VerificationPipeline(
            search: TavilySearchService(),
            extractor: ArticleExtractor(),
            embeddings: try EmbeddingService.loadFromBundle(bundle),
            nli: try NLIService.loadFromBundle(bundle)
        )
    }

    // MARK: - Fluxo

    /// Executa a verificação completa da afirmação.
    ///
    /// **Cancelamento (RF-01.5 / CA-09).** É cooperativo, via cancelamento do `Task` que
    /// chamou este método: a View guarda o handle e chama `cancel()` no botão Cancelar. Há
    /// checagem entre todas as etapas e **dentro** de cada tarefa paralela de extração — não
    /// só na entrada. O motivo está em `extractArticles`.
    ///
    /// - Parameter onProgress: notificado a cada etapa, na ordem da RF-01.4.
    /// - Returns: resultado em memória, com o veredito agregado e as fontes analisadas. Nunca
    ///   é persistido (§5).
    /// - Throws: `CancellationError` se a verificação foi cancelada; caso contrário sempre um
    ///   caso de `VerificationError` (RF-10.4) — nunca um erro cru de rede ou de Core ML.
    func verify(
        claim: String,
        onProgress: ProgressHandler = { _ in }
    ) async throws -> VerificationResult {
        try Task.checkCancellation()

        // 1. Busca (RF-02 / RF-04).
        onProgress(.searching)
        let query = SearchQueryBuilder.query(from: claim)
        let results = try await runSearch(query: query)
        try Task.checkCancellation()

        // 2. Zero resultados: veredito direto, sem extração, embeddings ou NLI (RF-04.4/CA-02).
        //    Um resultado que só existia fora da allowlist já foi descartado pelo filtro
        //    (RF-03.5) e chega aqui como lista vazia — para o usuário é o mesmo caso.
        guard !results.isEmpty else {
            return result(claim: claim, sources: [])
        }

        // 3. Extração em paralelo (RF-05.6).
        onProgress(.readingSources)
        let articles = try await extractArticles(results)
        try Task.checkCancellation()

        // 4. Análise: embeddings → top-3 → NLI (RF-06 / RF-07).
        onProgress(.analyzing)
        let sources = try analyze(claim: claim, articles: articles)
        try Task.checkCancellation()

        // 5. Agregação (RF-08). Lista vazia de fontes vira `NAO_ENCONTRADO` dentro do
        //    agregador — inclusive quando a busca achou artigos mas todos foram descartados
        //    por paywall, timeout ou irrelevância (RF-08.1).
        return result(claim: claim, sources: sources)
    }

    // MARK: - Etapa 1: busca

    private func runSearch(query: String) async throws -> [SearchResultItem] {
        do {
            return try await search.search(query: query)
        } catch {
            // Cancelar durante a busca chega aqui como `URLError.cancelled`, que o serviço já
            // achatou em `.searchRequestFailed`. Cancelamento não é falha de busca: a checagem
            // vem antes do mapeamento para não exibir "erro de rede" a quem tocou em Cancelar.
            try Task.checkCancellation()
            throw Self.mapped(error, to: .searchRequestFailed)
        }
    }

    // MARK: - Etapa 2: extração

    /// Artigo aprovado na busca e com texto extraído com sucesso.
    private struct Article {
        let item: SearchResultItem
        let text: String
    }

    /// Baixa e extrai os artigos **em paralelo** (RF-05.6), preservando a ordem da busca.
    ///
    /// A checagem de cancelamento **dentro** de cada tarefa filha não é redundante com a da
    /// entrada: `ArticleExtractor.extractText` devolve `nil` para qualquer falha, cancelamento
    /// incluído (é o que faz timeout e paywall descartarem a fonte sem abortar o fluxo,
    /// CA-05/CA-06). Sem a checagem explícita depois da chamada, uma verificação cancelada no
    /// meio do download degradaria silenciosamente para "todas as fontes foram descartadas" e
    /// seguiria para a inferência — o oposto do que a CA-09 exige.
    ///
    /// Sair do grupo por erro cancela as tarefas filhas restantes, e o `URLSession` aborta os
    /// downloads pendentes: nenhuma requisição sobrevive ao cancelamento (CA-09).
    private func extractArticles(_ items: [SearchResultItem]) async throws -> [Article] {
        let extractor = self.extractor

        let texts = try await withThrowingTaskGroup(
            of: (offset: Int, text: String)?.self
        ) { group in
            for (offset, item) in items.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    let text = await extractor.extractText(from: item)
                    try Task.checkCancellation()

                    // `nil` aqui é fonte descartada (RF-05.3/RF-05.4), não erro: o fluxo
                    // continua com as demais.
                    guard let text else { return nil }
                    return (offset, text)
                }
            }

            var byOffset: [Int: String] = [:]
            for try await produced in group {
                guard let produced else { continue }
                byOffset[produced.offset] = produced.text
            }
            return byOffset
        }

        // A ordem de conclusão das tarefas é arbitrária; a lista de fontes segue o ranking da
        // busca, que é o que o usuário vê na tela (RF-09.2).
        return items.enumerated().compactMap { offset, item in
            texts[offset].map { Article(item: item, text: $0) }
        }
    }

    // MARK: - Etapa 3: análise

    /// Roda embeddings e NLI por artigo, em série.
    ///
    /// Serial de propósito, ao contrário da extração: os dois modelos rodam em `.cpuOnly`
    /// (DT-18) e disputariam os mesmos núcleos, sem ganho de tempo e com pico de RAM maior
    /// (NF-06). O paralelismo que a spec pede é o de rede (RF-05.6), e ele acontece antes.
    ///
    /// Artigo sem chunk acima do limiar de similaridade não gera inferência de NLI nenhuma
    /// (RF-06.6 / CA-07) e não vira fonte analisada.
    private func analyze(claim: String, articles: [Article]) throws -> [SourceResult] {
        let chunker = Self.chunker(for: claim)
        var sources: [SourceResult] = []

        for article in articles {
            // Antes de cada artigo: cancelar não pode deixar o próximo artigo inferir (CA-09).
            try Task.checkCancellation()

            // DT-33: byline, navegação, legenda e título de página saem antes dos embeddings.
            // Antes dos embeddings, e não entre a similaridade e o NLI, porque eles repetem as
            // palavras-chave da afirmação e pontuam alto — deixá-los concorrer no top-3 (RF-06.6)
            // custa uma vaga de chunk com proposição de verdade.
            //
            // Sobrar zero chunk é resultado legítimo: o artigo não vira fonte válida e é
            // descartado pelo mesmo caminho de uma extração fracassada (RF-05.3), sem abortar as
            // demais. Foi o caso do artigo cujo único chunk era o título de um Web Story.
            let chunks = ChunkQualityFilter.keeping(chunker.chunks(from: article.text))
            guard !chunks.isEmpty else { continue }

            let selected = try runInference { try embeddings.selectTopChunks(claim: claim, chunks: chunks) }
            guard !selected.isEmpty else { continue }

            // Entre embeddings e NLI: são duas rodadas de inferência distintas, e a segunda é
            // a cara. Cancelar durante a primeira não pode disparar a segunda.
            try Task.checkCancellation()

            guard let label = try runInference({ try nli.label(for: claim, chunks: selected) })
            else { continue }

            sources.append(
                SourceResult(
                    url: article.item.url,
                    domain: Self.domain(of: article.item),
                    title: article.item.title,
                    label: label.label,
                    confidence: label.confidence,
                    similarity: label.similarity,
                    // O corte em 300 caracteres da RF-09.4/CA-10 é feito pelo `SourceResult`.
                    excerpt: label.excerpt
                )
            )
        }

        return sources
    }

    /// Orçamento de tokens por chunk, descontando a afirmação do usuário (RF-06.2).
    ///
    /// O limite de 512 é do **par** `[CLS] chunk [SEP] afirmação [SEP]`, não do chunk sozinho.
    /// Chunk dimensionado para 512 cheios faria o tokenizador cortar a premissa na hora do NLI
    /// (ver `BERTTokenizer.encodePair`) — o fim do chunk vencedor sumiria da inferência sem
    /// nenhum sinal. O piso de `minimumChunkTokens` evita que uma afirmação no limite da
    /// RF-01.2 (1.000 caracteres) produza chunks pequenos demais para carregar sentido.
    ///
    /// A contagem é a estimativa conservadora do `TextChunker`, não o tokenizador real: errar
    /// para mais mantém o par dentro do limite, que é o objetivo.
    private static func chunker(for claim: String) -> TextChunker {
        let specialTokens = 3 // [CLS] … [SEP] … [SEP]
        let budget = BERTTokenizer.maxSequenceLength
            - specialTokens
            - TextChunker.conservativeTokenEstimate(claim)

        return TextChunker(maxTokens: max(minimumChunkTokens, budget))
    }

    /// Executa uma inferência mapeando qualquer erro para a categoria da RF-10.3.
    ///
    /// Falha de Core ML no meio da análise aborta a verificação inteira em vez de descartar só
    /// aquele artigo: o modelo é o mesmo para todos, então o que falhou num artigo falharia em
    /// todos. Degradar silenciosamente produziria um veredito com menos fontes e sem nenhum
    /// sinal de que a análise está quebrada.
    private func runInference<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            try Task.checkCancellation()
            throw Self.mapped(error, to: .modelLoadFailed)
        }
    }

    // MARK: - Resultado

    private func result(claim: String, sources: [SourceResult]) -> VerificationResult {
        VerificationResult(
            id: UUID(),
            claim: claim,
            createdAt: Date(),
            verdict: VerdictAggregator.verdict(for: sources),
            consultedDomains: search.consultedDomains,
            sources: sources
        )
    }

    /// Veículo a que a fonte pertence, para exibição (RF-09.2) e rastreio (RF-03.3).
    ///
    /// A entrada da allowlist é o valor esperado — o item já passou pelo filtro da RF-03.5, e
    /// só chegaria aqui sem correspondência se a lista mudasse no meio da verificação. Nesse
    /// caso vale mais mostrar o host do que descartar uma fonte já analisada.
    private static func domain(of item: SearchResultItem) -> String {
        guard let url = item.resolvedURL else { return item.url }
        return AllowlistFilter.matchedDomain(for: url)
            ?? AllowlistFilter.normalizedHost(from: url)
            ?? item.url
    }

    // MARK: - Erros

    /// Converte um erro qualquer numa categoria que a tela sabe exibir (RF-10.4).
    ///
    /// Não é catch-all: o `fallback` é escolhido por etapa (falha de busca na busca, modelo na
    /// inferência), e erro que já é `VerificationError` passa intacto — é como `.noConnection`
    /// (CA-08) e `.searchQuotaExceeded` (RF-10.2) chegam à tela com a mensagem certa.
    /// `CancellationError` nunca vira erro de categoria: cancelar não é falhar.
    private static func mapped(_ error: Error, to fallback: VerificationError) -> Error {
        if error is CancellationError { return error }
        if let error = error as? VerificationError { return error }
        if let error = error as? URLError, error.code == .cancelled { return CancellationError() }
        return fallback
    }
}
