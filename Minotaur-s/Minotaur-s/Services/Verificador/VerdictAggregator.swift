//
//  VerdictAggregator.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Agrega os rótulos por fonte no veredito final da verificação (RF-08).
///
/// A regra é de contagem simples, sem ponderação por score: sejam `E` o número de fontes com
/// rótulo `entailment` e `C` o de `contradiction` — **neutro não vota** (RF-08.3 / DT-26).
/// Os rótulos que chegam aqui já passaram pelo rebaixamento de confiança da RF-07.4, então
/// um `entailment` presente é um `entailment` acima do limiar.
///
/// **Sem piso mínimo de fontes válidas**: 1 fonte já basta para um veredito diferente de
/// `naoEncontrado`. É decisão de produto explícita da DT-26, não omissão.
enum VerdictAggregator {

    /// Veredito agregado a partir das fontes efetivamente analisadas.
    ///
    /// - Parameter sources: fontes que sobreviveram a busca, extração e NLI. Fonte descartada
    ///   por paywall, timeout ou allowlist (RF-05.3/RF-05.4/RF-03.5) **não** entra na lista —
    ///   por isso lista vazia significa "nenhuma fonte válida analisada", que é exatamente a
    ///   condição de `naoEncontrado` na RF-08.1.
    static func verdict(for sources: [SourceResult]) -> Verdict {
        guard !sources.isEmpty else { return .naoEncontrado }

        let entailment = sources.count { $0.label == .entailment }
        let contradiction = sources.count { $0.label == .contradiction }

        if entailment == 0 && contradiction == 0 {
            // Há fonte analisada, mas nenhuma é direcional: todas neutras (RF-08.1).
            // Distinto de `naoEncontrado`, que é ausência de fonte.
            return .semInformacao
        }
        if entailment > contradiction { return .confirmado }
        if contradiction > entailment { return .contradito }
        return .divergente // E == C > 0
    }
}

private extension Array {
    /// `count(where:)` existe a partir do Swift 6; o alvo do projeto é Swift 5.
    func count(_ isIncluded: (Element) -> Bool) -> Int {
        reduce(0) { isIncluded($1) ? $0 + 1 : $0 }
    }
}
