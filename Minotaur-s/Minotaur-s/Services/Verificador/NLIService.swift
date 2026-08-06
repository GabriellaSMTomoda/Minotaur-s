//
//  NLIService.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import CoreML
import Foundation

/// Classifica a relação entre um chunk de artigo e a afirmação do usuário (RF-07).
///
/// Modelo: BERTimbau-base fine-tuned em PLUE/MNLI, INT8, em `.cpuOnly` (Spike 9).
/// Foi selecionado exclusivamente pelo macro-F1 do PLUE dev_matched e passou depois pelo gate
/// adversarial, pela paridade PyTorch/Core ML e pelos limites de RAM e latência em iPhone físico.
struct NLIService {

    /// Limiar mínimo de confiança (RF-07.5 / DT-25). Abaixo dele o rótulo vira `neutral`.
    ///
    /// Sozinho este limiar não isola o "erro perigoso" observado no Spike 1: aquele caso teve
    /// confiança 0,66, na mesma faixa de um entailment correto. Quem o filtra é o piso de
    /// similaridade da RF-06.7 — o par tinha similaridade 0,09 e nem chega aqui. Os dois
    /// limiares resolvem o risco **em conjunto**; mexer em um sem o outro reabre o buraco.
    static let minimumConfidence: Double = 0.50

    private let model: MLModel
    private let tokenizer: BERTTokenizer

    /// Ordem das classes na saída do modelo, lida de `NLILabels.json`.
    ///
    /// Nunca presumida: a ordem deste modelo é `[entailment, neutral, contradiction]`, mas
    /// outros checkpoints de NLI usam ordens diferentes, e trocar entailment por contradiction
    /// inverteria o veredito sem erro visível em lugar nenhum.
    private let labels: [NLILabel]

    init(model: MLModel, tokenizer: BERTTokenizer, labels: [NLILabel]) {
        self.model = model
        self.tokenizer = tokenizer
        self.labels = labels
    }

    // MARK: - Carregamento

    /// Carrega o modelo do bundle em `.cpuOnly`.
    ///
    /// `.cpuOnly` é o caminho medido no gate físico do Spike 9 e parte do contrato operacional.
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> NLIService {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly

        let model = try CoreMLModelLoader.load(
            resource: "NLI",
            configuration: configuration,
            bundle: bundle
        )
        return NLIService(
            model: model,
            tokenizer: try BERTTokenizer.nli(bundle: bundle),
            labels: try loadLabels(bundle: bundle)
        )
    }

    /// Lê `id2label` do asset exportado e o converte na ordem dos índices de saída.
    static func loadLabels(bundle: Bundle = .main) throws -> [NLILabel] {
        struct LabelConfig: Decodable { let id2label: [String: String] }

        guard
            let url = bundle.url(forResource: "NLILabels", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(LabelConfig.self, from: data)
        else {
            throw VerificationError.modelLoadFailed
        }

        let ordered = config.id2label
            .compactMap { key, value -> (Int, NLILabel)? in
                guard let index = Int(key), let label = NLILabel(rawValue: value.lowercased())
                else { return nil }
                return (index, label)
            }
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }

        // Um rótulo desconhecido ou faltando corromperia a leitura da saída inteira.
        guard ordered.count == 3, Set(ordered).count == 3 else {
            throw VerificationError.modelLoadFailed
        }
        return ordered
    }

    // MARK: - Inferência

    /// Resultado do NLI para um par (chunk, afirmação).
    struct Prediction: Equatable {
        let label: NLILabel
        let confidence: Double
    }

    /// Roda o modelo para um par premissa/hipótese (RF-07.1 / RF-07.2).
    ///
    /// A ordem dos argumentos importa e não é simétrica: **premissa = chunk do artigo**,
    /// **hipótese = afirmação do usuário**. Invertê-la faria a pergunta ao contrário ("o que
    /// o usuário disse sustenta o que o jornal publicou?").
    ///
    /// - Returns: o rótulo de maior probabilidade e a probabilidade dele. **Sem** aplicar o
    ///   limiar da RF-07.4 — o rebaixamento acontece por artigo, em `label(for:)`, depois de
    ///   comparar todos os chunks.
    func predict(premise: String, hypothesis: String) throws -> Prediction {
        let encoded = tokenizer.encodePair(premise: premise, hypothesis: hypothesis)
        let count = encoded.inputIDs.count

        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        let tokenTypeIDs = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        for index in 0..<count {
            inputIDs[index] = NSNumber(value: Int32(encoded.inputIDs[index]))
            attentionMask[index] = NSNumber(value: Int32(encoded.attentionMask[index]))
            tokenTypeIDs[index] = NSNumber(value: Int32(encoded.tokenTypeIDs[index]))
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
            "token_type_ids": MLFeatureValue(multiArray: tokenTypeIDs),
        ])

        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "logits")?.multiArrayValue,
              array.count == labels.count
        else {
            throw VerificationError.modelLoadFailed
        }

        var logits = [Double](repeating: 0, count: array.count)
        for index in 0..<array.count {
            logits[index] = array[index].doubleValue
        }

        // O grafo devolve logits crus — o softmax foi deixado de fora na conversão (Spike 2c).
        let probabilities = Self.softmax(logits)
        guard let best = probabilities.indices.max(by: { probabilities[$0] < probabilities[$1] })
        else {
            throw VerificationError.modelLoadFailed
        }
        return Prediction(label: labels[best], confidence: probabilities[best])
    }

    /// Rótulo de um artigo a partir dos chunks selecionados (RF-07.3 / RF-07.4).
    ///
    /// **Neutro não compete entre chunks.** Vence a predição *direcional* (entailment ou
    /// contradiction) de maior probabilidade; o artigo só fica neutro se nenhuma direcional
    /// alcançar `minimumConfidence`.
    ///
    /// A leitura literal da RF-07.3 — argmax sobre todos os chunks, neutro incluído — foi
    /// medida e não funciona: o modelo é confiantíssimo ao declarar neutralidade sobre texto
    /// fora do assunto (0,9930 num chunk distrator, contra 0,9883 de um entailment correto no
    /// mesmo artigo). Como a RF-06.6 sempre manda até 3 chunks e artigo real quase sempre tem
    /// algum fora do assunto, o vencedor seria sistematicamente um neutro confiante e o
    /// veredito colapsaria em `SEM_INFORMACAO`. Esta regra espelha no nível do artigo o mesmo
    /// princípio que a DT-26 já adota no nível do veredito.
    ///
    /// O chunk vencedor é o que vira o trecho citado na tela (RF-09.4).
    ///
    /// - Returns: `nil` se não houver chunk selecionado; o artigo não vira fonte analisada.
    func label(for claim: String, chunks: [EmbeddingService.ScoredChunk]) throws -> ArticleLabel? {
        guard !chunks.isEmpty else { return nil }

        var scored: [(chunk: EmbeddingService.ScoredChunk, prediction: Prediction)] = []
        for chunk in chunks {
            scored.append((chunk, try predict(premise: chunk.text, hypothesis: claim)))
        }

        // RF-07.4: direcional abaixo do limiar não conta como evidência.
        let directional = scored
            .filter { $0.prediction.label != .neutral }
            .filter { $0.prediction.confidence >= Self.minimumConfidence }

        if let best = directional.max(by: { $0.prediction.confidence < $1.prediction.confidence }) {
            return ArticleLabel(
                label: best.prediction.label,
                confidence: best.prediction.confidence,
                similarity: best.chunk.similarity,
                excerpt: best.chunk.text
            )
        }

        // Nenhuma direcional convincente: o artigo é neutro. O trecho exibido passa a ser o de
        // maior similaridade — é o mais relacionado que o artigo tem a oferecer ao leitor.
        guard let fallback = scored.max(by: { $0.chunk.similarity < $1.chunk.similarity })
        else { return nil }

        return ArticleLabel(
            label: .neutral,
            confidence: fallback.prediction.confidence,
            similarity: fallback.chunk.similarity,
            excerpt: fallback.chunk.text
        )
    }

    /// Rótulo consolidado de um artigo, pronto para virar `SourceResult`.
    struct ArticleLabel: Equatable {
        let label: NLILabel
        let confidence: Double
        let similarity: Double
        /// Chunk que motivou o rótulo. O truncamento em 300 caracteres da RF-09.4 é feito
        /// pelo `SourceResult.init`, não aqui — o texto inteiro ainda pode ser útil.
        let excerpt: String
    }

    // MARK: - Softmax

    /// Softmax estável: subtrai o máximo antes de exponenciar, para não estourar em `exp`.
    static func softmax(_ logits: [Double]) -> [Double] {
        guard let maximum = logits.max() else { return [] }
        let exponentials = logits.map { exp($0 - maximum) }
        let total = exponentials.reduce(0, +)
        guard total > 0 else { return logits.map { _ in 0 } }
        return exponentials.map { $0 / total }
    }
}
