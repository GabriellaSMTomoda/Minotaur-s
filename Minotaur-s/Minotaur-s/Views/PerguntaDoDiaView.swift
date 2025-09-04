//
//  PerguntaDoDiaView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 02/09/25.


import SwiftUI

struct PerguntaDoDiaView: View {
    let question: Question
    
    var body: some View {
        VStack(spacing: 8) {
            Text(question.titulo)
                .font(.headline)
            Text("Fonte: \(question.fonte)")
                .font(.subheadline)
            Text("Autor: \(question.autor)")
                .font(.footnote)
        }
//        .padding()
        .background(.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}


