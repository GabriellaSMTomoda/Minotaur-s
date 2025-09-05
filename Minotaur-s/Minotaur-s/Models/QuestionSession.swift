//
//  QuestionSession.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 03/09/25.
//

class QuestionSession {
    static let shared = QuestionSession()
    var currentQuestion: Question?
    private init() {}
}
