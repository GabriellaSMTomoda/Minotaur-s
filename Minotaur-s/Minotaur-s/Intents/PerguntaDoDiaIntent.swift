//
//  PerguntaDoDiaIntent.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 01/09/25.


import AppIntents
import SwiftUI


struct PerguntaDoDiaIntent: AppIntent {
    static var title: LocalizedStringResource = "Pergunta do Dia"
    static var description = IntentDescription(
        "Mostra uma pergunta aleatória do arquivo PerguntasDoDia.tsv"
    )
    static var ProvidesDialog = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Carrega todas as perguntas
        let questions = QuestionsDayLoader.loadQuestions()
        guard let question = questions.randomElement() else {
            return .result(dialog: "Não há perguntas disponíveis no momento.")
        }

        // Salva a pergunta **em memória e no storage**
        QuestionSession.shared.currentQuestion = question
        PerguntaStorage.shared.salvarPergunta(question)

                //=======================DEBUGGER ==================
                        print("ahhhhhh")
                        print(question)
        
        
                //=================================================
        
        // Monta o diálogo
        let dialogo = IntentDialog("""
        Título: \(question.titulo)
        
        Fonte: \(question.fonte)
        Autor: \(question.autor)

        Essa notícia é fato ou farsa?
        """)

//        return .result(dialog: dialogo, view: PerguntaDoDiaView(question: question))
        return .result(dialog: dialogo)

    }
}

