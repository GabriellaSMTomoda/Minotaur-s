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
    @State private var mostrarPopup = false
    @State private var respostaCorreta = false
    @State private var fimDePartida = false
    
    var body: some View {
        ZStack {
            Color("background")
                .ignoresSafeArea()
            VStack(spacing: 0) {
                // HEADER
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.largeTitle)
                        .foregroundColor(Color("background"))
                        .scaleEffect(x: -1, y: 1)
                    Spacer()
                    Image("icon")
                        .font(.largeTitle)
                        .foregroundColor(Color("background"))
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 57)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: 138, alignment: .bottom)
                .background(Color("azul"))
                
                // --- Conteúdo da tela ---
                VStack {
                    Spacer(minLength: 10)
                    Text("\(gameState.currentIndex + 1)/\(gameState.partidaFacts.count)   ")
                        .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: 85, alignment: .trailing)
//                        .font(.system(size: 40, weight: .bold))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color("azul"))
                    Spacer()
                    ScrollView {
                        VStack(spacing: 16) {
                            if let fact = gameState.factAtual {
                                HStack {
                                    Text(fact.assunto)
                                        .font(.headline)
                                        .foregroundColor(Color("background"))
                                        .frame(maxWidth: 190, maxHeight: 30)
                                        .background(Color("vermelho"))
                                        .cornerRadius(20)
                                        .padding(.horizontal)
                                    Spacer()
                                }
                                Text(fact.titulo)
                                    .font(.title2.bold())
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal)
                                Text(fact.resumo)
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal)
                            }
                        }
                        .frame(maxWidth: UIScreen.main.bounds.width * 8/9)
                    }
                    Spacer()
                }
                .frame(maxHeight: .infinity)
                
                // Botões de resposta
                HStack {
                    Spacer(minLength: 25)
                    Button("FATO") {
                        checkAnswer(userSaysTrue: true)
                    }
                    .font(.title)
                    .bold()
                    .foregroundColor(Color("background"))
                    .frame(maxWidth: .infinity, minHeight: 63)
                    .background(Color("azul"))
                    .cornerRadius(22)
                    
                    Spacer(minLength: 25)
                    
                    Button("FARSA") {
                        checkAnswer(userSaysTrue: false)
                    }
                    .font(.title)
                    .bold()
                    .lineLimit(1)
                    .foregroundColor(Color("background"))
                    .frame(maxWidth: .infinity, minHeight: 63)
                    .background(Color("vermelho"))
                    .cornerRadius(22)
                    Spacer(minLength: 25)
                }
                .padding()
                .frame(width: UIScreen.main.bounds.width)
                Button("Pular") {
                    gameState.pulos += 1
                    checkFim()
                }
                .font(.title)
                .bold()
                .foregroundColor(Color("cinza"))
                .frame(maxWidth: .infinity, maxHeight: 130, alignment: .top)
                //                    .padding()
            }
            .ignoresSafeArea(.all)
            
            // POP-UP de resposta
            if mostrarPopup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text(respostaCorreta ? "CORRETO" : "ERRADO")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(respostaCorreta ? Color("verde") : Color("vermelho"))
                        .foregroundColor(Color("background"))
                    
                    if let fact = gameState.factAtual {
                        ScrollView {
                            Text(fact.motivo)
                                .padding()
                        }
                    }
                    
                    Spacer()
                    
                    Button("PRÓXIMA") {
                        mostrarPopup = false
                        checkFim()
                    }
                    .font(.title2)
                    .bold()
                    .foregroundColor(Color("background"))
                    .padding()
                    .background(Color("azul"))
                    .cornerRadius(12)
                    .padding([.leading, .trailing, .bottom], 20)
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
                        .font(.title)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .padding(.vertical, 10)
                        .background(Color("azul"))
                        .foregroundColor(Color("background"))
                    
                    NavigationLink(destination: GameReportView()) {
                        Text("REVISÃO")
                            .font(.title2)
                            .bold()
                            .frame(maxWidth: UIScreen.main.bounds.width * 5/7, minHeight: 62)
                            .background(Color("azul"))
                            .foregroundColor(Color("background"))
                            .cornerRadius(22)
                        }
                    
                    Button("JOGAR DE NOVO") {
                        fimDePartida = false
                        gameState.partida()
                        GamePersistence.clear()
                    }
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: UIScreen.main.bounds.width * 5/7, minHeight: 62)
                    .background(Color("azul"))
                    .foregroundColor(Color("background"))
                    .cornerRadius(22)
                    
                    Button("SAIR") {
                        GamePersistence.clear()
                        dismiss()
                    }
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: UIScreen.main.bounds.width * 5/7, minHeight: 62)
                    .background(Color("vermelho"))
                    .foregroundColor(Color("background"))
                    .cornerRadius(22)
                    
                    Spacer(minLength: 5)
                }
                .frame(width: UIScreen.main.bounds.width * 4/5,
                       height: UIScreen.main.bounds.height * 3/7)
                .background(Color("background"))
                .cornerRadius(20)
                .shadow(radius: 10)
            }
        }
        //        .ignoresSafeArea()
        .onAppear {
            gameState.facts = FactLoader.loadFacts()
            GamePersistence.load(into: gameState)
            
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
        guard let fact = gameState.factAtual else { return }
        let rating = fact.binario.lowercased()
        let isTrue = rating == "true" || rating == "verdadeiro"
        respostaCorreta = (userSaysTrue == isTrue)
        mostrarPopup = true
        if respostaCorreta {
            gameState.acertos += 1
        } else {
            gameState.erros += 1
        }
    }
    // Checa se chegou ao fim da partida
    func checkFim() {
        if gameState.currentIndex == gameState.partidaFacts.count - 1 {
            fimDePartida = true
        } else {
            gameState.nextFact()
        }
    }
}

#Preview {
    GameView()
}

 //++++++++++DEBBUGUER, NAO APAGAR+++++++++++++++++
                    
//                    Text("Acertos: \(gameState.acertos)\nErros: \(gameState.erros)\nPulos: \(gameState.pulos)")
//                        .multilineTextAlignment(.center)
