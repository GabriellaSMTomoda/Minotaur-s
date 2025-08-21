//
//  GameView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.
//

import SwiftUI

struct GameView: View {
    @StateObject private var gameState = GameState()
    @State private var facts: [Fact] = FactLoader.loadFacts()
    @State private var mostrarPopup = false
    @State private var respostaCorreta = false
    
    var body: some View {
        ZStack {
            VStack {
                if !gameState.partidaFacts.isEmpty {
                    let fact = gameState.partidaFacts[gameState.currentIndex]
                    
                    // Indicador de progresso
                    Text("Notícia \(gameState.currentIndex + 1) de \(gameState.partidaFacts.count)")
                        .font(.headline)
                        .padding(.top)
                    
                    Text(facts[gameState.currentIndex].titulo)
                        .font(.title2)
                        .padding()
                    Text(facts[gameState.currentIndex].resumo)
                        .padding()
                }
                
                Spacer()
                
                // Botões de resposta
                HStack {
                    Button("FALSO") {
                        checkAnswer(userSaysTrue: false)
                    }
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Color.red)
                    .cornerRadius(10)
                    
                    Button("VERDADE") {
                        checkAnswer(userSaysTrue: true)
                    }
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Color.green)
                    .cornerRadius(10)
                }
                .padding()
                
                Button("PULAR") {
                    gameState.pulouQuestao()
                }
                .font(.title)
            }
            .padding()
            
            // POP-UP customizado
            if mostrarPopup {
                Color.black.opacity(0.4) // fundo escuro
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text(respostaCorreta ? "Correto ✅" : "Errado ❌")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding()
                    
                    Text(facts[gameState.currentIndex].motivo)
                        .padding()
                    
                    Button("Próxima questão") {
                        mostrarPopup = false
                        gameState.nextFact()
                    }
                    .font(.title2)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                }
                .frame(width: UIScreen.main.bounds.width * 4/5, height: UIScreen.main.bounds.height * 2/3)
                .background(Color.white)
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
        .onAppear {
            if gameState.partidaFacts.isEmpty {
                gameState.facts = FactLoader.loadFacts()
                gameState.partida()
            }
        }
    }
    
    // Verifica se o usuário acertou ou errou
    func checkAnswer(userSaysTrue: Bool) {
        guard !gameState.partidaFacts.isEmpty else { return }
        
        let rating = gameState.partidaFacts[gameState.currentIndex].binario.lowercased()
        let isTrue = rating == "true" || rating == "verdadeiro"
        
        respostaCorreta = (userSaysTrue == isTrue)
        mostrarPopup = true
        
        if respostaCorreta {
            gameState.acertos += 1
        } else {
            gameState.erros += 1
        }
    }
}

#Preview {
    GameView()
}

