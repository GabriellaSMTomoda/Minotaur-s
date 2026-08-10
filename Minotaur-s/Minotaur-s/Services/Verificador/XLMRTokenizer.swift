//
//  XLMRTokenizer.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Hub
import Tokenizers

/// Tokenização XLM-R do modelo de embeddings (DT-06).
///
/// Envolve o `swift-transformers` por dois motivos que os Services não deveriam conhecer:
///
/// 1. **Carregamento offline.** `AutoTokenizer.from(modelFolder:)` é `async` e passa pelo
///    `HubApi`; aqui os arquivos vêm do bundle e viram `Config` direto, sem rede.
/// O NLI deixou de compartilhar esta implementação: o BERTimbau selecionado no Spike 9 usa
/// WordPiece, tokens especiais BERT e `token_type_ids` (ver `BERTTokenizer`).
struct XLMRTokenizer {

    /// Limite do modelo de embeddings, convertido com `RangeDim(1...512)`.
    static let maxSequenceLength = 512

    private let tokenizer: any Tokenizer

    /// Ids dos tokens especiais do XLM-R, lidos do tokenizador — não constantes mágicas.
    private let bosTokenId: Int
    private let eosTokenId: Int

    // MARK: - Carregamento

    /// Carrega um tokenizador a partir dos assets no bundle.
    ///
    /// - Parameters:
    ///   - tokenizerResource: nome do `tokenizer.json` exportado (sem extensão).
    ///   - configResource: nome do `tokenizer_config.json` exportado (sem extensão).
    ///   - bundle: injetável para que os testes leiam os assets do bundle de teste.
    /// - Throws: `VerificationError.modelLoadFailed` (RF-10.3) — asset ausente ou ilegível
    ///   bloqueia a funcionalidade com mensagem própria, sem derrubar o app.
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
            )
        else {
            throw VerificationError.modelLoadFailed
        }

        guard
            let bos = tokenizer.convertTokenToId("<s>"),
            let eos = tokenizer.convertTokenToId("</s>")
        else {
            throw VerificationError.modelLoadFailed
        }

        self.tokenizer = tokenizer
        self.bosTokenId = bos
        self.eosTokenId = eos
    }

    /// Tokenizador do modelo de embeddings.
    static func embeddings(bundle: Bundle = .main) throws -> XLMRTokenizer {
        try XLMRTokenizer(
            tokenizerResource: "EmbeddingsTokenizer",
            configResource: "EmbeddingsTokenizerConfig",
            bundle: bundle
        )
    }

    // MARK: - Codificação

    /// Codifica um texto isolado: `<s> X </s>`. É o formato do modelo de embeddings.
    ///
    /// Trunca em `maxSequenceLength` preservando os tokens especiais nas pontas — um texto
    /// cortado sem o `</s>` final muda o que o modelo vê.
    func encode(_ text: String) -> [Int] {
        let body = tokenizer.encode(text: text, addSpecialTokens: false)
        let budget = Self.maxSequenceLength - 2 // <s> e </s>
        return [bosTokenId] + body.prefix(max(0, budget)) + [eosTokenId]
    }

}
