//
//  GameView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.
//

import SwiftUI

struct GameView: View {
    var body: some View {
        VStack {
            HStack {
                Button(action: {
    
                }) {
                    Text("FALSO")
                        .font(.title) // aumenta o tamanho do texto
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    
                }) {
                    Text("VERDADE")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.green)
                        .cornerRadius(10)
                }
            }
            .padding()

            
            Button(action: {
                
            }) {
                Text("PULAR")
                    .font(.title)

            }
        }
        .padding()
    }
}

#Preview {
    GameView()
}
