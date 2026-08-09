import SwiftUI
struct GameReportView: View {
    
    @EnvironmentObject private var gameState: GameState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                acertosSection
                errosSection
                pulosSection
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Revisão")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color("azul"), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarRole(.navigationStack)
    }

    
    // Seção de acertos
    private var acertosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Acertos", systemImage: "checkmark.circle.fill", tint: .green)
            
            let acertos = gameState.partidaFacts.filter { gameState.resultados[$0.id] == true }
            
            if acertos.isEmpty {
                EmptySectionMessage(message: "Você não acertou nenhuma questão.", systemImage: "")
            } else {
                ForEach(acertos) { fact in
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
    
    // Seção de erros
    private var errosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Erros", systemImage: "x.circle.fill", tint: .red)
            
            let erros = gameState.partidaFacts.filter { gameState.resultados[$0.id] == false }
            
            if erros.isEmpty {
                EmptySectionMessage(message: "Você não errou nenhuma questão.", systemImage: "")
            } else {
                ForEach(erros) { fact in
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
    
    // Seção de pulos
    private var pulosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Pulos", systemImage: "circle.fill", tint: .gray)
            
            let pulos = gameState.partidaFacts.filter { gameState.resultados[$0.id] == nil }
            
            if pulos.isEmpty {
                EmptySectionMessage(message: "Você não pulou nenhuma questão.", systemImage: "")
            } else {
                ForEach(pulos) { fact in
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

#Preview {
    NavigationStack {
        GameReportView()
            .environmentObject(GameState())
    }
}

// Helpers
private struct SectionHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .imageScale(.large)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color("texto"))
            Spacer()
        }
        .padding(.horizontal)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct EmptySectionMessage: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityLabel(message)
    }
}

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
    
    private var isExpanded: Bool { expandedFactID == id }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                expandedFactID = isExpanded ? nil : id
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Esta notícia é:")
                            .foregroundStyle(Color("texto"))
                            .font(.subheadline)
                        Pill(text: binario, isFato: binario == "FATO", colorScheme: colorScheme)
                        Spacer()
                    }
                    
                    Divider()
                    
                    Text(titulo)
                        .multilineTextAlignment(.leading)
                        .font(.headline)
                        .foregroundStyle(Color("texto"))
                    
                    if !isExpanded {
                        Text("Ver mais")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("Mostrar detalhes")
                    }
                }
                .padding(16)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Fonte:")
                            .fontWeight(.semibold)
                        Text(fonte)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color("texto"))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Autor:")
                            .fontWeight(.semibold)
                        Text(autor)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color("texto"))
                    
                    Text("Explicação:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color("texto"))
                        .padding(.top, 4)
                    
                    Text(motivo)
                        .font(.body)
                        .foregroundStyle(Color("texto"))
                    
                    HStack {
                        Spacer()
                        Button {
                            expandedFactID = nil
                        } label: {
                            Text("Ver menos")
                                .font(.footnote)
                                .foregroundStyle(.gray)
                                .accessibilityLabel("Ocultar detalhes")
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct Pill: View {
    let text: String
    let isFato: Bool
    let colorScheme: ColorScheme
    
    var body: some View {
        Text(text)
            .font(.subheadline).bold()
            .foregroundColor(colorScheme == .dark ? Color("texto") : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((isFato ? Color("azul") : Color("vermelho")))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(text)
    }
}
