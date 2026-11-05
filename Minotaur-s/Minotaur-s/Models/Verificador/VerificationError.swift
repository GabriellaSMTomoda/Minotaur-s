//
//  VerificationError.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import Foundation

/// Erros distinguíveis do fluxo de verificação (RF-10). Nunca há um caso
/// genérico ("algo deu errado") — cada caso deve ser rastreável a um
/// requisito específico (RF-10.4).
enum VerificationError: Error {
    /// RF-10.1 / CA-08 — dispositivo sem conexão de rede.
    case noConnection

    /// RF-04.5 — falha de rede na chamada de busca (Tavily/proxy) que não é
    /// ausência de conexão (ex.: timeout, erro 5xx, resposta malformada).
    /// Permanece distinta do veredito `.naoEncontrado` (que representa zero
    /// resultados, não uma falha).
    case searchRequestFailed

    /// RF-10.2 — quota diária da API de busca esgotada.
    case searchQuotaExceeded

    /// RF-10.3 — falha ao carregar um modelo Core ML (embeddings ou NLI).
    case modelLoadFailed
    case deadlineExceeded
    case searchBudgetExceeded
    case inferenceBudgetExceeded
    case searchRateLimited
    case readingIncomplete
    case claimNeedsSelection
    case claimNeedsRephrasing
}

extension VerificationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .searchRequestFailed:
            return "Não foi possível concluir a busca. Tente novamente em instantes."
        case .searchQuotaExceeded:
            return "A cota gratuita de buscas deste mês foi atingida. Aguarde a renovação."
        case .modelLoadFailed:
            return "Não foi possível carregar o modelo de análise neste dispositivo."
        case .deadlineExceeded: return "O tempo de análise terminou. Tente uma afirmação mais específica."
        case .searchBudgetExceeded: return "As três tentativas de busca desta verificação foram usadas."
        case .inferenceBudgetExceeded: return "O limite de trechos desta análise foi atingido."
        case .searchRateLimited: return "Muitas buscas em pouco tempo. Aguarde alguns instantes."
        case .readingIncomplete: return "Foram encontrados artigos, mas não foi possível ler evidências suficientes."
        case .claimNeedsSelection: return "Escolha uma afirmação para verificar por vez."
        case .claimNeedsRephrasing: return "Reescreva uma única afirmação completa, incluindo de quem ou do que ela trata."
        }
    }
}
