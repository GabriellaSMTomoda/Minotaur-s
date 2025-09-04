import SwiftUI
struct GameReportView: View {
    @EnvironmentObject private var gameState: GameState
    @Environment(\.dismiss) private var dismiss
    
    @State private var expandedFactID: UUID? = nil
    
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
            .navigationBarBackButtonHidden(true)
            .toolbar {
                // Botão de voltar customizado sem texto
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.bold)
                        }
                    }
                }
            }
            .toolbarColorScheme(.dark)
            .toolbarBackground(Color("azul"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // Seção de acertos
    var acertosSection: some View {
        VStack{
            HStack{
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
                Text("Acertos")
                    .font(.title2)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.leading)
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
                            motivo: fact.motivo
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
                Image(systemName: "circle.fill")
                    .foregroundColor(.red)
                Text("Erros")
                    .font(.title2)
                    .fontWeight(.medium)
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
                            motivo: fact.motivo
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
                Text("Pulos")
                    .font(.title2)
                    .fontWeight(.medium)
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
                        motivo: fact.motivo
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
    
    @State private var expandedFactID: UUID? = nil
    
    let id: UUID
    let binario: String
    let titulo: String
    let resumo: String
    let motivo: String
    
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
                        Spacer()
                        Text(binario)
                            .foregroundColor(Color("texto"))
                            .frame(minWidth: 120, minHeight: 30, alignment: .center)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color("texto"), lineWidth: 5)
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
                    Text(expandedFactID == id ? "" : "Ver Mais")
                        .foregroundColor(.gray)
                        .frame(width: UIScreen.main.bounds.width * 7/9, alignment: .trailing)
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
                        Spacer(minLength: 38)
                        Text("Explicação:")
                            .foregroundColor(Color("texto"))
                            .frame(width: UIScreen.main.bounds.width * 7/9, alignment: .leading)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    Spacer()
                    Text(motivo)
                        .foregroundColor(Color("texto"))
                        .padding(.horizontal)
                        .padding(.bottom, 12)
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

//
//import SwiftUI
//struct GameReportView: View {
//  @EnvironmentObject private var gameState: GameState
//  @State private var expandedFactID: UUID? = nil
//  var body: some View {
//    NavigationStack {
//      ZStack {
//        Color("background")
//          .ignoresSafeArea()
//        ScrollView {
//          VStack(spacing: 16) {
//            ForEach(gameState.partidaFacts) { fact in
//              VStack(spacing: 0) {
//                HStack(spacing: 0) {
//                  // Linha vertical que se expande
//                  Rectangle()
//                    .fill(corResultado(para: fact.id))
//                    .frame(width: 18)
//                  // Conteúdo principal
//                  VStack(alignment: .leading, spacing: 0) {
//                    ZStack(alignment: .topTrailing) {
//                      // Botão para expandir/recolher
//                      Button(action: {
//                        if expandedFactID == fact.id {
//                          expandedFactID = nil
//                        } else {
//                          expandedFactID = fact.id
//                        }
//                      }) {
//                        HStack {
//                          Text(fact.titulo)
//                            .font(.system(size: 24, weight: .medium))
//                            .foregroundColor(.black)
//                            .padding()
//                            //.frame(maxWidth: .infinity, alignment: .leading)
//                          Spacer()
//                          // Ícone no canto inferior direito
//                          Image(systemName: expandedFactID == fact.id ? "chevron.up" : "chevron.down")
//                            .foregroundColor(.gray)
//                            .padding(.trailing, 16)
//                            .padding(.bottom, 16)
//                        }
//                      }
//                      // Label FATO ou FARSA no canto superior direito
//                      Image(ehVerdadeiro(fact.binario) ? "fato" : "farsa")
//                        .resizable() // ← FALTANDO
//                        .scaledToFit() // ← FALTANDO
//                        .frame(width: 107, height: 57) // Diminui o tamanho
//                        .offset(x: 12, y: 0)
//                    }
//                    // Conteúdo expandido
//                    if expandedFactID == fact.id {
//                      VStack(alignment: .leading, spacing: 8) {
//                        Text("Explicação:")
//                          .font(.system(size: 24, weight: .medium))
//                          .foregroundColor(.black)
//                          .padding(.horizontal)
//                        Text(fact.motivo)
//                          .foregroundColor(.black)
//                          .padding(.horizontal)
//                          .padding(.bottom, 12)
//                      }
//                    }
//                  }
//                }
//              }
//              .background(Color.white)
//              .cornerRadius(12)
//              .overlay(
//                RoundedRectangle(cornerRadius: 12)
//                  .stroke(Color.gray, lineWidth: 0.5)
//              )
//            }
//          }
//          .padding()
//        }
//      }
//      .toolbar {
//        ToolbarItem(placement: .principal) {
//          Text("REVISÃO")
//            .font(.system(size: 32, weight: .bold))
//            .foregroundColor(.white)
//        }
//      }
//      .navigationBarTitleDisplayMode(.inline)
//      .toolbarBackground(Color("azul"), for: .navigationBar)
//      .toolbarBackground(.visible, for: .navigationBar)
//    }
//  }
//  private func ehVerdadeiro(_ binario: String) -> Bool {
//    let rating = binario.lowercased()
//    return rating == "true" || rating == "verdadeiro"
//  }
//  private func corResultado(para factID: UUID) -> Color {
//    if let acertou = gameState.resultados[factID] {
//      return acertou ? Color("verde") : Color("vermelho")
//    }
//    return Color.gray
//  }
//}
//#Preview {
//  GameReportView()
//    .environmentObject(GameState())
//}

