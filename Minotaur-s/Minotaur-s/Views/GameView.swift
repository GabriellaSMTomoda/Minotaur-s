//
//  GameView.swift
//  Minotaur-s
//

import SwiftUI

struct GameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gameState = GameState()
    @State private var mostrarPopup = false
    @State private var respostaCorreta = false
    @State private var fimDePartida = false
    @State private var sairPopup = false
    
    var body: some View {
        ZStack {
            Color("background")
                .ignoresSafeArea()
            VStack() {
                // HEADER
                HStack {
                    Button(action: {sairPopup = true} ) {
                        Image(systemName: "chevron.backward")
                            .font(.largeTitle)
                            .foregroundColor(Color("background"))
                            .frame(minWidth: 120, alignment: .leading)
                    }
                    Text("\(gameState.currentIndex + 1)/\(gameState.partidaFacts.count)   ")
                        .frame(alignment: .trailing)
                        .font(.system(size: 50, weight: .bold))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color("background"))
                    Button("Pular") {
                        gameState.pulos += 1
                        checkFim()
                    }
                    .font(.title)
                    .bold()
                    .foregroundColor(Color("cinza"))
                    .padding(.horizontal)
//                    .frame(maxWidth: .infinity, maxHeight: 130, alignment: .top)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: 125, alignment: .bottom)
                .background(Color("azul"))
                
                // --- Conteúdo da tela ---
                VStack {
                    Spacer(minLength: 10)
                    
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
            }
            .ignoresSafeArea(.all, edges: .top)
            
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
            
            // POP-UP de saida
            if sairPopup {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack() {
                    Spacer(minLength: 5)
                    Button("CONTINUAR") {
                        sairPopup = false
                    }
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: UIScreen.main.bounds.width * 5/7, minHeight: 30)
                    .foregroundColor(Color("background"))
                    .padding()
                    .background(Color("azul"))
                    .cornerRadius(22)
                    .padding([.leading, .trailing, .bottom], 20)
                    
                    Button("SAIR") {
                        dismiss()
                    }
                    .font(.title2)
                    .bold()
                    .frame(maxWidth: UIScreen.main.bounds.width * 5/7, minHeight: 30)
                    .foregroundColor(Color("background"))
                    .padding()
                    .background(Color("vermelho"))
                    .cornerRadius(22)
                    .padding([.leading, .trailing, .bottom], 20)
                }
                .frame(width: UIScreen.main.bounds.width * 6/7,
                       height: UIScreen.main.bounds.height * 3/14)
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
                    
                    NavigationLink(destination: GameReportView().environmentObject(gameState)) {
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
                        GamePersistence.clear()
                        gameState.partida()
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
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
    
    // Verifica se o usuário acertou ou errou
    func checkAnswer(userSaysTrue: Bool) {
        guard let fact = gameState.factAtual else { return }
        let rating = fact.binario.lowercased()
        let isTrue = rating == "true" || rating == "verdadeiro"
        respostaCorreta = (userSaysTrue == isTrue)
        mostrarPopup = true
        
        gameState.registrarResultado(para: fact.id, acertou: respostaCorreta)
        
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
