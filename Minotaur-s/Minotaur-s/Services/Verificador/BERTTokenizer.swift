//
//  BERTTokenizer.swift
//  Minotaur-s
//
//  Integração do BERTimbau-base selecionado no Spike 9.
//

import Foundation
import Hub
import Tokenizers

/// Tokenização WordPiece do BERTimbau usado exclusivamente pelo NLI.
///
/// O modelo de embeddings continua usando XLM-R. O NLI selecionado no Spike 9 usa o formato
/// BERT `[CLS] premissa [SEP] hipótese [SEP]` e exige também `token_type_ids`; misturar os
/// dois formatos produz entradas válidas no Core ML, mas semanticamente erradas.
struct BERTTokenizer {

    /// Limite da RF-06.2 e limite superior do `RangeDim` validado no Spike 9.
    static let maxSequenceLength = 512

    struct EncodedPair: Equatable {
        let inputIDs: [Int]
        let attentionMask: [Int]
        let tokenTypeIDs: [Int]
    }

    private let tokenizer: any Tokenizer
    private let clsTokenID: Int
    private let sepTokenID: Int

    init(
        tokenizerResource: String,
        configResource: String,
        bundle: Bundle = .main
    ) throws {
        guard
            let tokenizerURL = bundle.url(forResource: tokenizerResource, withExtension: "json"),
            let configURL = bundle.url(forResource: configResource, withExtension: "json"),
            let tokenizerData = try? Data(contentsOf: tokenizerURL),
            let configData = try? Data(contentsOf: configURL)
        else {
            throw VerificationError.modelLoadFailed
        }

        let decoder = JSONDecoder()
        guard
            let tokenizerConfig = try? decoder.decode(Config.self, from: configData),
            let tokenizerJSON = try? decoder.decode(Config.self, from: tokenizerData),
            let tokenizer = try? AutoTokenizer.from(
                tokenizerConfig: tokenizerConfig,
                tokenizerData: tokenizerJSON
            ),
            let cls = tokenizer.convertTokenToId("[CLS]"),
            let sep = tokenizer.convertTokenToId("[SEP]")
        else {
            throw VerificationError.modelLoadFailed
        }

        self.tokenizer = tokenizer
        self.clsTokenID = cls
        self.sepTokenID = sep
    }

    static func nli(bundle: Bundle = .main) throws -> BERTTokenizer {
        try BERTTokenizer(
            tokenizerResource: "NLITokenizer",
            configResource: "NLITokenizerConfig",
            bundle: bundle
        )
    }

    /// Codifica `[CLS] premissa [SEP] hipótese [SEP]` preservando a hipótese quando possível.
    ///
    /// A premissa é o chunk dimensionado pelo pipeline. Se o par exceder 512, ela é truncada
    /// primeiro. Uma hipótese isoladamente maior que o limite só pode ser truncada como rede de
    /// segurança; a RF-01.2 e o orçamento do chunk evitam esse caminho no uso normal.
    func encodePair(premise: String, hypothesis: String) -> EncodedPair {
        let premiseTokens = tokenizer.encode(text: premise, addSpecialTokens: false)
        let rawHypothesisTokens = tokenizer.encode(text: hypothesis, addSpecialTokens: false)
        let bodyBudget = Self.maxSequenceLength - 3 // [CLS], [SEP], [SEP]
        let hypothesisTokens = Array(rawHypothesisTokens.prefix(bodyBudget))
        let premiseBudget = max(0, bodyBudget - hypothesisTokens.count)
        let retainedPremise = Array(premiseTokens.prefix(premiseBudget))

        let inputIDs = [clsTokenID]
            + retainedPremise
            + [sepTokenID]
            + hypothesisTokens
            + [sepTokenID]
        let tokenTypeIDs = [Int](repeating: 0, count: retainedPremise.count + 2)
            + [Int](repeating: 1, count: hypothesisTokens.count + 1)

        return EncodedPair(
            inputIDs: inputIDs,
            attentionMask: [Int](repeating: 1, count: inputIDs.count),
            tokenTypeIDs: tokenTypeIDs
        )
    }
}
