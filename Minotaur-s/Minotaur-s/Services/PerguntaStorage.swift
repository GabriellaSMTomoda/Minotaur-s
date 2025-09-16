//
//  PerguntaStorage.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 03/09/25.
//

import Foundation

class PerguntaStorage {
    static let shared = PerguntaStorage()
    private let key = "ultimaPergunta"

    func salvarPergunta(_ question: Question, data: String) {
        let dict: [String: String] = [
            "titulo": question.titulo,
            "fonte": question.fonte,
            "binario": question.binario,
            "motivo": question.motivo,
            "autor": question.autor,
            "link": question.link,
            "data": data
        ]
        UserDefaults.standard.set(dict, forKey: key)
    }

    func carregarPergunta() -> (question: Question, data: String)? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: String],
              let data = dict["data"] else { return nil }
        let question = Question(
            titulo: dict["titulo"] ?? "",
            fonte: dict["fonte"] ?? "",
            binario: dict["binario"] ?? "",
            motivo: dict["motivo"] ?? "",
            autor: dict["autor"] ?? "",
            link: dict["link"] ?? ""
        )
        return (question, data)
    }
}
