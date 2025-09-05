//
//  Question.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 01/09/25.
//

import Foundation

struct Question: Identifiable {
    let id = UUID()
    let titulo: String
    let fonte: String
    let binario: String
    let motivo: String
    let autor: String
    let link: String
}
