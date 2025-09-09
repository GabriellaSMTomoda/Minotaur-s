//
//  QuestionsDayLoader.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 01/09/25.
//

import Foundation

class QuestionsDayLoader {
    static func loadQuestions() -> [Question] {
        guard let url = Bundle.main.url(forResource: "PerguntasDoDia", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var questions: [Question] = []
        let lines = content.components(separatedBy: "\n")
        
        for line in lines.dropFirst() { // pula header
            let columns = line.components(separatedBy: "\t")
            // Confirma que temos pelo menos 7 colunas: ID, Titulo, Fonte, Binario, Motivo, Autor, Link
            guard columns.count >= 7 else { continue }
            
            let question = Question(
                titulo: columns[1],
                fonte: columns[2],
                binario: columns[3],
                motivo: columns[4],
                autor: columns[5],
                link: columns[6]
            )
            questions.append(question)
        }
        
        return questions
    }
}

