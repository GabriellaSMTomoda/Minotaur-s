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

    /// Função que converte sinônimos em "fato" ou "farsa"
    private func normalizarResposta(_ valor: String) -> String {
        let normalizado = valor
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        switch normalizado {
        // sinônimos de fato
        case "fato", "verdade", "verdadeiro", "certo", "real", "verdadeira":
            return "fato"
            
        // sinônimos de farsa
        case "farsa", "falso", "mentira", "enganoso", "fake", "falsa":
            return "farsa"
            
        default:
            return normalizado
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let question = PerguntaStorage.shared.carregarPergunta() else {
            return .result(dialog: "Nenhuma pergunta ativa no momento. Peça uma nova.")
        }
        
        // Normaliza os dois lados
        let respostaNormalizada = normalizarResposta(resposta.rawValue)
        let binarioNormalizado = normalizarResposta(question.binario)

        let acertou = (respostaNormalizada == binarioNormalizado)
        
        let dialogo: IntentDialog
        if acertou {
            dialogo = IntentDialog("""
            ✅ Você acertou! Era mesmo \(binarioNormalizado.capitalized).
            Motivo: \(question.motivo)
            """)
        } else {
            dialogo = IntentDialog("""
            ❌ Não foi dessa vez. A resposta correta era \(binarioNormalizado.capitalized).
            Motivo: \(question.motivo)
            """)
        }
        
        return .result(dialog: dialogo, view: PerguntaDoDiaView(question: question))
    }
}

