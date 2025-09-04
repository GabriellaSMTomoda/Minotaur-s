import SwiftUI
struct GameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gameState = GameState()
    @State private var mostrarPopup = false
    @State private var respostaCorreta = false
    @State private var fimDePartida = false
    @State private var popupAppIntent = false
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "azul") // fundo azul
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white] // título branco
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    var body: some View {
        NavigationStack {
            ZStack {
                //Color("background")
                // .ignoresSafeArea()
                VStack(spacing: 0) {
                    VStack {
                        Spacer()
                        ScrollView {
                            VStack() {
                                if let fact = gameState.factAtual {
                                    Text(fact.titulo)
                                        .font(.title.bold())
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .foregroundColor(Color("texto"))
                                    Text(fact.resumo)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal)
                                        .foregroundColor(Color("texto"))
                                    Text("Fonte: \(fact.autor)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .foregroundColor(Color("texto"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer()
                        // Botões de resposta
                        HStack {
                            Button("FALSO") {
                                checkAnswer(userSaysTrue: false)
                            }
                            .font(.title)
                            .bold()
                            .foregroundColor(Color.white)
                            .frame(minWidth: 160, maxHeight: 64)
                            .background(Color("vermelho"))
                            .cornerRadius(20)
                            //            Spacer().frame(width: 15)
                            Button("REAL") {
                                checkAnswer(userSaysTrue: true)
                            }
                            .font(.title)
                            .bold()
                            .foregroundColor(Color.white)
                            .frame(minWidth: 160, maxHeight: 64)
                            .background(Color("azul"))
                            .cornerRadius(20)
                        }
                        Button("Pular") {
                            gameState.pulos += 1
                            checkFim()
                        }
                        .bold()
                        .foregroundColor(Color("cinza"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
                if popupAppIntent {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack() {
                        Text("Jogue por voz!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .background(Color("azul"))
                            .foregroundColor(Color.white)
                        ScrollView{
                            Text("idjidjidj")
                                .padding()
                        }
                        Button("ENTENDI") {
                            popupAppIntent = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("azul"))
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.white)
                        .padding(.bottom)
                    }
                    .frame(width: UIScreen.main.bounds.width * 5/6,
                           height: UIScreen.main.bounds.height * 3/4)
                    .background(Color("revisao_pop"))
                    .cornerRadius(20)
                }
                // POP-UP de resposta
                if mostrarPopup {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack() {
                        Text(respostaCorreta ? "ACERTOU" : "ERROU")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .background(respostaCorreta ? Color("verde") : Color("vermelho"))
                            .foregroundColor(.white)
                        ScrollView{
                            if let fact = gameState.factAtual {
                                Text(fact.motivo)
                                    .foregroundColor(Color("texto"))
                                    .padding()
                            }
                        }
                        Button("PRÓXIMA") {
                            mostrarPopup = false
                            checkFim()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("azul"))
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.white)
                        .padding(.bottom)
                    }
                    .frame(width: UIScreen.main.bounds.width * 4/5,
                           height: UIScreen.main.bounds.height * 2/3)
                    .background(Color("revisao_pop"))
                    .cornerRadius(20)
                    .shadow(radius: 10)
                }
                // POP-UP final
                if fimDePartida {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 20) {
                        Text("FIM DA PARTIDA")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Color("azul"))
                        NavigationLink(destination: GameReportView().environmentObject(gameState)) {
                            Text("REVISÃO")
                                .font(.title2)
                                .foregroundColor(.white)
                                .bold()
                                .frame(width: 264, height: 64)
                                .background(Color("azul"))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        Button("JOGAR DE NOVO") {
                            fimDePartida = false
                            GamePersistence.clear()
                            gameState.partida()
                        }
                        .font(.title2)
                        .bold()
                        .frame(width: 264, height: 64)
                        .background(Color("azul"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        Button("SAIR") {
                            GamePersistence.clear()
                            dismiss()
                        }
                        .font(.title2)
                        .bold()
                        .frame(width: 264, height: 64)
                        .background(Color("vermelho"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding([.leading, .trailing, .bottom])
                    }
                    .frame(width: UIScreen.main.bounds.width * 4/5)
                    .background(Color("revisao_pop"))
                    .cornerRadius(20)
                    .shadow(radius: 10)
                }
            }
            //.navigationBarBackButtonHidden(true)
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
            .navigationTitle("\(gameState.currentIndex + 1)/\(gameState.partidaFacts.count)")
            .navigationBarTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("logo") {
                        popupAppIntent = true
                    }
                    .foregroundColor(.white)
                    .bold()
                }
            }
        }
    }
    
    // Verifica se o usuário acertou ou errou
    func checkAnswer(userSaysTrue: Bool) {
        guard let fact = gameState.factAtual else { return }
        let rating = fact.binario.lowercased()
        let isTrue = rating == "FATO" || rating == "verdadeiro"
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
