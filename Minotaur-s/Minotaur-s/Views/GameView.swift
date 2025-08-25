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
            Color("background")
                .ignoresSafeArea() // ocupa toda a tela
            VStack(spacing: 0) {
                // HEADER (faixa azul)
                HStack {
                    Image(systemName: "newspaper.fill") // ícone
                        .foregroundColor(Color("background"))
                    
                    Text("APP NEWS")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color("background"))
                    Spacer()
                    
                    // Contador à direita
                    Text("\(gameState.currentIndex + 1)/\(gameState.partidaFacts.count)")
                        .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color("background"))                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color("azul"))
                                
                // --- Conteúdo da tela ---
                VStack {
                    Spacer() // empurra para baixo quando o texto for pequeno

                    ScrollView {
                        VStack(spacing: 16) {
                            Text(facts[gameState.currentIndex].titulo)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .padding()

                            Text(facts[gameState.currentIndex].resumo)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity) // centraliza no eixo horizontal
                    }

                    Spacer() // empurra para cima quando o texto for pequeno
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)




                    
                    // Botões de resposta
                    HStack {
                        Button("FALSO") {
                            checkAnswer(userSaysTrue: false)
                        }
                        .font(.title)
                        .bold()
                        .foregroundColor(Color("background"))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color("vermelho"))
                        .cornerRadius(20)
                        
                        Button("REAL") {
                            checkAnswer(userSaysTrue: true)
                        }
                        .font(.title)
                        .bold()
                        .foregroundColor(Color("background"))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color("azul"))
                        .cornerRadius(20)
                    }
                    .padding()
                    
                    Button("Pular") {
                        gameState.pulos += 1
                        checkFim()
                    }
                    .font(.title)
                    .bold()
                    .foregroundColor(Color("cinza"))
                    
                }
            .padding()
            
            // POP-UP de resposta
            if mostrarPopup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
//                    Text(respostaCorreta ? "CORRETO" : "ERRADO")
//                        .font(.largeTitle)
//                        .fontWeight(.bold)
//                        .padding()
                    
                    Text(respostaCorreta ? "CORRETO" : "ERRADO")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)   // espaço vertical da faixa
                        .background(respostaCorreta ? Color("azul") : Color("vermelho")) // cor da faixa
                        .foregroundColor(Color("background"))  // cor do texto


                    
                    Text(facts[gameState.currentIndex].motivo)
                        .padding()
                    
                    Spacer()
                    
                    Button("PRÓXIMA") {
                        mostrarPopup = false
                        checkFim()
                    }

                    .font(.title2)
                    .bold()
                    .foregroundColor(Color("background")) // cor do texto
                    .padding()
                    .background(Color("azul"))
                    .cornerRadius(12)
                    .padding([.leading, .trailing, .bottom], 20) // margem interna do popup

                }
                .frame(width: UIScreen.main.bounds.width * 4/5,
                       height: UIScreen.main.bounds.height * 2/3)
                .background(Color("background"))
                .cornerRadius(20)
                .shadow(radius: 10)
            }
            
            // POP-UP final
            if fimDePartida {
                
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Text("FIM DA PARTIDA")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)   // espaço vertical da faixa
                        .background(Color("azul")) // cor da faixa
                        .foregroundColor(Color("background"))  // cor do texto
                    
                    
 //++++++++++DEBBUGUER, NAO APAGAR+++++++++++++++++
                    
//                    Text("Acertos: \(gameState.acertos)\nErros: \(gameState.erros)\nPulos: \(gameState.pulos)")
//                        .multilineTextAlignment(.center)
                    
                    NavigationLink(destination: GameReportView()) {
                        Text("REVISÃO")
                            .font(.title2)
                            .bold()
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color("azul"))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button("JOGAR DE NOVO") {
                        fimDePartida = false
                        gameState.partida()
                        GamePersistence.clear()

                    }
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    
                    Button("🏠 Tela inicial") {
                        GamePersistence.clear()
                        dismiss()   //volta para ContentView
                    }
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
                .frame(width: UIScreen.main.bounds.width * 4/5)
                .background(Color("background"))
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

