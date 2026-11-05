//
//  VerificationResult.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Veredito agregado de uma verificação, conforme RF-08.1.
enum Verdict: String, Codable, CaseIterable {
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
    var stance: SourceStance
    var provenance: TextProvenance
    var isPartial: Bool
    var publishedAt: Date?
    var temporalAlignment: TemporalAlignment
    var originGroup: String
    var duplicateOf: String?
    var evidence: [EvidencePassage]
    var reason: String?

    /// `excerpt` é truncado para no máximo 300 caracteres (RF-09.4 / CA-10).
    init(url: String, domain: String, title: String, label: NLILabel,
         confidence: Double, similarity: Double, excerpt: String,
         stance: SourceStance? = nil, provenance: TextProvenance = .articleBody,
         isPartial: Bool = false, publishedAt: Date? = nil,
         temporalAlignment: TemporalAlignment = .compatible, originGroup: String? = nil,
         duplicateOf: String? = nil, evidence: [EvidencePassage] = [], reason: String? = nil) {
        self.url = url
        self.domain = domain
        self.title = title
        self.label = label
        self.confidence = confidence
        self.similarity = similarity
        self.excerpt = String(excerpt.prefix(300))
        self.stance = stance ?? (label == .entailment ? .supports : label == .contradiction ? .refutes : .insufficient)
        self.provenance = provenance; self.isPartial = isPartial; self.publishedAt = publishedAt
        self.temporalAlignment = temporalAlignment
        self.originGroup = originGroup ?? domain
        self.duplicateOf = duplicateOf; self.evidence = evidence; self.reason = reason
    }

    var isEligible: Bool {
        !isPartial && provenance != .searchSnippet && temporalAlignment == .compatible && duplicateOf == nil
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
    var context: ClaimContext? = nil
    var diagnostics = VerificationDiagnostics()
}
