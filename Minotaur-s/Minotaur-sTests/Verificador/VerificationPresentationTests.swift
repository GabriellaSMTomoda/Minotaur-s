//
//  VerificationPresentationTests.swift
//  Minotaur-sTests
//
//  Created by Claude Code on 26/07/26.
//

import Foundation
import Testing
@testable import Minotaur_s

/// CA-03, CA-10 e CA-11 no nível em que são regra, não layout: validação da entrada, corte e
/// atribuição do trecho citado, e existência do aviso de limitação.
///
/// **O que estes testes não cobrem:** posição na tela. Que o aviso da CA-11 fique fora da
/// `ScrollView` é uma decisão de `VerificationResultView`, verificável só com UI test rodando
/// a tela real — e a tela real depende do pipeline (rede + 216 MB de modelo). O projeto não
/// tem alvo de UI test com injeção de dependência montado para isso, então a garantia aqui é
/// a de que o texto existe e é o certo; a posição está comentada no arquivo da View.
struct VerificationPresentationTests {

    // MARK: - CA-03: validação de entrada (RF-01.2)

    @Test("CA-03: menos de 15 caracteres desabilita o botão e explica o mínimo")
    func shortClaimBlocksVerification() {
        let validation = VerificationPresentation.validate(claim: "Boato no zap")  // 12

        #expect(validation == .tooShort(missing: 3))
        #expect(!validation.allowsVerification)

        // "uma mensagem indica o mínimo de caracteres exigido" — o número precisa aparecer.
        #expect(validation.message?.contains("15") == true)
    }

    @Test("CA-03: campo vazio também informa o mínimo exigido")
    func emptyClaimExplainsMinimum() {
        let validation = VerificationPresentation.validate(claim: "")

        #expect(validation == .empty)
        #expect(!validation.allowsVerification)
        // Zero caractere é "menos de 15": a tela não pode ficar muda no estado inicial.
        #expect(validation.message?.contains("15") == true)
    }

    @Test("Espaços não contam para o mínimo")
    func whitespaceDoesNotCountTowardsMinimum() {
        // 12 caracteres úteis, empurrados a 25 por espaços e quebras de linha.
        let padded = "\n\n   Boato no zap        \n"

        #expect(VerificationPresentation.validate(claim: padded) == .tooShort(missing: 3))
    }

    @Test("Exatamente 15 e exatamente 1.000 caracteres são válidos")
    func boundariesAreInclusive() {
        let minimum = String(repeating: "a", count: 15)
        let maximum = String(repeating: "a", count: 1_000)

        #expect(VerificationPresentation.validate(claim: minimum) == .valid)
        #expect(VerificationPresentation.validate(claim: maximum) == .valid)
        #expect(VerificationPresentation.validate(claim: minimum).allowsVerification)
        #expect(VerificationPresentation.validate(claim: maximum).allowsVerification)
    }

    @Test("Acima de 1.000 caracteres desabilita o botão e diz o excesso")
    func longClaimBlocksVerification() {
        let validation = VerificationPresentation.validate(claim: String(repeating: "a", count: 1_042))

        #expect(validation == .tooLong(excess: 42))
        #expect(!validation.allowsVerification)
        #expect(validation.message?.contains("1000") == true || validation.message?.contains("1.000") == true)
    }

    @Test("Mensagem só some quando a entrada é válida")
    func validClaimHasNoMessage() {
        #expect(VerificationPresentation.validate(claim: "O desemprego caiu para 6,2%.").message == nil)
    }

    // MARK: - CA-10: atribuição de conteúdo (RF-09.4 / NF-12)

    @Test("CA-10: trecho exibido nunca passa de 300 caracteres")
    func excerptIsCappedAt300() {
        // Um `SourceResult` já trunca em 300; aqui o texto entra cru para provar que a camada
        // de exibição também corta — a CA-10 é sobre o que aparece na tela.
        let long = String(repeating: "notícia ", count: 200)  // 1.600 caracteres

        let displayed = VerificationPresentation.excerptText(long)

        #expect(displayed.count <= VerificationPresentation.maximumExcerptLength)
        #expect(displayed.hasSuffix("…"))
    }

    @Test("CA-10: trecho curto é exibido inteiro, sem reticências")
    func shortExcerptIsUntouched() {
        let excerpt = "A taxa de desocupação ficou em 6,2%, segundo o levantamento."

        #expect(VerificationPresentation.excerptText(excerpt) == excerpt)
    }

    @Test("CA-10: o trecho que vem do pipeline já chega dentro do limite")
    func sourceResultTruncatesExcerpt() {
        let source = SourceResult(
            url: "https://g1.globo.com/economia/desemprego",
            domain: "g1.globo.com",
            title: "Desemprego cai a 6,2%",
            label: .entailment,
            confidence: 0.93,
            similarity: 0.81,
            excerpt: String(repeating: "a", count: 900)
        )

        #expect(source.excerpt.count == 300)
        #expect(VerificationPresentation.excerptText(source.excerpt).count <= 300)
    }

    @Test("CA-10: o trecho é atribuído ao veículo de origem")
    func excerptIsAttributedToTheOutlet() {
        let attribution = VerificationPresentation.attributionText(domain: "g1.globo.com")

        // "exibe o nome do veículo": o domínio é o identificador do veículo nesta fase
        // (RF-03.3 não exige `displayName`).
        #expect(attribution.contains("g1.globo.com"))
    }

    @Test("Rótulo e score de cada fonte têm cópia própria (RF-09.2)")
    func labelAndConfidenceAreDisplayable() {
        #expect(VerificationPresentation.title(for: .entailment) == "Sustenta")
        #expect(VerificationPresentation.title(for: .contradiction) == "Contradiz")
        #expect(VerificationPresentation.title(for: .neutral) == "Não conclui")
        #expect(VerificationPresentation.confidenceText(0.93).contains("93"))
    }

    // MARK: - CA-11: aviso de limitação (RF-09.5)

    @Test("CA-11: o aviso diz que é automatizado e que não substitui as fontes")
    func limitationWarningSaysWhatItMust() {
        let warning = VerificationPresentation.limitationWarning.lowercased()

        #expect(warning.contains("automatizada"))
        #expect(warning.contains("erros"))
        #expect(warning.contains("não substitui"))
        #expect(warning.contains("fontes"))
    }

    @Test("CA-11: o aviso é curto o bastante para caber sem rolagem")
    func limitationWarningIsShort() {
        // A CA-11 exige o aviso visível sem rolagem. A View o fixa fora da `ScrollView`, mas
        // um texto longo demais empurraria o resto da tela para fora mesmo assim.
        #expect(VerificationPresentation.limitationWarning.count <= 160)
    }

    // MARK: - RF-08.2 / DT-12: nenhum veredito afirma verdade absoluta

    @Test("Nenhum veredito usa linguagem de verdade ou mentira")
    func verdictsNeverClaimAbsoluteTruth() {
        let forbidden = ["verdadeir", "falso", "falsa", "mentira", "fake"]

        for verdict in [Verdict.confirmado, .contradito, .divergente, .semInformacao, .naoEncontrado] {
            let style = VerificationPresentation.style(for: verdict)
            let copy = (style.title + " " + style.subtitle).lowercased()

            for word in forbidden {
                #expect(!copy.contains(word), "Veredito \(verdict.rawValue) usa \"\(word)\": \(copy)")
            }
            // RF-08.2: o veredito sempre referencia as fontes.
            #expect(copy.contains("fonte") || copy.contains("veículo"))
        }
    }

    // MARK: - RF-10.4 / CA-08: todo erro tem mensagem própria

    @Test("CA-08: cada erro tem mensagem distinta, nenhuma genérica")
    func everyErrorHasItsOwnMessage() {
        let errors: [VerificationError] = [
            .noConnection, .searchRequestFailed, .searchQuotaExceeded, .modelLoadFailed
        ]
        let presentations = errors.map(VerificationPresentation.presentation(for:))

        // Nenhuma mensagem repetida: erro indistinguível é o que a RF-10.4 proíbe.
        #expect(Set(presentations.map(\.title)).count == errors.count)
        #expect(Set(presentations.map(\.message)).count == errors.count)

        for presentation in presentations {
            #expect(!presentation.message.isEmpty)
            #expect(!presentation.message.lowercased().contains("algo deu errado"))
        }
    }

    @Test("CA-08: ausência de conexão é distinta de 'não encontrado' e oferece nova tentativa")
    func noConnectionIsDistinctFromNotFound() {
        let offline = VerificationPresentation.presentation(for: .noConnection)
        let notFound = VerificationPresentation.style(for: .naoEncontrado)

        #expect(offline.isRetriable)  // RF-10.1: "opção de tentar novamente"
        #expect(offline.title != notFound.title)
        #expect(offline.message != notFound.subtitle)
        #expect(offline.message.lowercased().contains("conexão"))
    }

    @Test("RF-10.2/RF-10.3: erros que repetir não resolve não oferecem nova tentativa")
    func nonRetriableErrorsDoNotOfferRetry() {
        #expect(!VerificationPresentation.presentation(for: .searchQuotaExceeded).isRetriable)
        #expect(!VerificationPresentation.presentation(for: .modelLoadFailed).isRetriable)
    }

    // MARK: - RF-01.4: progresso por etapa

    @Test("Cada etapa do pipeline tem texto próprio, na ordem da RF-01.4")
    func everyStageHasItsOwnTitle() {
        let titles = [VerificationStage.searching, .readingSources, .analyzing]
            .map(VerificationPresentation.progressTitle(for:))

        #expect(Set(titles).count == 3)
        #expect(titles[0].lowercased().contains("busc"))
        #expect(titles[1].lowercased().contains("lendo"))
        #expect(titles[2].lowercased().contains("analis"))
    }
}
