//
//  TokenizerParityTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// **Gate crítico da fase.** Compara os ids produzidos em Swift com os do Hugging Face.
///
/// Motivo de existir: até esta fase nenhuma tokenização em Swift havia sido validada. O
/// Spike 2c mediu "os logits batem com o PyTorch" sobre `input_ids` **hardcoded**, gerados em
/// Python — ou seja, provou que o modelo converte bem, não que o app alimenta o modelo certo.
/// Se o tokenizador Swift divergir do HF, os dois modelos recebem entrada errada e devolvem
/// um resultado com aparência perfeitamente normal. Nenhum outro teste pegaria isso.
///
/// A referência é `parity_fixture.json`, gerado por `spikes/07-tokenizer-parity/export_assets.py`.
struct TokenizerParityTests {

    private struct Fixture: Decodable {
        struct Single: Decodable {
            let text: String
            let inputIDs: [Int]

            enum CodingKeys: String, CodingKey {
                case text
                case inputIDs = "input_ids"
            }
        }

        struct Pair: Decodable {
            let premise: String
            let hypothesis: String
            let inputIDs: [Int]

            enum CodingKeys: String, CodingKey {
                case premise, hypothesis
                case inputIDs = "input_ids"
            }
        }

        let single: [Single]
        let pairs: [Pair]
    }

    private func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "parity_fixture", withExtension: "json"),
            "parity_fixture.json não está no bundle de teste"
        )
        return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
    }

    // MARK: - Texto isolado (modelo de embeddings)

    @Test("Ids de texto isolado batem com o Hugging Face")
    func singleTextParity() throws {
        let fixture = try loadFixture()
        let tokenizer = try XLMRTokenizer.embeddings()

        #expect(!fixture.single.isEmpty)
        for sample in fixture.single {
            let produced = tokenizer.encode(sample.text)
            #expect(produced == sample.inputIDs,
                    Comment(rawValue: "Divergência em: \(sample.text)\n"
                        + "esperado: \(sample.inputIDs)\nobtido:   \(produced)"))
        }
    }

    // MARK: - Par premissa/hipótese (modelo NLI)

    @Test("Ids do par premissa/hipótese batem com o Hugging Face")
    func pairParity() throws {
        let fixture = try loadFixture()
        let tokenizer = try XLMRTokenizer.nli()

        #expect(!fixture.pairs.isEmpty)
        for sample in fixture.pairs {
            // O swift-transformers 1.3.3 não tem encode(text:textPair:) — o par é montado à
            // mão como `<s> A </s></s> B </s>`. Este é o teste que prova que a montagem
            // manual reproduz o HF exatamente.
            let produced = tokenizer.encodePair(
                premise: sample.premise,
                hypothesis: sample.hypothesis
            )
            #expect(produced == sample.inputIDs,
                    Comment(rawValue: "Divergência no par:\n\(sample.premise)\n"
                        + "\(sample.hypothesis)\nesperado: \(sample.inputIDs)\n"
                        + "obtido:   \(produced)"))
        }
    }

    // MARK: - Estrutura

    @Test("Texto isolado é <s> X </s>")
    func singleHasBosAndEos() throws {
        let tokenizer = try XLMRTokenizer.embeddings()
        let ids = tokenizer.encode("teste")

        #expect(ids.first == 0)  // <s>
        #expect(ids.last == 2)   // </s>
    }

    @Test("Par tem o separador duplo do XLM-R")
    func pairHasDoubleSeparator() throws {
        let tokenizer = try XLMRTokenizer.nli()
        let ids = tokenizer.encodePair(premise: "A premissa.", hypothesis: "A hipótese.")

        #expect(ids.first == 0)
        #expect(ids.last == 2)
        // `</s></s>` no meio é o separador de par do XLM-R, não um erro de duplicação.
        let doubleSeparator = ids.indices.dropLast().contains { ids[$0] == 2 && ids[$0 + 1] == 2 }
        #expect(doubleSeparator)
    }

    @Test("Truncagem respeita o limite de 512 tokens (RF-06.2)")
    func respectsMaxLength() throws {
        let tokenizer = try XLMRTokenizer.nli()
        let huge = String(repeating: "palavra qualquer para encher o contexto. ", count: 500)

        let single = try XLMRTokenizer.embeddings().encode(huge)
        #expect(single.count <= XLMRTokenizer.maxSequenceLength)

        let pair = tokenizer.encodePair(premise: huge, hypothesis: "A afirmação do usuário.")
        #expect(pair.count <= XLMRTokenizer.maxSequenceLength)
    }

    @Test("Quem encolhe no par é a premissa, nunca a hipótese")
    func truncationPreservesHypothesis() throws {
        let tokenizer = try XLMRTokenizer.nli()
        let hypothesis = "O desemprego caiu para o menor nível já registrado no país inteiro."
        let huge = String(repeating: "texto de enchimento do artigo. ", count: 500)

        let pair = tokenizer.encodePair(premise: huge, hypothesis: hypothesis)
        let hypothesisIDs = tokenizer.encode(hypothesis).dropFirst().dropLast() // sem <s>/</s>

        // Cortar a hipótese mudaria a pergunta feita ao modelo; ela tem de sobreviver inteira.
        #expect(pair.count <= XLMRTokenizer.maxSequenceLength)
        #expect(pair.suffix(hypothesisIDs.count + 1).dropLast() == Array(hypothesisIDs)[...])
    }

    // MARK: - Rótulos do NLI

    @Test("Ordem das classes vem do asset, não é presumida")
    func labelOrderFromAsset() throws {
        let labels = try NLIService.loadLabels()

        // Deste checkpoint específico. Assumir esta ordem no código inverteria o veredito em
        // silêncio se o modelo fosse trocado — por isso ela é lida, não escrita.
        #expect(labels == [.entailment, .neutral, .contradiction])
    }
}

/// Âncora para localizar o bundle de teste.
private final class BundleToken {}
