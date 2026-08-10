//
//  TextChunker.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import NaturalLanguage

/// Divide o texto extraído de um artigo nos chunks que alimentam o pipeline de
/// embeddings (RF-06.1) e, em seguida, o de NLI (RF-07.1).
///
/// A divisão é por parágrafo, com sobreposição de uma frase entre chunks adjacentes
/// (RF-06.1 / DT-07): a última frase de um chunk reabre o chunk seguinte, para que o
/// contexto não se perca exatamente na fronteira. Chunk que exceda o limite de tokens do
/// modelo NLI é subdividido (RF-06.2).
struct TextChunker {

    /// Orçamento de tokens por chunk. Padrão 512, o limite do modelo NLI (RF-06.2).
    ///
    /// O NLI codifica o par como `[CLS] premissa [SEP] hipótese [SEP]`, então o orçamento
    /// real do chunk é 512 menos a afirmação do usuário (até 1.000 caracteres pela RF-01.2)
    /// e os tokens especiais. A RF-06.2 fixa 512 para o chunk, que é o padrão aqui; o
    /// parâmetro existe para que a camada de NLI construa um chunker com orçamento reduzido
    /// quando souber o tamanho da hipótese.
    let maxTokens: Int

    /// Conta os tokens de um trecho.
    ///
    /// O padrão é uma estimativa conservadora, não o tokenizador real: `swift-transformers`
    /// (§3.1 da spec) só entra na fase dos modelos Core ML. Injetar a contagem verdadeira
    /// depois não exige mudar nada aqui.
    let estimateTokens: (String) -> Int

    init(
        maxTokens: Int = 512,
        estimateTokens: @escaping (String) -> Int = TextChunker.conservativeTokenEstimate
    ) {
        self.maxTokens = max(1, maxTokens)
        self.estimateTokens = estimateTokens
    }

    /// Estimativa conservadora de tokens, para uso antes de o tokenizador real existir.
    ///
    /// Toma o maior entre `caracteres / 3` e o número de palavras. O divisor 3 fica abaixo
    /// da razão típica do SentencePiece do XLM-R em português (~3,5–4 caracteres por token),
    /// e o piso por palavra reflete que um tokenizador de subpalavras nunca produz menos de
    /// um token por palavra. Errar para mais mantém os chunks dentro do limite real.
    static func conservativeTokenEstimate(_ text: String) -> Int {
        let byCharacters = Int((Double(text.count) / 3.0).rounded(.up))
        let byWords = text.split(whereSeparator: { $0.isWhitespace }).count
        return max(byCharacters, byWords)
    }

    // MARK: - Chunking

    /// Divide o texto do artigo em chunks prontos para embedding (RF-06.1/RF-06.2).
    /// A ordem do array preserva a ordem do artigo.
    func chunks(from text: String) -> [String] {
        var chunks: [String] = []
        /// Última frase do chunk anterior, que abre o próximo (RF-06.1).
        var overlap: String?

        for paragraph in Self.paragraphs(in: text) {
            let body: String
            if let overlap, !overlap.isEmpty {
                body = overlap + " " + paragraph
            } else {
                body = paragraph
            }

            let produced = subdivide(body)
            guard !produced.isEmpty else { continue }

            chunks.append(contentsOf: produced)
            overlap = produced.last.flatMap { Self.sentences(in: $0).last }
        }

        return chunks
    }

    // MARK: - Subdivisão por orçamento de tokens

    /// Quebra um chunk que excede `maxTokens`, preservando a sobreposição de uma frase
    /// entre os pedaços gerados (RF-06.2, coerente com DT-07).
    private func subdivide(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        guard estimateTokens(text) > maxTokens else { return [text] }

        let sentences = Self.sentences(in: text)
        guard sentences.count > 1 else { return splitByWords(text) }

        var pieces: [String] = []
        var current: [String] = []

        for sentence in sentences {
            // Frase que sozinha não cabe no orçamento vira várias unidades menores.
            let units = estimateTokens(sentence) <= maxTokens ? [sentence] : splitByWords(sentence)

            for unit in units {
                if current.isEmpty {
                    current = [unit]
                    continue
                }

                let candidate = (current + [unit]).joined(separator: " ")
                if estimateTokens(candidate) <= maxTokens {
                    current.append(unit)
                    continue
                }

                pieces.append(current.joined(separator: " "))

                guard let previous = current.last else {
                    current = [unit]
                    continue
                }
                let withOverlap = previous + " " + unit
                current = estimateTokens(withOverlap) <= maxTokens ? [previous, unit] : [unit]
            }
        }

        if !current.isEmpty {
            pieces.append(current.joined(separator: " "))
        }
        return pieces
    }

    /// Último recurso quando uma frase isolada estoura o orçamento: agrupa palavras até
    /// o limite. Nenhum pedaço devolvido excede `maxTokens`.
    private func splitByWords(_ text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }

        var pieces: [String] = []
        var current: [String] = []

        for word in words {
            let units = estimateTokens(word) <= maxTokens ? [word] : splitOversizedWord(word)

            for unit in units {
                if current.isEmpty {
                    current = [unit]
                    continue
                }
                let candidate = (current + [unit]).joined(separator: " ")
                if estimateTokens(candidate) <= maxTokens {
                    current.append(unit)
                } else {
                    pieces.append(current.joined(separator: " "))
                    current = [unit]
                }
            }
        }

        if !current.isEmpty {
            pieces.append(current.joined(separator: " "))
        }
        return pieces
    }

    /// Caso patológico: uma única "palavra" maior que o orçamento inteiro (URL gigante,
    /// texto sem espaços). Corta por comprimento até caber.
    private func splitOversizedWord(_ word: String) -> [String] {
        var pieces: [String] = []
        var remaining = Substring(word)

        while !remaining.isEmpty {
            var length = remaining.count
            while length > 1 && estimateTokens(String(remaining.prefix(length))) > maxTokens {
                length = max(1, length / 2)
            }
            pieces.append(String(remaining.prefix(length)))
            remaining = remaining.dropFirst(length)
        }
        return pieces
    }

    // MARK: - Segmentação

    /// Parágrafos do texto extraído. A extração de RF-05.2 entrega um parágrafo por linha,
    /// então qualquer sequência de quebras de linha separa parágrafos.
    ///
    /// Linhas que são estrutura de página (navegação, título de Web Story) saem aqui, antes da
    /// montagem — DT-33. É antes e não depois por causa da sobreposição de uma frase: uma linha
    /// de navegação sobrevivente seria arrastada como prefixo do chunk seguinte e levaria junto
    /// o parágrafo legítimo logo abaixo dela. Ver `ChunkQualityFilter.isStructuralBoilerplate`.
    private static func paragraphs(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !ChunkQualityFilter.isStructuralBoilerplate($0) }
    }

    /// Segmenta em frases com `NLTokenizer`, on-device e sem dependência externa.
    /// O idioma é fixado em português — a feature não suporta outros (§5 da spec).
    private static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.portuguese)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }
}
