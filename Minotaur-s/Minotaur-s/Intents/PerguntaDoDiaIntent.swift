//
//  PerguntaDoDiaIntent.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 01/09/25.
//

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
        let hoje = DateFormatterStorage.shared.stringFromDate(Date())
        
        
        // ===================DEBBUGUER====================================
        // Força o "hoje" para ontem
//        let hoje = DateFormatterStorage.shared.stringFromDate(
//            Calendar.current.date(byAdding: .day, value: -1, to: Date())!
//        )
        // =================================================================
        
        let emptyQuestion = Question(titulo: "", fonte: "", binario: "", motivo: "", autor: "", link: "")

        if let (perguntaSalva, data) = PerguntaStorage.shared.carregarPergunta() {
            if data == hoje {
                // mesma data → mantém
                let dialogo = IntentDialog("""
                Você já recebeu a pergunta de hoje!
                Título: \(perguntaSalva.titulo)
                Fonte: \(perguntaSalva.fonte)
                Autor: \(perguntaSalva.autor)

                Essa notícia é fato ou farsa?
                """)
                QuestionSession.shared.currentQuestion = perguntaSalva
                return .result(dialog: dialogo, view: PerguntaDoDiaView(question: perguntaSalva))
            } else {
                // nova data → limpa
                QuestionSession.shared.currentQuestion = nil
            }
        }


        // Caso não exista, sorteia uma nova pergunta
        let questions = QuestionsDayLoader.loadQuestions()
        guard let question = questions.randomElement() else {
            // Se não houver perguntas, retorna uma View mínima vazia
            let dialogo = IntentDialog("Não há perguntas disponíveis no momento.")
            return .result(dialog: dialogo, view: PerguntaDoDiaView(question: emptyQuestion))
        }

        // Salva a pergunta do dia
        PerguntaStorage.shared.salvarPergunta(question, data: hoje)
        QuestionSession.shared.currentQuestion = question

        // Monta o diálogo
        let dialogo = IntentDialog("""
        Título: \(question.titulo)
        Fonte: \(question.fonte)
        Autor: \(question.autor)

        Essa notícia é fato ou farsa?
        """)

        return .result(dialog: dialogo, view: PerguntaDoDiaView(question: question))
    }
}

