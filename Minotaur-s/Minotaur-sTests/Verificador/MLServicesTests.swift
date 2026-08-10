//
//  MLServicesTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// RF-06 / RF-07 / DT-24 / DT-25 / CA-07.
///
/// Estes testes carregam os modelos Core ML do bundle do app (o target de teste roda hospedado
/// nele). Se `scripts/sync-models.sh` nunca rodou, eles falham com `.modelLoadFailed` — e isso
/// é informação, não ruído: significa que o app também não conseguiria analisar nada.
struct MLServicesTests {

    // MARK: - Similaridade de cosseno (RF-06.5)

    @Test("Cosseno de vetores idênticos é 1")
    func cosineOfIdenticalVectors() {
        let vector: [Float] = [0.5, -0.25, 0.75, 0.1]
        #expect(abs(EmbeddingService.cosineSimilarity(vector, vector) - 1.0) < 1e-5)
    }

    @Test("Cosseno de vetores ortogonais é 0")
    func cosineOfOrthogonalVectors() {
        #expect(abs(EmbeddingService.cosineSimilarity([1, 0], [0, 1])) < 1e-6)
    }

    @Test("Cosseno de vetores opostos é -1")
    func cosineOfOppositeVectors() {
        #expect(abs(EmbeddingService.cosineSimilarity([1, 2, 3], [-1, -2, -3]) + 1.0) < 1e-5)
    }

    @Test("Vetores de tamanhos diferentes ou vazios devolvem 0, não travam")
    func cosineOfMismatchedVectors() {
        #expect(EmbeddingService.cosineSimilarity([1, 2], [1, 2, 3]) == 0)
        #expect(EmbeddingService.cosineSimilarity([], []) == 0)
        #expect(EmbeddingService.cosineSimilarity([0, 0], [0, 0]) == 0)
    }

    // MARK: - Softmax (RF-07.2)

    @Test("Softmax soma 1 e preserva o argmax")
    func softmaxProperties() {
        let probabilities = NLIService.softmax([2.5, -1.0, 0.3])

        #expect(abs(probabilities.reduce(0, +) - 1.0) < 1e-9)
        #expect(probabilities.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(probabilities[0] == probabilities.max())
    }

    @Test("Softmax não estoura com logits grandes")
    func softmaxIsNumericallyStable() {
        // Sem subtrair o máximo, exp(1000) vira infinito e tudo vira NaN.
        let probabilities = NLIService.softmax([1000, 999, 998])

        #expect(probabilities.allSatisfy { $0.isFinite })
        #expect(abs(probabilities.reduce(0, +) - 1.0) < 1e-9)
    }

    // MARK: - Limiares definitivos

    @Test("Limiares são os valores da spec")
    func thresholdsMatchSpec() {
        #expect(EmbeddingService.minimumSimilarity == 0.25) // RF-06.7 / DT-24
        #expect(NLIService.minimumConfidence == 0.50)       // RF-07.5 / DT-25
        #expect(EmbeddingService.topChunkCount == 3)        // RF-06.6 / DT-08
    }

    // MARK: - CA-07: seleção de chunks

    @Test("No máximo 3 chunks seguem para o NLI")
    func selectsAtMostThreeChunks() throws {
        let service = try EmbeddingService.loadFromBundle()

        // 10 chunks, todos sobre o mesmo assunto da afirmação — sem o limite de 3, todos
        // passariam do limiar e todos gerariam inferência de NLI.
        let claim = "O desemprego caiu no último trimestre."
        let chunks = (1...10).map {
            "A taxa de desemprego recuou no trimestre encerrado em maio, segundo o IBGE, "
            + "na leitura número \($0) da pesquisa."
        }

        let selected = try service.selectTopChunks(claim: claim, chunks: chunks)

        #expect(selected.count <= EmbeddingService.topChunkCount)
    }

    @Test("Chunks abaixo do limiar são descartados antes do top-3")
    func discardsBelowThreshold() throws {
        let service = try EmbeddingService.loadFromBundle()

        let claim = "A taxa de desemprego caiu para o menor nível da série histórica."
        let chunks = [
            "O IBGE informou que a taxa de desemprego caiu para 6,2%, o menor patamar já "
            + "registrado desde o início da série histórica em 2012.",
            "O jogador marcou dois gols na partida de domingo pelo campeonato estadual.",
            "A receita de bolo de fubá leva três ovos, farinha de trigo e leite morno.",
        ]

        let selected = try service.selectTopChunks(claim: claim, chunks: chunks)

        // A ordem é: filtrar pelo limiar e SÓ ENTÃO pegar o top-3. Como só 1 chunk é
        // relevante, os outros dois não podem entrar só porque havia vaga sobrando.
        #expect(selected.allSatisfy { $0.similarity >= EmbeddingService.minimumSimilarity })
        #expect(selected.first?.text.contains("desemprego") == true)
        #expect(selected.count < 3,
                Comment(rawValue: "Chunks irrelevantes passaram: \(selected.map(\.similarity))"))
    }

    @Test("Resultado vem ordenado por similaridade decrescente")
    func selectionIsSortedBySimilarity() throws {
        let service = try EmbeddingService.loadFromBundle()

        let claim = "O dólar fechou em queda nesta sexta-feira."
        let chunks = [
            "A moeda norte-americana encerrou o pregão desta sexta-feira em queda de 0,8%.",
            "O dólar fechou cotado a R$ 5,12 nesta sexta-feira, em queda ante a sessão anterior.",
            "O Banco Central divulgou o relatório trimestral de inflação na semana passada.",
        ]

        let selected = try service.selectTopChunks(claim: claim, chunks: chunks)

        #expect(selected == selected.sorted { $0.similarity > $1.similarity })
    }

    @Test("Artigo sem chunk relevante não gera inferência de NLI")
    func irrelevantArticleYieldsNothing() throws {
        let service = try EmbeddingService.loadFromBundle()

        let selected = try service.selectTopChunks(
            claim: "O Supremo Tribunal Federal decidiu sobre a constitucionalidade da lei.",
            chunks: ["A receita de bolo de fubá leva três ovos, farinha de trigo e leite morno."]
        )

        #expect(selected.isEmpty)
    }

    @Test("Lista de chunks vazia não roda o modelo")
    func emptyChunksShortCircuits() throws {
        let service = try EmbeddingService.loadFromBundle()
        #expect(try service.selectTopChunks(claim: "qualquer coisa", chunks: []).isEmpty)
    }

    // MARK: - Embeddings

    @Test("Textos parecidos têm similaridade maior que textos sem relação")
    func embeddingSeparatesRelatedFromUnrelated() throws {
        let service = try EmbeddingService.loadFromBundle()

        let claim = try service.embedding(for: "O desemprego caiu no Brasil.")
        let related = try service.embedding(for: "A taxa de desocupação recuou no país.")
        let unrelated = try service.embedding(for: "O bolo de fubá leva três ovos.")

        let relatedScore = EmbeddingService.cosineSimilarity(claim, related)
        let unrelatedScore = EmbeddingService.cosineSimilarity(claim, unrelated)

        #expect(relatedScore > unrelatedScore)
        // O limiar de 0,25 só tem sentido se o modelo de fato separa nessa faixa.
        #expect(relatedScore >= EmbeddingService.minimumSimilarity)
        #expect(unrelatedScore < EmbeddingService.minimumSimilarity)
    }

    @Test("Embedding sai normalizado pelo grafo, não em Swift")
    func embeddingIsAlreadyNormalized() throws {
        let service = try EmbeddingService.loadFromBundle()
        let vector = try service.embedding(for: "Uma frase qualquer em português.")

        // O mean pooling e o L2 estão dentro do .mlpackage (convert_embeddings.py). Se esta
        // norma deixar de ser 1, a conversão mudou e a escala da similaridade mudou junto.
        let norm = sqrt(vector.reduce(0) { $0 + Double($1 * $1) })
        #expect(abs(norm - 1.0) < 1e-3,
                Comment(rawValue: "Norma \(norm): o grafo parou de normalizar"))
    }

    // MARK: - NLI

    @Test("Saída do NLI em Swift reproduz a referência PyTorch")
    func nliMatchesPyTorchReference() throws {
        // Esta é a asserção que importa, e substitui um "esperado: entailment" escrito por
        // mim: comparar com o PyTorch mede se o caminho Swift (tokenização + Core ML +
        // softmax) está correto. Escrever o rótulo que um humano daria mediria a acurácia do
        // modelo — medida separadamente no conjunto adversarial do Spike 9, não um bug do app.
        let service = try NLIService.loadFromBundle()

        for sample in try NLIReferenceFixture.load() {
            let prediction = try service.predict(
                premise: sample.premise,
                hypothesis: sample.hypothesis
            )

            #expect(prediction.label == sample.expectedLabel,
                    Comment(rawValue: "\(sample.hypothesis)\n"
                        + "referência: \(sample.expectedLabel), obtido: \(prediction.label)"))
            // INT8 introduz desvio pequeno; 0,05 é folga suficiente sem esconder erro real.
            #expect(abs(prediction.confidence - sample.expectedConfidence) < 0.05,
                    Comment(rawValue: "\(sample.hypothesis)\n"
                        + "referência: \(sample.expectedConfidence), "
                        + "obtido: \(prediction.confidence)"))
        }
    }

    @Test("Contradiction em PT-BR é detectada")
    func detectsContradiction() throws {
        let service = try NLIService.loadFromBundle()

        let prediction = try service.predict(
            premise: "A prefeitura informou que o novo hospital municipal só será inaugurado "
                   + "em 2027, após o adiamento das obras.",
            hypothesis: "O hospital municipal foi inaugurado neste ano."
        )

        #expect(prediction.label == .contradiction)
        #expect(prediction.confidence > NLIService.minimumConfidence)
    }

    @Test("NLI não confirma os seis casos críticos de Terra plana e vacina")
    func rejectsMaterializedHarmCases() throws {
        let service = try NLIService.loadFromBundle()
        let cases: [(premise: String, hypothesis: String, acceptsNeutral: Bool)] = [
            (
                "Algumas teorias da conspiração que afirmam que a Terra é plana continuam "
                    + "se espalhando. Estas são algumas maneiras simples de comprovar que a "
                    + "Terra é redonda e rebater essas ideias dos terraplanistas.",
                "A Terra é plana.",
                false
            ),
            (
                "Pode parecer mentira, mas em pleno século 21 ainda é necessário insistir que "
                    + "a Terra é redonda, algo que se sabe há mais de 2 mil anos. Algumas "
                    + "teorias da conspiração que afirmam que a Terra é plana continuam se "
                    + "espalhando.",
                "A Terra é plana.",
                false
            ),
            (
                "Se a Terra fosse plana e você olhasse para longe, veria a mesma paisagem se "
                    + "estivesse no chão ou na copa da árvore.",
                "A Terra é plana.",
                true
            ),
            (
                "A vacinação contra a gripe pode reduzir significativamente o risco de infarto "
                    + "e AVC (acidente vascular cerebral), explicou o Dr. Roberto Kalil.",
                "Vacina da gripe causa infarto.",
                false
            ),
            (
                "\"A vacina para a gripe se torna extremamente importante ao reduzir de 20% a "
                    + "30% a incidência de infarto e acidente vascular cerebral\", afirmou Dr. "
                    + "Kalil.",
                "Vacina da gripe causa infarto.",
                false
            ),
            (
                "A vacinação contra o vírus Influenza tem como principal objetivo proteger a "
                    + "população da gripe. No entanto, há benefícios secundários: a proteção "
                    + "contra infartos e acidentes vasculares cerebrais (AVC).",
                "Vacina da gripe causa infarto.",
                false
            ),
        ]

        for sample in cases {
            let prediction = try service.predict(
                premise: sample.premise,
                hypothesis: sample.hypothesis
            )
            if sample.acceptsNeutral {
                #expect(prediction.label != .entailment)
            } else {
                #expect(prediction.label == .contradiction)
            }
        }
    }

    @Test("Rótulo abaixo de 0,50 de confiança é rebaixado para neutral (RF-07.4)")
    func lowConfidenceIsDemoted() throws {
        let service = try NLIService.loadFromBundle()

        // Premissa sem relação com a hipótese: qualquer rótulo direcional aqui seria ruído.
        let chunks = [EmbeddingService.ScoredChunk(
            text: "O time treinou normalmente no centro de treinamento durante a manhã.",
            similarity: 0.3
        )]

        let label = try #require(
            try service.label(for: "A inflação subiu no último trimestre.", chunks: chunks)
        )

        if label.confidence < NLIService.minimumConfidence {
            #expect(label.label == .neutral)
        }
        // O trecho vencedor continua sendo exibível mesmo após o rebaixamento (RF-09.4).
        #expect(!label.excerpt.isEmpty)
    }

    @Test("Neutro não compete: a direcional vence o distrator confiante (RF-07.3)")
    func directionalBeatsConfidentNeutral() throws {
        let service = try NLIService.loadFromBundle()

        let chunks = [
            // Medido: este chunk dá neutral com 0,9930 — MAIS confiante que o entailment
            // correto abaixo. Sob a leitura literal da RF-07.3 ele venceria e o artigo seria
            // neutro, jogando fora a evidência.
            EmbeddingService.ScoredChunk(
                text: "O relatório menciona diversos indicadores econômicos do período.",
                similarity: 0.30
            ),
            EmbeddingService.ScoredChunk(
                text: "O Instituto Brasileiro de Geografia e Estatística divulgou nesta "
                    + "quinta-feira que a taxa de desemprego caiu para 6,2% no trimestre "
                    + "encerrado em maio.",
                similarity: 0.80
            ),
        ]

        let label = try #require(
            try service.label(for: "A taxa de desemprego caiu para 6,2%.", chunks: chunks)
        )

        #expect(label.label == .entailment)
        // O chunk vencedor é o que vira o trecho citado na tela (RF-09.4).
        #expect(label.excerpt.contains("6,2%"))
        #expect(label.similarity == 0.80)
    }

    @Test("Sem direcional convincente, o artigo é neutro e exibe o chunk mais similar")
    func neutralArticleShowsMostSimilarChunk() throws {
        let service = try NLIService.loadFromBundle()

        let chunks = [
            EmbeddingService.ScoredChunk(
                text: "O time treinou normalmente no centro de treinamento durante a manhã.",
                similarity: 0.28
            ),
            EmbeddingService.ScoredChunk(
                text: "O relatório menciona diversos indicadores econômicos do período.",
                similarity: 0.44
            ),
        ]

        let label = try #require(
            try service.label(for: "A inflação subiu no último trimestre.", chunks: chunks)
        )

        #expect(label.label == .neutral)
        // Mesmo neutro, o usuário recebe o trecho mais relacionado que o artigo tem.
        #expect(label.similarity == 0.44)
        #expect(!label.excerpt.isEmpty)
    }

    @Test("Sem chunk selecionado, o artigo não vira fonte analisada")
    func noChunksMeansNoLabel() throws {
        let service = try NLIService.loadFromBundle()
        #expect(try service.label(for: "qualquer coisa", chunks: []) == nil)
    }
}
