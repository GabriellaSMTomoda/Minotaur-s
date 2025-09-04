//
//  dadosNoticias.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 19/08/25.
//


import Foundation

struct Fact: Identifiable {
    let id = UUID()
    let url: String
    let autor: String
    let data: String
    let motivo: String
    let resumo: String
    let titulo: String
    let binario: String
    let assunto: String
}


