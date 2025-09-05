//
//  PerguntaDoDiaView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 02/09/25.

import SwiftUI

struct PerguntaDoDiaView: View {
    let question: Question
    
    var body: some View {
        VStack(spacing: 16) { // Aumenta o espaçamento entre os textos
            Text(question.titulo)
                .font(.headline)
                .multilineTextAlignment(.center) // ajuda caso seja longo
                .padding(.bottom, 4) // respiro extra embaixo do título
            
            Text("Fonte: \(question.fonte)")
                .font(.subheadline)
            
            Text("Autor: \(question.autor)")
                .font(.footnote)
        }
        .padding(20) // mais espaçamento interno ao redor do conteúdo
        .background(.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24) // margem externa nas laterais
        .padding(.bottom, 32)
    }
}
