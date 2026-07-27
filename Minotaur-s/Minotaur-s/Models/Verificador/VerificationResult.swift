//
//  VerificationResult.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Veredito agregado de uma verificação, conforme RF-08.1.
enum Verdict: String, Codable {
    case confirmado = "CONFIRMADO"
    case contradito = "CONTRADITO"
    case divergente = "DIVERGENTE"
    case semInformacao = "SEM_INFORMACAO"
    case naoEncontrado = "NAO_ENCONTRADO"
}

/// Rótulo de inferência de linguagem natural (NLI) por fonte, conforme RF-07.2.
enum NLILabel: String, Codable {
    case entailment
    case contradiction
    case neutral
}

/// Uma fonte individual analisada durante a verificação (spec, seção 3.5).
struct SourceResult: Codable {
    let url: String
    let domain: String
    let title: String
    let label: NLILabel
    let confidence: Double
    let similarity: Double
    let excerpt: String

    /// `excerpt` é truncado para no máximo 300 caracteres (RF-09.4 / CA-10).
    init(url: String, domain: String, title: String, label: NLILabel,
         confidence: Double, similarity: Double, excerpt: String) {
        self.url = url
        self.domain = domain
        self.title = title
        self.label = label
        self.confidence = confidence
        self.similarity = similarity
        self.excerpt = String(excerpt.prefix(300))
    }
}

/// Resultado completo de uma verificação. Existe apenas em memória durante a
/// sessão de uso — não é persistido em nenhuma forma (ver spec, seção 5).
struct VerificationResult: Codable {
    let id: UUID
    let claim: String
    let createdAt: Date
    let verdict: Verdict
    /// Domínios consultados nesta verificação (RF-09.6 / DT-32). Presente mesmo quando
    /// `sources` está vazio — é justamente em `NAO_ENCONTRADO` que a CA-02 exige informar
    /// o que foi consultado.
    let consultedDomains: [String]
    let sources: [SourceResult]
}
