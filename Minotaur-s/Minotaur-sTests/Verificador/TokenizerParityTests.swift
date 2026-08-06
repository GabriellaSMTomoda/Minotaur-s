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
/// A referência de embeddings nasceu no Spike 7; os pares NLI são regenerados pelo
/// `spikes/09-nli-base-search/export_app_assets.py` a partir do checkpoint selecionado.
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
            let attentionMask: [Int]
            let tokenTypeIDs: [Int]

            enum CodingKeys: String, CodingKey {
                case premise, hypothesis
                case inputIDs = "input_ids"
                case attentionMask = "attention_mask"
                case tokenTypeIDs = "token_type_ids"
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

    @Test("Três entradas do par BERT batem com o Hugging Face")
    func pairParity() throws {
        let fixture = try loadFixture()
        let tokenizer = try BERTTokenizer.nli()

        #expect(!fixture.pairs.isEmpty)
        for sample in fixture.pairs {
            let produced = tokenizer.encodePair(
                premise: sample.premise,
                hypothesis: sample.hypothesis
            )
            #expect(produced.inputIDs == sample.inputIDs,
                    Comment(rawValue: "Divergência no par:\n\(sample.premise)\n"
                        + "\(sample.hypothesis)\nesperado: \(sample.inputIDs)\n"
                        + "obtido:   \(produced.inputIDs)"))
            #expect(produced.attentionMask == sample.attentionMask)
            #expect(produced.tokenTypeIDs == sample.tokenTypeIDs)
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

    @Test("Par tem estrutura e segmentos do BERT")
    func pairHasBERTStructure() throws {
        let tokenizer = try BERTTokenizer.nli()
        let pair = tokenizer.encodePair(premise: "A premissa.", hypothesis: "A hipótese.")

        #expect(pair.inputIDs.first == 101) // [CLS]
        #expect(pair.inputIDs.last == 102)  // [SEP]
        #expect(pair.inputIDs.filter { $0 == 102 }.count == 2)
        #expect(pair.inputIDs.count == pair.attentionMask.count)
        #expect(pair.inputIDs.count == pair.tokenTypeIDs.count)
        #expect(pair.attentionMask.allSatisfy { $0 == 1 })
        let firstSegmentOne = try #require(pair.tokenTypeIDs.firstIndex(of: 1))
        #expect(pair.tokenTypeIDs[..<firstSegmentOne].allSatisfy { $0 == 0 })
        #expect(pair.tokenTypeIDs[firstSegmentOne...].allSatisfy { $0 == 1 })
        #expect(pair.inputIDs[firstSegmentOne - 1] == 102)
    }

    @Test("Truncagem respeita o limite de 512 tokens (RF-06.2)")
    func respectsMaxLength() throws {
        let tokenizer = try BERTTokenizer.nli()
        let huge = String(repeating: "palavra qualquer para encher o contexto. ", count: 500)

        let single = try XLMRTokenizer.embeddings().encode(huge)
        #expect(single.count <= XLMRTokenizer.maxSequenceLength)

        let pair = tokenizer.encodePair(premise: huge, hypothesis: "A afirmação do usuário.")
        #expect(pair.inputIDs.count <= BERTTokenizer.maxSequenceLength)
    }

    @Test("Quem encolhe no par é a premissa, nunca a hipótese")
    func truncationPreservesHypothesis() throws {
        let tokenizer = try BERTTokenizer.nli()
        let hypothesis = "O desemprego caiu para o menor nível já registrado no país inteiro."
        let huge = String(repeating: "texto de enchimento do artigo. ", count: 500)

        let pair = tokenizer.encodePair(premise: huge, hypothesis: hypothesis)
        let hypothesisOnly = tokenizer.encodePair(premise: "", hypothesis: hypothesis)
        let hypothesisSuffix = hypothesisOnly.inputIDs.dropFirst(2) // sem [CLS][SEP]

        // Cortar a hipótese mudaria a pergunta feita ao modelo; ela tem de sobreviver inteira.
        #expect(pair.inputIDs.count <= BERTTokenizer.maxSequenceLength)
        #expect(pair.inputIDs.suffix(hypothesisSuffix.count) == Array(hypothesisSuffix)[...])
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
