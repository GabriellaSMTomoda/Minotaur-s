//
//  GameView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.
//

import SwiftUI

struct GameView: View {
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var gameState = GameState()
    @State private var facts: [Fact] = FactLoader.loadFacts()
    @State private var mostrarPopup = false
    @State private var respostaCorreta = false
    
    // Novo: popup final
    @State private var fimDePartida = false
    
    var body: some View {
        ZStack {
            VStack {
                if !gameState.partidaFacts.isEmpty {
//                    let fact = gameState.partidaFacts[gameState.currentIndex]
                    
                    // Indicador de progresso
                    Text("Notícia \(gameState.currentIndex + 1) de \(gameState.partidaFacts.count)")
                        .font(.headline)
                        .padding(.top)
                    
                    Text(facts[gameState.currentIndex].titulo)
                        .font(.title2) .padding()
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
                    gameState.pulos += 1
                    checkFim()
                }
                .font(.title)
            }
            .padding()
            
            // POP-UP de resposta
            if mostrarPopup {
                Color.black.opacity(0.4)
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
                        checkFim()
                    }

                    .font(.title2)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                }
                .frame(width: UIScreen.main.bounds.width * 4/5,
                       height: UIScreen.main.bounds.height * 2/3)
                .background(Color.white)
                .cornerRadius(20)
                .shadow(radius: 10)
            }
            
            // POP-UP final
            if fimDePartida {
                
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Text("🎉 Fim da partida!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Acertos: \(gameState.acertos)\nErros: \(gameState.erros)\nPulos: \(gameState.pulos)")
                        .multilineTextAlignment(.center)
                    
                    NavigationLink(destination: GameReportView()) {
                        Text("📊 Ver relatório")
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button("🔄 Jogar novamente") {
                        fimDePartida = false
                        gameState.partida()
                        GamePersistence.clear()

                    }
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    
                    Button("🏠 Tela inicial") {
                        GamePersistence.clear()
                        dismiss()   //volta para ContentView
                    }
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
                .frame(width: UIScreen.main.bounds.width * 4/5)
                .background(Color.white)
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
//        .onAppear {
//            if gameState.partidaFacts.isEmpty {
//                gameState.facts = FactLoader.loadFacts()
//                gameState.partida()
//            }
//        }
        
        .onAppear {
            gameState.facts = FactLoader.loadFacts()
            
            // tenta carregar progresso salvo
            GamePersistence.load(into: gameState)
            
            // se não tinha partida salva, inicia nova
            if gameState.partidaFacts.isEmpty {
                gameState.partida()
            }
        }
        .onDisappear {
            GamePersistence.save(gameState: gameState)
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
    
    // Checa se chegou ao fim
    func checkFim() {
        if gameState.currentIndex == gameState.partidaFacts.count - 1{
            fimDePartida = true
        } else {
            gameState.nextFact()
        }
    }
}

#Preview {
    GameView()
}


// SALVAR OS DADOS

