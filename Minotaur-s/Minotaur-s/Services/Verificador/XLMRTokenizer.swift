//
//  XLMRTokenizer.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Hub
import Tokenizers

/// Tokenização XLM-R para os dois modelos Core ML (DT-06).
///
/// Envolve o `swift-transformers` por dois motivos que os Services não deveriam conhecer:
///
/// 1. **Carregamento offline.** `AutoTokenizer.from(modelFolder:)` é `async` e passa pelo
///    `HubApi`; aqui os arquivos vêm do bundle e viram `Config` direto, sem rede.
/// 2. **Par premissa/hipótese.** O `swift-transformers` 1.3.3 não tem `encode(text:textPair:)`
///    — só texto único. O par do NLI (RF-07.1) é montado à mão no formato do XLM-R,
///    `<s> A </s></s> B </s>`, validado contra o Hugging Face pela fixture do Spike 7.
///
/// Os dois modelos usam o mesmo tokenizador XLM-R, mas cada um carrega o seu próprio
/// `tokenizer.json`: são checksums diferentes, e assumir que são intercambiáveis é
/// exatamente o tipo de suposição que produz ids errados sem erro visível.
struct XLMRTokenizer {

    /// Limite de tokens do modelo NLI (RF-06.2). Vale para os dois modelos: o de embeddings
    /// foi convertido com `RangeDim(1...512)`.
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

    /// Tokenizador do modelo NLI.
    static func nli(bundle: Bundle = .main) throws -> XLMRTokenizer {
        try XLMRTokenizer(
            tokenizerResource: "NLITokenizer",
            configResource: "NLITokenizerConfig",
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

    /// Codifica o par do NLI: `<s> premissa </s></s> hipótese </s>` (RF-07.1).
    ///
    /// O `</s></s>` duplo não é engano — é o separador de par do XLM-R, confirmado contra a
    /// saída do Hugging Face na fixture do Spike 7.
    ///
    /// Quando o par estoura o limite, **quem encolhe é a premissa**: a hipótese é a afirmação
    /// do usuário e cortá-la mudaria a pergunta que está sendo feita ao modelo. A premissa é
    /// um chunk que o `TextChunker` já dimensionou para caber (RF-06.2), então na prática
    /// este corte é rede de segurança, não caminho normal.
    func encodePair(premise: String, hypothesis: String) -> [Int] {
        let hypothesisTokens = tokenizer.encode(text: hypothesis, addSpecialTokens: false)
        let premiseTokens = tokenizer.encode(text: premise, addSpecialTokens: false)

        // <s> + premissa + </s> + </s> + hipótese + </s>
        let specialTokenCount = 4
        let available = Self.maxSequenceLength - specialTokenCount - hypothesisTokens.count
        let premiseBudget = max(0, available)

        return [bosTokenId]
            + premiseTokens.prefix(premiseBudget)
            + [eosTokenId, eosTokenId]
            + hypothesisTokens
            + [eosTokenId]
    }
}
