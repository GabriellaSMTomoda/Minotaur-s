//
//  ResponderPerguntaIntent.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 03/09/25.
//

import AppIntents

enum RespostaUsuario: String, AppEnum, CaseIterable {
    case fato = "Fato"
    case farsa = "Farsa"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Escolha Fato ou Farsa"
    
    static var caseDisplayRepresentations: [RespostaUsuario: DisplayRepresentation] = [
        .fato: "Fato",
        .farsa: "Farsa"
    ]
}

struct ResponderPerguntaIntent: AppIntent {
    static var title: LocalizedStringResource = "Responder Pergunta"
    
    @Parameter(title: "Resposta", default: .fato)
    var resposta: RespostaUsuario

    static var parameterSummary: some ParameterSummary {
        Summary("Responder que é \(\.$resposta)")
    }

    private func normalizarResposta(_ valor: String) -> String {
        let normalizado = valor
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        switch normalizado {
        case "fato", "verdade", "verdadeiro", "certo", "real", "verdadeira":
            return "fato"
        case "farsa", "falso", "mentira", "enganoso", "fake", "falsa":
            return "farsa"
        default:
            return normalizado
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Primeiro tenta carregar da sessão em memória
        let question = QuestionSession.shared.currentQuestion ?? PerguntaStorage.shared.carregarPergunta()

        guard let questionAtiva = question else {
            return .result(dialog: "Nenhuma pergunta ativa no momento. Peça uma nova.")
        }

        // Normaliza respostas
        let respostaNormalizada = normalizarResposta(resposta.rawValue)
        let binarioNormalizado = normalizarResposta(questionAtiva.binario)

        let acertou = (respostaNormalizada == binarioNormalizado)
        
        // =========== DEBBUGUER ===============
        
        print("bahhhhhh")
        print(questionAtiva)
        
        // ==========================
        
        let dialogo: IntentDialog
        if acertou {
            dialogo = IntentDialog("""
            ✅ Você acertou! Era mesmo \(binarioNormalizado.capitalized).
            Motivo: \(questionAtiva.motivo)
            """)
        } else {
            dialogo = IntentDialog("""
            ❌ Não foi dessa vez. A resposta correta era \(binarioNormalizado.capitalized).
            Motivo: \(questionAtiva.motivo)
            """)
        }

        return .result(dialog: dialogo, view: PerguntaDoDiaView(question: questionAtiva))
        
    }
}
