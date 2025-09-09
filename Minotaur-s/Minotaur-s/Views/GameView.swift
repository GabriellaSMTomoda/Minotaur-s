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
                                    HStack{
                                        Spacer(minLength: 17)
                                        Text(fact.assunto)
                                            .font(.caption2.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color("vermelho"))
                                            .cornerRadius(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.bottom, 4)
                                    }
                                    Text(fact.titulo)
                                        .font(.title.bold())
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(Color("texto"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                    Text("Fonte: \(fact.fonte)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(Color("texto"))
                                        .font(.callout)
                                        .padding(.horizontal)
                                    Text("Autor: \(fact.autor)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(Color("texto"))
                                        .font(.callout)
                                        .padding(.horizontal)
                                    Text(fact.resumo)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(Color("texto"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .font(.title2)
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Spacer()
                        // Botões de resposta
                        HStack {
                            
                            //            Spacer().frame(width: 15)
                            Button("FATO") {
                                checkAnswer(userSaysTrue: true)
                            }
                            .font(.title)
                            .bold()
                            .foregroundColor(Color.white)
                            .frame(minWidth: 160, maxHeight: 64)
                            .background(Color("azul"))
                            .cornerRadius(20)
                            Button("FARSA") {
                                checkAnswer(userSaysTrue: false)
                            }
                            .font(.title)
                            .bold()
                            .foregroundColor(Color.white)
                            .frame(minWidth: 160, maxHeight: 64)
                            .background(Color("vermelho"))
                            .cornerRadius(20)
                        }
                        .padding(.bottom, 2)
                        Button("Pular") {
                            gameState.pulos += 1
                            checkFim()
                        }
                        .padding(.bottom, -20)
                        .bold()
                        .foregroundColor(Color("cinza"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
                if popupAppIntent {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack {
                        Text("NOTÍCIA DO DIA")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(Color("azul"))
                            .foregroundColor(Color.white)
                        ScrollView{
                            Text("""
                                 Para jogar pela Siri, siga os seguintes passos:
                                
                                 1) Ative a Siri em Ajustes > Siri e Busca (ou Ajustes > Apple Intelligence) e confirme que a opção "Falar com a Siri" ou "Ouvir 'E aí Siri'" está ligada.
                                """)
                            .padding()
                            .foregroundColor(Color("texto"))
                            Button(action: {
                                if let url = URL(string: "App-Prefs:root=APPLE_INTELLIGENCE") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Abrir Ajustes da Siri")
                                    .fontWeight(.bold)
//                                    .foregroundColor(.white)
                                    .padding()
//                                    .frame(maxWidth: .infinity, maxHeight: 20)
//                                    .background(Color("azul"))
                                    .cornerRadius(10)
                                    .padding()
                            }
                            .frame(maxHeight: 12)
                            Text("""
                                 2) Para jogar a Pergunta do Dia, basta dizer:
                                 “E aí Siri, qual a notícia do dia no Fato ou Farsa?”
                                 
                                 3) Para responder, basta dizer:
                                 "Minha resposta é Fato/Farsa no Fato ou Farsa"
                                 """)
                            .padding()
                            .foregroundColor(Color("texto"))
                        }
                        Button("ENTENDI") {
                            popupAppIntent = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color("azul"))
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color("pop"))
                        .padding(.bottom)
                    }
                    .frame(width: UIScreen.main.bounds.width * 5/6,
                           height: UIScreen.main.bounds.height * 3/4)
                    .background(Color("pop"))
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
                            .foregroundColor(Color.white)
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
                    .background(Color("pop"))
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
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Color("azul"))
                            .foregroundColor(Color.white)
                        NavigationLink(destination: GameReportView().environmentObject(gameState)) {
                            Text("REVISÃO")
                                .font(.title2)
                                .bold()
                                .frame(width: 264, height: 64)
                                .background(Color("azul"))
                                .foregroundColor(.white)
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
                        .padding(.bottom)
                    }
                    .frame(width: UIScreen.main.bounds.width * 5/6)
                    .background(Color("pop"))
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        popupAppIntent = true
                    }) {
                        Image(systemName: "info.circle")
                        //.frame(width: 40, height: 40)
                            .foregroundColor(.white) // cor do ícone
                    }
                    //.bold()
                }
            }
        }
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





