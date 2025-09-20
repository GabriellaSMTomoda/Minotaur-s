import SwiftUI
struct GameReportView: View {
    
    @EnvironmentObject private var gameState: GameState
    @Environment(\.dismiss) private var dismiss
    
    @State private var expandedFactID: UUID? = nil
    @State private var isNavigationBarHidden: Bool = true
       
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("background")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack() {
                        Spacer(minLength: 15)
                        acertosSection
                        Spacer(minLength: 20)
                        errosSection
                        Spacer(minLength: 20)
                        pulosSection
                    }
                }
            }
            .navigationTitle("Revisão")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(self.isNavigationBarHidden)
            .navigationBarItems(leading:
                Button(action: { dismiss() } ) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.bold)
                    }
                }
            )
            .gesture(DragGesture().onEnded { value in
                if value.translation.width > 70 {
                    self.presentationMode.wrappedValue.dismiss()
                }
            })
            .toolbarColorScheme(.dark)
            .toolbarBackground(Color("azul"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear() {
                self.isNavigationBarHidden = true
            }
            .onDisappear() {
                self.isNavigationBarHidden = false
            }
        }
    }
    
    // Seção de acertos
    var acertosSection: some View {
        VStack{
            HStack{
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title)
                Text("Acertos")
                    .font(.title2)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.leading)
            .accessibilityLabel("ACERTOS")
            .accessibilitySortPriority(0)
            Spacer()
            
            //#####IF nenhum, popup de "0 erros, sem acertos"
            
            ForEach(gameState.partidaFacts) { fact in
                if let acertou = gameState.resultados[fact.id] {
                    if acertou {
                        Card(
                            id: fact.id,
                            binario: fact.binario,
                            titulo: fact.titulo,
                            resumo: fact.resumo,
                            motivo: fact.motivo,
                            fonte: fact.fonte,
                            autor: fact.autor
                        )
                    }
                }
            }
        }
    }
    
    // Seção de erros
    var errosSection: some View {
        VStack{
            HStack{
                Image(systemName: "x.circle.fill")
                    .foregroundColor(.red)
                    .font(.title)
                Text("Erros")
                    .font(.title2)
                    .fontWeight(.medium)
                    .accessibilityLabel("ERROS")
                    .accessibilitySortPriority(1)
                Spacer()
            }
            .padding(.leading)
            Spacer()
            
            ForEach(gameState.partidaFacts) { fact in
                if let acertou = gameState.resultados[fact.id] {
                    if !acertou {
                        Card(
                            id: fact.id,
                            binario: fact.binario,
                            titulo: fact.titulo,
                            resumo: fact.resumo,
                            motivo: fact.motivo,
                            fonte: fact.fonte,
                            autor: fact.autor
                        )
                    }
                }
            }
        }
    }
    
    // Seção de pulos
    var pulosSection: some View {
        VStack{
            HStack{
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
                    .font(.title)
                Text("Pulos")
                    .font(.title2)
                    .fontWeight(.medium)
                    .accessibilityLabel("PULOS")
                    .accessibilitySortPriority(2)
                Spacer()
            }
            .padding(.leading)
            Spacer()
            
            ForEach(gameState.partidaFacts) { fact in
                if gameState.resultados[fact.id] == nil {
                    Card(
                        id: fact.id,
                        binario: fact.binario,
                        titulo: fact.titulo,
                        resumo: fact.resumo,
                        motivo: fact.motivo,
                        fonte: fact.fonte,
                        autor: fact.autor
                    )
                }
            }
        }
    }
    
    private func ehVerdadeiro(_ binario: String) -> Bool {
        let rating = binario/*.lowercased()*/
        return rating == "FATO" || rating == "verdadeiro"
    }
}
#Preview {
    GameReportView()
        .environmentObject(GameState())
}
//----------------------------------------------------------------
struct Card: View {

    @Environment(\.colorScheme) var colorScheme
    @State private var expandedFactID: UUID? = nil
    
    let id: UUID
    let binario: String
    let titulo: String
    let resumo: String
    let motivo: String
    let fonte: String
    let autor: String
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                if expandedFactID == id {
                    expandedFactID = nil
                } else {
                    expandedFactID = id
                }
            }) {
                VStack {
                    Spacer(minLength: 10)
                    HStack(spacing: 0) {
                        Spacer(minLength: 10)
                        Text("Esta notícia é:")
                            .foregroundColor(Color("texto"))
                            .accessibilityLabel("Esta notícia é:")
                            .accessibilitySortPriority(6)
                        Spacer(minLength: 10)
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(binario == "FATO" ? Color("azul") : Color("vermelho"), lineWidth: 10)
                            .frame(maxWidth: 120, minHeight: 30, alignment: .center)
                            .background(binario == "FATO" ? Color("azul") : Color("vermelho"))
                            .overlay(
                                Text(binario)
                                    .foregroundColor(colorScheme == .dark ? Color("texto") : .white)
                                    .fontWeight(.bold)
                                    .accessibilityLabel("\(binario)")
                                    .accessibilitySortPriority(5)
                            )
                        Spacer()
                    }
                    .background(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color("texto"))
                            .offset(y: 10),
                        alignment: .bottom
                    )
                    
                    Text(titulo)
                        .multilineTextAlignment(.leading)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color("texto"))
                        .padding()
                        .frame(width: UIScreen.main.bounds.width * 8/9, alignment: .leading)
                        .accessibilityLabel("Título da notícia: \(titulo)")
                        .accessibilitySortPriority(4)
                    Text(expandedFactID == id ? "" : "Ver Mais")
                        .foregroundColor(.gray)
                        .frame(width: UIScreen.main.bounds.width * 7/9, alignment: .trailing)
                        .accessibilityLabel("Botão Ver Mais")
                        .accessibilityHint("Aperte para ver mais sobre a notícia")
                        .accessibilitySortPriority(3)
                    Spacer()
                }
                .frame(width: UIScreen.main.bounds.width * 8/9)
            }
            
            // Conteúdo expandido
            if expandedFactID == id {
                VStack(spacing: 0) {
                    Spacer(minLength: 10)
                    //                    Text(resumo)
                    //                        .multilineTextAlignment(.leading)
                    //                        .font(.title3)
                    //                        .foregroundColor(Color("texto"))
                    //                        .padding()
                    //                        .frame(width: UIScreen.main.bounds.width * 8/9, alignment: .leading)
                    //                    Spacer()
                    HStack {
                        Spacer(minLength: 22)
                        Text("Fonte: \(fonte)")
                            .foregroundColor(Color("texto"))
                            .frame(width: UIScreen.main.bounds.width * 7/9, alignment: .leading)
                            //.fontWeight(.bold)
                            .accessibilityLabel("Fonte: \(fonte)")
                            .accessibilitySortPriority(0)
                        Spacer()
                    }
                    HStack {
                        Spacer(minLength: 22)
                        Text("Autor: \(autor)")
                            .foregroundColor(Color("texto"))
                            .frame(width: UIScreen.main.bounds.width * 7/9, alignment: .leading)
                            //.fontWeight(.bold)
                            .accessibilityLabel("Autor: \(autor)")
                            .accessibilitySortPriority(1)
                        Spacer()
                    }
                    
                    HStack {
                        Spacer(minLength: 22)
                        Text("Explicação:")
                            .foregroundColor(Color("texto"))
                            .frame(width: UIScreen.main.bounds.width * 7/9, alignment: .leading)
                            .fontWeight(.bold)
                            .accessibilityLabel("EXPLICAÇÃO")
                            .accessibilitySortPriority(2)
                        Spacer()
                    }
                   // Spacer()
                    Text(motivo)
                        .foregroundColor(Color("texto"))
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                        .accessibilityLabel("Motivo pelo qual a notícia é \(binario): \(motivo)")
                        .accessibilitySortPriority(3)
                    Spacer()
                }
                .frame(width: UIScreen.main.bounds.width * 8/9)
            }
        }
        .background(Color("revisao_pop"))
        .cornerRadius(12)
        Spacer(minLength: 10)
    }
}
