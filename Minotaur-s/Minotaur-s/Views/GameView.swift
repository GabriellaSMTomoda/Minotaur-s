import SwiftUI

// PreferenceKey to capture frames of views for spotlight tutorial
struct ViewFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// Lightweight callout card to reduce SwiftUI type-checking complexity
private struct CalloutCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(Color("texto"))
            Text(message)
                .font(.subheadline)
                .foregroundColor(Color("texto").opacity(0.9))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 4)
    }
}

struct GameView: View {
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gameState = GameState()
    @State private var mostrarPopup = false
    @State private var respostaCorreta = false
    @State private var fimDePartida = false
    @State private var popupAppIntent = false
    @State private var explicacao_inicial = false
    @State private var tutorialStep: Int = 0
    @State private var frames: [String: CGRect] = [:]

    var body: some View {
        ZStack {
                VStack(spacing: 0) {
                    VStack {
                        Spacer()
                        ScrollView {
                            VStack() {
                                // Capture frame for news area
                                
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
                                            .accessibilityLabel("Assunto: \(fact.assunto).")
                                            .accessibilitySortPriority(1)
                                    }
                                    Text(fact.titulo)
                                        .font(.title.bold())
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(Color("texto"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                        .accessibilityLabel("Título: \(fact.titulo).")
                                        .accessibilitySortPriority(0)
                                    Text("Fonte: \(fact.fonte)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(Color("texto"))
                                        .font(.callout)
                                        .padding(.horizontal)
                                        .accessibilityLabel("Fonte: \(fact.fonte).")
                                        .accessibilitySortPriority(3)
                                    Text("Autor: \(fact.autor)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(Color("texto"))
                                        .font(.callout)
                                        .padding(.horizontal)
                                        .accessibilityLabel("Autor: \(fact.autor).")
                                        .accessibilitySortPriority(4)
                                    Text(fact.resumo)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(Color("texto"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .font(.title2)
                                        .padding(.horizontal)
                                        .padding(.bottom)
                                        .accessibilityLabel("Resumo: \(fact.resumo).")
                                        .accessibilitySortPriority(2)
                                }
                            }
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: ViewFrameKey.self, value: ["newsArea": proxy.frame(in: .global)])
                            })
                        }
                        .scrollIndicators(.hidden)
                        Spacer()
                        // Botões de resposta
                        HStack {
                            Button("Fato") {
                                checkAnswer(userSaysTrue: true)
                            }
                            .font(.title)
                            .bold()
                            .foregroundColor(Color.white)
                            .frame(minWidth: 160, maxHeight: 64)
                            .background(Color("azul"))
                            .cornerRadius(20)
                            .accessibilityLabel("Fato")
                            .accessibilityHint("Toque para confirmar que a notícia é verdadeira.")
                            .accessibilitySortPriority(5)
                            Button("Farsa") {
                                checkAnswer(userSaysTrue: false)
                            }
                            .font(.title)
                            .bold()
                            .foregroundColor(Color.white)
                            .frame(minWidth: 160, maxHeight: 64)
                            .background(Color("vermelho"))
                            .cornerRadius(20)
                            .accessibilityLabel("Farsa")
                            .accessibilityHint("Toque para confirmar que a notícia NÃO é verdadeira.")
                            .accessibilitySortPriority(6)
                        }
                        .padding(.bottom, 2)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ViewFrameKey.self, value: ["answerButtons": proxy.frame(in: .global)])
                        })
                        Button("Pular") {
                            gameState.pulos += 1
                            checkFim()
                        }
                        .padding(.top, 8)
                        .bold()
                        .foregroundColor(Color("cinza"))
                        .accessibilityLabel("PULAR")
                        .accessibilityHint("Toque para pular a notícia.")
                        .accessibilitySortPriority(7)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ViewFrameKey.self, value: ["skipButton": proxy.frame(in: .global)])
                        })
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
                .allowsHitTesting(!explicacao_inicial)

                if popupAppIntent {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack {
                        Text("Notícia do dia")
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
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Abrir Ajustes da Siri")
                                    .fontWeight(.bold)
                            }
                            //.buttonStyle(.borderedProminent)
                            //.tint(Color("azul"))
                            .accessibilityLabel("Abrir Ajustes do app nas Configurações")
                            .accessibilityHint("Abre as Configurações do iPhone para ajustar permissões e preferências do app")
                            .padding()
                            Text("""
                                 2) Para jogar a Pergunta do Dia, basta dizer:
                                 “E aí Siri, qual a notícia do dia no Fato ou Farsa?”
                                 
                                 3) Para responder, basta dizer:
                                 "Minha resposta é Fato/Farsa no Fato ou Farsa"
                                 """)
                            .padding()
                            .foregroundColor(Color("texto"))
                        }
                        Button("Entendi") {
                            popupAppIntent = false
                        }
                        //.buttonStyle(.borderedProminent)
                        //.tint(Color("azul"))
                        //.font(.title2)
                        //.bold()
                        //.foregroundColor(Color.white)
                                                
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.white)
                        .frame(minWidth: 140, maxHeight: 54)
                        .background(Color("azul"))
                        .cornerRadius(20)
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
                        Text(respostaCorreta ? "Acertou" : "Errou")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 55)
                            .background(respostaCorreta ? Color("verde") : Color("vermelho"))
                            .foregroundColor(Color.white)
                            .accessibilityLabel(respostaCorreta ? "ACERTOU" : "ERROU")
                            .accessibilitySortPriority(8)
                        ScrollView{
                            if let fact = gameState.factAtual {
                                Text(fact.motivo)
                                    .foregroundColor(Color("texto"))
                                    .padding(.horizontal)
                                    .accessibilityLabel("Explicação do motivo: \(fact.motivo)")
                                    .accessibilitySortPriority(9)
                            }
                        }
                        Button("Próxima") {
                            mostrarPopup = false
                            checkFim()
                        }
                        .font(.title2)
                        .bold()
                        .foregroundColor(Color.white)
                        .frame(minWidth: 140, maxHeight: 54)
                        .background(Color("azul"))
                        .cornerRadius(20)
                        .padding(.bottom)

                        //.buttonStyle(.borderedProminent)
                        //.tint(Color("azul"))
                        //.font(.title2)
                        //.bold()
                        //.foregroundColor(Color.white)
                        //.padding(.bottom)
                        .accessibilityLabel("PRÓXIMA")
                        .accessibilityHint("Aperte para ver a próxima pergunta")
                        .accessibilitySortPriority(10)
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
                        Text("Fim da partida")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Color("azul"))
                            .foregroundColor(Color.white)
                            .accessibilityLabel("Fim da Partida")
                            .accessibilitySortPriority(11)
                        NavigationLink(destination: GameReportView().environmentObject(gameState)) {
                            Text("Revisar")
                                .font(.title2)
                                .bold()
                                .frame(width: 264, height: 64)
                                .background(Color("azul"))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .accessibilityLabel("REVISÃO")
                                .accessibilityHint("Aperte para ver os erros e acertos desta partida")
                                .accessibilitySortPriority(12)
                        }
                        .padding(.horizontal)
                        Button("Jogar de novo") {
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
                        .accessibilityLabel("JOGAR DE NOVO")
                        .accessibilityHint("Aperte para Jogar um novo jogo")
                        .accessibilitySortPriority(13)
                        
                        Button("Sair") {
                            fimDePartida = true
                            GamePersistence.clear()
                            dismiss()
                        }
                        .font(.title2)
                        .bold()
                        .frame(width: 264, height: 64)
                        .background(Color("vermelho"))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.bottom)
                        .accessibilityLabel("SAIR")
                        .accessibilityHint("Aperte para voltar a tela inicial")
                        .accessibilitySortPriority(14)
                    }
                    .frame(width: UIScreen.main.bounds.width * 5/6)
                    .background(Color("pop"))
                    .cornerRadius(20)
                    .shadow(radius: 10)
                }
                
                if explicacao_inicial {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()

                        VStack(spacing: 0) {
                            // Top-right skip
                            HStack {
                                Spacer()
                                Button("Pular tutorial") {
                                    explicacao_inicial = false
                                }
                                .font(.callout.weight(.semibold))
                                .foregroundColor(.white.opacity(0.95))
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }

                            Spacer(minLength: 0)

                            // Tutorial card
                            VStack(spacing: 16) {
                                // Image for current step (tutorial1, tutorial2, tutorial3)
                                Image("tutorial\(tutorialStep + 1)")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 520)
                                    .cornerRadius(12)
                                    .accessibilityHidden(true)

                                // Text for current step
                                Group {
                                    switch tutorialStep {
                                    case 0:
                                        Text("Leia o título e resumo da notícia, analisando se  é um fato ou uma farsa")
                                    case 1:
                                        Text("Toque em \"Fato\", \"Farsa\" ou \"Pular\" de acordo com o que você analisou")
                                    default:
                                        Text("Depois de marcar 10 questões, você pode revisar tudo o que errou ou acertou!")
                                    }
                                }
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(Color("texto"))
                                .padding(.horizontal)
                            }
                            .padding(20)
                            .frame(maxWidth: min(UIScreen.main.bounds.width * 0.9, 600))
                            .background(Color("pop"))
                            .cornerRadius(20)
                            .shadow(radius: 10)
                            .padding(.horizontal)

                            // Step indicators
                            HStack(spacing: 6) {
                                ForEach(0..<3, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == tutorialStep ? Color.white : Color.white.opacity(0.4))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.top, 12)

                            // Bottom controls
                            HStack(spacing: 12) {
                                if tutorialStep > 0 {
                                    Button("Voltar") {
                                        withAnimation(.easeInOut) { tutorialStep = max(0, tutorialStep - 1) }
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.white)
                                }

                                Button(tutorialStep == 2 ? "Começar" : "Próximo") {
                                    withAnimation(.easeInOut) {
                                        if tutorialStep < 2 { tutorialStep += 1 } else { explicacao_inicial = false }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(tutorialStep == 2 ? Color("vermelho") : Color("azul"))
                                .foregroundColor(.white)
                            }
                            .font(.headline)
                            .padding(.vertical, 20)

                            Spacer(minLength: 24)
                        }
                    }
                }
            }
            .onPreferenceChange(ViewFrameKey.self) { newValues in
                frames.merge(newValues, uniquingKeysWith: { $1 })
            }
            .onAppear {
                // Verificar se é o primeiro lançamento e mostrar explicação
                if !UserDefaults.standard.bool(forKey: "firstLaunchHasShown") {
                    explicacao_inicial = true
                    tutorialStep = 0
                    UserDefaults.standard.set(true, forKey: "firstLaunchHasShown")
                }
                    
                // Carrega facts somente se ainda não estiverem carregados.
                if gameState.facts.isEmpty {
                    gameState.facts = FactLoader.loadFacts()
                }

                // Agora tenta restaurar o estado salvo. Como facts já estão carregados,
                // a reconstrução de partidaFacts por IDs vai funcionar.
                GamePersistence.load(into: gameState)

                // Se por algum motivo não houve partida salva, inicia uma nova.
                if gameState.partidaFacts.isEmpty {
                    gameState.partida()
                }
            }
            .onDisappear {
                GamePersistence.save(gameState: gameState)
            }
            .navigationTitle("\(gameState.currentIndex + 1)/\(gameState.partidaFacts.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(explicacao_inicial ? Color.black.opacity(0.6) : Color("azul"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        popupAppIntent = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white)
                    }
                    .disabled(explicacao_inicial)
                }
            }
            .toolbarRole(.navigationStack)
    }

    // Computes the rect to highlight for the current tutorial step
    private func highlightRectForCurrentStep(in screen: CGRect) -> CGRect {
        switch tutorialStep {
        case 0:
            return frames["newsArea"] ?? .zero
        case 1:
            return frames["answerButtons"] ?? .zero
        case 2:
            // Prefer skip button; if missing, fall back to answer buttons
            return frames["skipButton"] ?? frames["answerButtons"] ?? .zero
        default:
            return .zero
        }
    }

    // Computes a stable callout position around an anchor rect, respecting safe areas
    private func calloutPosition(anchor: CGRect, screen: CGRect, safe: EdgeInsets) -> CGPoint {
        // Horizontal clamping margins
        let hMargin: CGFloat = 24
        // Vertical spacing between the anchor and the callout
        let vGap: CGFloat = 56
        // Safe area guards
        let minTopY = screen.minY + safe.top + 60
        let maxBottomY = screen.maxY - safe.bottom - 60

        // Available space above and below the anchor
        let availableAbove = anchor.minY - minTopY
        let availableBelow = maxBottomY - anchor.maxY
        let placeAbove = availableAbove > availableBelow

        // X centered on anchor, clamped to margins
        let clampedX = min(max(anchor.midX, screen.minX + hMargin), screen.maxX - hMargin)

        // Y placed above or below with a consistent gap
        let y: CGFloat
        if placeAbove {
            y = max(anchor.minY - vGap, minTopY)
        } else {
            y = min(anchor.maxY + vGap, maxBottomY)
        }

        return CGPoint(x: clampedX, y: y)
    }

    // Verifica se o usuário acertou ou errou
    func checkAnswer(userSaysTrue: Bool) {
        guard let fact = gameState.factAtual else { return }
        let rating = fact.binario
        let isTrue = rating == "true" || rating == "FATO"
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
