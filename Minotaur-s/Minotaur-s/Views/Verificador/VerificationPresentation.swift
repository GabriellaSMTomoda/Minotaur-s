//
//  VerificationPresentation.swift
//  Minotaur-s
//
//  Created by Claude Code on 26/07/26.
//

import SwiftUI

/// Tradução do resultado do pipeline para o que a tela mostra: cópia em português, ícone e
/// cor (RF-09.1), validação da entrada (RF-01.2) e mensagem de erro por categoria (RF-10.4).
///
/// É um `enum` sem casos, de funções puras: nada aqui toca rede, modelo ou estado. Existe
/// separado das `View`s porque é o que a CA-03, a CA-10 e a CA-11 realmente exigem verificar —
/// e teste de string não deveria precisar montar uma hierarquia de SwiftUI.
///
/// Os `enum`s do domínio (`Verdict`, `NLILabel`, `VerificationError`) continuam sem cópia de
/// UI: a camada de dados não decide como o veredito é escrito.
enum VerificationPresentation {

    // MARK: - Entrada (RF-01.2 / CA-03)

    /// Limites da afirmação, em caracteres (RF-01.2).
    static let minimumClaimLength = 15
    static let maximumClaimLength = 1_000

    /// Resultado da validação do campo de texto.
    ///
    /// O caso `.valid` não carrega mensagem porque a tela não deve elogiar entrada correta —
    /// só explicar por que o botão está desabilitado.
    enum ClaimValidation: Equatable {
        case empty
        case tooShort(missing: Int)
        case tooLong(excess: Int)
        case valid

        /// Se o botão "Verificar notícia" pode ser tocado (RF-01.2 / CA-03).
        var allowsVerification: Bool { self == .valid }

        /// Motivo da desabilitação, exibido junto ao campo. `nil` quando não há o que dizer.
        ///
        /// Campo vazio também tem mensagem: a CA-03 pede que o mínimo de caracteres esteja
        /// indicado na tela quando o texto tem menos de 15 caracteres — e 0 é menos de 15.
        var message: String? {
            switch self {
            case .empty:
                return "Digite ou cole a notícia que você quer verificar (mínimo de \(minimumClaimLength) caracteres)."
            case .tooShort(let missing):
                return "Faltam \(missing) caractere\(missing == 1 ? "" : "s") para o mínimo de \(minimumClaimLength)."
            case .tooLong(let excess):
                return "Texto \(excess) caractere\(excess == 1 ? "" : "s") acima do máximo de \(maximumClaimLength). Remova parte do conteúdo."
            case .valid:
                return nil
            }
        }
    }

    /// Valida a afirmação digitada (RF-01.2).
    ///
    /// A contagem é feita sobre o texto **sem espaços nas pontas**: colar um texto com quebras
    /// de linha sobrando não deve fazer o app achar que atingiu o mínimo. É a mesma string que
    /// vai para o pipeline, então o que a tela conta é o que a busca recebe.
    static func validate(claim: String) -> ClaimValidation {
        let trimmed = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = trimmed.count

        if length == 0 { return .empty }
        if length < minimumClaimLength { return .tooShort(missing: minimumClaimLength - length) }
        if length > maximumClaimLength { return .tooLong(excess: length - maximumClaimLength) }
        return .valid
    }

    // MARK: - Progresso (RF-01.4)

    /// Texto do indicador de progresso, na ordem buscando → lendo fontes → analisando.
    static func progressTitle(for stage: VerificationStage) -> String {
        switch stage {
        case .searching: return "Buscando em veículos confiáveis…"
        case .readingSources: return "Lendo as fontes encontradas…"
        case .analyzing: return "Analisando o que as fontes dizem…"
        }
    }

    // MARK: - Veredito (RF-09.1 / RF-08.2)

    /// Cópia do veredito: título, explicação, ícone e cor (RF-09.1).
    struct VerdictStyle {
        let title: String
        let subtitle: String
        let systemImage: String
        let tint: Color
    }

    /// **Nenhum título afirma verdade ou mentira** (RF-08.2 / DT-12): todos falam do que as
    /// fontes dizem, não do mundo. Isso não é preferência de redação — é o que separa esta
    /// feature de um "detector de fake news", e o que a análise de risco da seção 7.2 cobra.
    static func style(for verdict: Verdict) -> VerdictStyle {
        switch verdict {
        case .confirmado:
            return VerdictStyle(
                title: "Confirmado pelas fontes",
                subtitle: "Os veículos analisados publicaram informação que sustenta essa afirmação.",
                systemImage: "checkmark.seal.fill",
                tint: .green
            )
        case .contradito:
            return VerdictStyle(
                title: "Contradito pelas fontes",
                subtitle: "Os veículos analisados publicaram informação que contradiz essa afirmação.",
                systemImage: "xmark.seal.fill",
                tint: .red
            )
        case .divergente:
            return VerdictStyle(
                title: "Fontes divergentes",
                subtitle: "Os veículos analisados não concordam entre si sobre essa afirmação.",
                systemImage: "arrow.triangle.branch",
                tint: .orange
            )
        case .semInformacao:
            return VerdictStyle(
                title: "Sem informação suficiente",
                subtitle: "As fontes encontradas não permitem concluir nada sobre essa afirmação.",
                systemImage: "questionmark.circle.fill",
                tint: .gray
            )
        case .naoEncontrado:
            return VerdictStyle(
                title: "Não encontrado",
                // "não significa que seja falsa" seria a redação natural aqui, e é a que a
                // versão antiga usava — mas nomeia o veredito que a RF-08.2 proíbe. A ausência
                // de cobertura precisa ser dita sem afirmar nada sobre o conteúdo.
                subtitle: "Nenhum artigo dos veículos consultados tratava dessa afirmação. Não encontrar cobertura não é uma conclusão sobre o conteúdo.",
                systemImage: "magnifyingglass",
                tint: .gray
            )
        }
    }

    /// Cópia do rótulo individual de uma fonte (RF-09.2).
    static func title(for label: NLILabel) -> String {
        switch label {
        case .entailment: return "Sustenta"
        case .contradiction: return "Contradiz"
        case .neutral: return "Não conclui"
        }
    }

    static func tint(for label: NLILabel) -> Color {
        switch label {
        case .entailment: return .green
        case .contradiction: return .red
        case .neutral: return .gray
        }
    }

    /// Score de confiança como porcentagem inteira (RF-09.2).
    static func confidenceText(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))% de confiança"
    }

    // MARK: - Atribuição (RF-09.4 / CA-10 / NF-12)

    /// Trecho citado, entre aspas e com o corte de 300 caracteres garantido na exibição.
    ///
    /// O `SourceResult` já trunca em 300 (RF-09.4), mas a tela não depende disso: a CA-10 é
    /// sobre o que aparece na tela, e um trecho vindo de outra origem no futuro não pode
    /// escapar do limite por descuido. Truncar duas vezes é barato; republicar artigo inteiro
    /// é risco de conformidade (NF-12).
    static func excerptText(_ excerpt: String) -> String {
        let trimmed = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumExcerptLength else { return trimmed }
        return String(trimmed.prefix(maximumExcerptLength - 1)) + "…"
    }

    /// Máximo de caracteres do trecho citado (RF-09.4 / CA-10).
    static let maximumExcerptLength = 300

    /// Atribuição do trecho ao veículo (CA-10 / NF-12 / NF-14).
    static func attributionText(domain: String) -> String {
        "Trecho de \(domain)"
    }

    // MARK: - Aviso de limitação (RF-09.5 / CA-11)

    /// Aviso permanente exibido na tela de resultado.
    ///
    /// A CA-11 exige que esteja **visível sem rolagem**, então ele é renderizado fora da
    /// `ScrollView` da `VerificationResultView` — mudá-lo de lugar quebra o critério, não só o
    /// layout. Precisa dizer as três coisas da RF-09.5: que é automatizado, que pode errar e
    /// que não substitui ler as fontes.
    static let limitationWarning = """
    Análise automatizada: pode conter erros e não substitui a leitura das fontes originais.
    """

    /// Aviso de que o app não tem vínculo com os veículos (NF-14).
    static let independenceNotice = """
    Este app não tem vínculo com os veículos consultados.
    """

    // MARK: - Erros (RF-10 / CA-08)

    /// Mensagem exibível de um erro do pipeline.
    ///
    /// Nunca há caso genérico (RF-10.4): o parâmetro é o `enum` fechado da `VerificationError`,
    /// então o compilador — não a revisão de código — garante que um erro novo vem com
    /// mensagem própria.
    struct ErrorPresentation {
        let title: String
        let message: String
        let systemImage: String
        /// Se cabe oferecer "Tentar novamente" (RF-10.1). Falso quando repetir não muda nada.
        let isRetriable: Bool
    }

    static func presentation(for error: VerificationError) -> ErrorPresentation {
        switch error {
        case .noConnection:
            return ErrorPresentation(
                title: "Sem conexão",
                message: "Não foi possível acessar a internet. Verifique sua conexão e tente novamente.",
                systemImage: "wifi.slash",
                isRetriable: true
            )
        case .searchRequestFailed:
            return ErrorPresentation(
                title: "Falha na busca",
                message: "A busca nos veículos confiáveis não pôde ser concluída. Tente novamente em instantes.",
                systemImage: "exclamationmark.magnifyingglass",
                isRetriable: true
            )
        case .searchQuotaExceeded:
            return ErrorPresentation(
                title: "Limite de verificações atingido",
                message: "O limite diário de verificações foi atingido. Tente novamente amanhã.",
                systemImage: "hourglass",
                // Repetir agora só consome o que já acabou.
                isRetriable: false
            )
        case .modelLoadFailed:
            return ErrorPresentation(
                title: "Análise indisponível",
                message: "O modelo de análise não pôde ser carregado neste dispositivo. A verificação está indisponível.",
                systemImage: "cpu",
                // RF-10.3: a funcionalidade fica bloqueada; um botão de repetir prometeria
                // algo que a mesma sessão não vai entregar.
                isRetriable: false
            )
        }
    }
}
