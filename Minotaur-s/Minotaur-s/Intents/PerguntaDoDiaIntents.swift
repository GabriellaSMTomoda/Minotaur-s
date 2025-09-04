//
//  PerguntaDoDiaIntent.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 01/09/25.


import AppIntents
import SwiftUI
//
//struct PerguntaDoDiaIntent: AppIntent {
//    static var title: LocalizedStringResource = "Pergunta do Dia"
//    static var description = IntentDescription(
//        "Mostra uma pergunta aleatória"
//    )
////
////    static var parameterSummary: some ParameterSummary {
////        Summary("Mostra uma pergunta do dia")
////    }
//    static var ProvidesDialog = true
//    
//    @MainActor
//    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
//        let questions = QuestionsDayLoader.loadQuestions()
//        
//        guard let question = questions.randomElement() else {
//            return .result(dialog: "Não há perguntas disponíveis no momento.")
//        }
//
//        // salvar a última pergunta para ser usada depois
//        PerguntaStorage.shared.salvarPergunta(question)
//        
//        
////=======================DEBUGGER ==================
//        print("ahhhhhh")
//        print(question)
//        
//
////=================================================
//        
//        var resposta = IntentDialog("Essa notícia é fato ou farsa?")
//        resposta.speakableString = "Título: \(question.titulo). Essa notícia é fato ou farsa?"
//
//        return .result(dialog: resposta, view: PerguntaDoDiaView(question: question))
//    }
//}
//
//
////Status: \(question.binario)
////Motivo: \(question.motivo)
//
//

struct PerguntaDoDiaIntent: AppIntent {
    static var title: LocalizedStringResource = "Pergunta do Dia"
    static var description = IntentDescription(
        "Mostra uma pergunta aleatória do arquivo PerguntasDoDia.tsv"
    )
    static var ProvidesDialog = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let questions = QuestionsDayLoader.loadQuestions()

        guard let question = questions.randomElement() else {
            return .result(dialog: "Não há perguntas disponíveis no momento.")
        }

        // Salva a pergunta no storage para o ResponderPerguntaIntent
        PerguntaStorage.shared.salvarPergunta(question)
        
        //=======================DEBUGGER ==================
                print("ahhhhhh")
                print(question)
        
        
        //=================================================

        // Monta o diálogo completo
        let dialogo = IntentDialog("""
        Título: \(question.titulo)
        
        Fonte: \(question.fonte)
        Autor: \(question.autor)

        Essa notícia é fato ou farsa?
        """)

        return .result(dialog: dialogo)
    }
}
