//
//  EmbeddingService.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Accelerate
import CoreML
import Foundation

/// Converte texto em vetores e seleciona os chunks que seguem para o NLI (RF-06).
///
/// Modelo: `paraphrase-multilingual-MiniLM-L12-v2` INT8, rodando on-device (DT-02).
/// O mean pooling e a normalização L2 estão **dentro do grafo** Core ML (feitos no
/// `convert_embeddings.py` do Spike 2), então a saída já é o vetor de sentença pronto —
/// normalizar de novo em Swift seria redundante e mudaria a escala da similaridade.
struct EmbeddingService {

    /// Limiar mínimo de similaridade de cosseno (RF-06.7 / DT-24).
    ///
    /// Calibrado com os dados por par do Spike 2c: pares decisivos ficaram entre 0,31 e 0,86;
    /// neutros entre 0,09 e 0,17. 0,25 preserva 15/15 decisivos e descarta 4/5 neutros.
    /// Este piso é metade da defesa contra o "erro perigoso" do Spike 1 — o par que o NLI
    /// classificou errado com confiança 0,66 tinha similaridade 0,09 e nem chega ao NLI.
    static let minimumSimilarity: Double = 0.25

    /// Quantos chunks por artigo seguem para o NLI (RF-06.6 / DT-08 / CA-07).
    static let topChunkCount = 3

    private let model: MLModel
    private let tokenizer: XLMRTokenizer

    // MARK: - Carregamento

    /// - Throws: `VerificationError.modelLoadFailed` (RF-10.3).
    init(model: MLModel, tokenizer: XLMRTokenizer) {
        self.model = model
        self.tokenizer = tokenizer
    }

    /// Carrega o modelo do bundle em `.cpuOnly`.
    ///
    /// `.cpuOnly` é a única configuração medida em device físico no Spike 2 — 7 ms, muito
    /// abaixo dos 150 ms da NF-01. Vale a lição estrutural do Spike 2c: "converte sem erro" e
    /// "logits batem com o PyTorch" não implicaram execução em device real, então a
    /// configuração usada aqui é a que foi de fato exercitada em hardware, não a que parece
    /// mais rápida no papel.
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> EmbeddingService {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly

        let model = try CoreMLModelLoader.load(
            resource: "Embeddings",
            configuration: configuration,
            bundle: bundle
        )
        return EmbeddingService(model: model, tokenizer: try XLMRTokenizer.embeddings(bundle: bundle))
    }

    // MARK: - Embeddings

    /// Vetor de embedding do texto (RF-06.3 / RF-06.4).
    /// A afirmação do usuário e os chunks passam pelo mesmo caminho, logo caem no mesmo espaço.
    func embedding(for text: String) throws -> [Float] {
        let ids = tokenizer.encode(text)
        let count = ids.count

        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        for index in 0..<count {
            inputIDs[index] = NSNumber(value: Int32(ids[index]))
            // Sem padding: cada texto roda no seu próprio comprimento, aproveitando o
            // `RangeDim(1...512)` com que o modelo foi convertido. Daí a máscara ser toda 1.
            attentionMask[index] = 1
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])

        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw VerificationError.modelLoadFailed
        }

        var vector = [Float](repeating: 0, count: array.count)
        for index in 0..<array.count {
            vector[index] = array[index].floatValue
        }
        return vector
    }

    // MARK: - Similaridade

    /// Similaridade de cosseno entre dois vetores (RF-06.5 / DT-09), via Accelerate (§3.1).
    ///
    /// Não presume que os vetores já venham normalizados, apesar de o grafo normalizar: um
    /// produto interno cru daria resultado errado e silencioso se o modelo mudar.
    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        var dot: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &dot, vDSP_Length(lhs.count))

        var lhsSquared: Float = 0
        var rhsSquared: Float = 0
        vDSP_svesq(lhs, 1, &lhsSquared, vDSP_Length(lhs.count))
        vDSP_svesq(rhs, 1, &rhsSquared, vDSP_Length(rhs.count))

        let magnitude = sqrt(lhsSquared) * sqrt(rhsSquared)
        guard magnitude > 0 else { return 0 }
        return Double(dot / magnitude)
    }

    // MARK: - Seleção de chunks

    /// Um chunk aprovado para o NLI, com a similaridade que o aprovou.
    struct ScoredChunk: Equatable {
        let text: String
        let similarity: Double
    }

    /// Os chunks de um artigo que seguem para o NLI (RF-06.6 / CA-07).
    ///
    /// A ordem das duas operações é o requisito: **descarta abaixo do limiar e só então pega
    /// os 3 melhores**. Pegar o top-3 primeiro deixaria passar chunk irrelevante sempre que o
    /// artigo tivesse menos de 3 chunks acima do limiar — e é justamente o chunk irrelevante
    /// de baixa similaridade que produz o erro perigoso do NLI (RF-07.5).
    ///
    /// - Returns: de 0 a 3 chunks. Vazio significa que o artigo não fala sobre a afirmação;
    ///   ele não gera inferência de NLI nenhuma e não vira fonte analisada.
    func selectTopChunks(claim: String, chunks: [String]) throws -> [ScoredChunk] {
        guard !chunks.isEmpty else { return [] }

        let claimVector = try embedding(for: claim)

        return try chunks
            .map { chunk in
                ScoredChunk(
                    text: chunk,
                    similarity: Self.cosineSimilarity(claimVector, try embedding(for: chunk))
                )
            }
            .filter { $0.similarity >= Self.minimumSimilarity }
            .sorted { $0.similarity > $1.similarity }
            .prefix(Self.topChunkCount)
            .map { $0 }
    }
}
