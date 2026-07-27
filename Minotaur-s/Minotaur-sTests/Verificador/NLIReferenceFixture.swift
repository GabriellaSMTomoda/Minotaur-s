//
//  NLIReferenceFixture.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// Referência PyTorch para os pares de NLI, lida de `parity_fixture.json`.
///
/// Gerada por `spikes/07-tokenizer-parity/export_assets.py` rodando o modelo original do
/// Hugging Face. É contra ela que a saída em Swift é comparada — não contra um rótulo que
/// alguém escreveu à mão.
enum NLIReferenceFixture {

    struct Sample {
        let premise: String
        let hypothesis: String
        let expectedLabel: NLILabel
        let expectedConfidence: Double
    }

    private struct Raw: Decodable {
        struct Pair: Decodable {
            let premise: String
            let hypothesis: String
            let expectedLabel: String
            let expectedConfidence: Double

            enum CodingKeys: String, CodingKey {
                case premise, hypothesis
                case expectedLabel = "expected_label"
                case expectedConfidence = "expected_confidence"
            }
        }

        let pairs: [Pair]
    }

    static func load() throws -> [Sample] {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "parity_fixture", withExtension: "json"),
            "parity_fixture.json não está no bundle de teste"
        )
        let raw = try JSONDecoder().decode(Raw.self, from: try Data(contentsOf: url))

        return try raw.pairs.map { pair in
            Sample(
                premise: pair.premise,
                hypothesis: pair.hypothesis,
                expectedLabel: try #require(NLILabel(rawValue: pair.expectedLabel)),
                expectedConfidence: pair.expectedConfidence
            )
        }
    }
}

/// Âncora para localizar o bundle de teste.
private final class BundleToken {}
