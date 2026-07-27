import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme // Variável de ambiente para detectar o modo claro/escuro

    var body: some View {
        NavigationStack {
            ZStack {
                Color("background")
                    .ignoresSafeArea()

                GeometryReader { geometry in
                    VStack {
                        // Título do app
                        VStack(spacing: 8) {
                            HStack(spacing: 0) {
                                Image("Fato")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: geometry.size.width * 0.18)
                                
                                Text("ato ou")
                                    .font(.system(size: geometry.size.width * 0.13, weight: .bold))
                            }
                            HStack {
                                Image("farsa")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: geometry.size.width * 0.18)
                                
                                Text("arsa")
                                    .font(.system(size: geometry.size.width * 0.13, weight: .bold))
                            }
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.top, geometry.size.height * 0.25) // Coloca o título mais para cima

                        Spacer() // Espaço para empurrar os botões para o centro
                        
                        // Botões
                        VStack(spacing: 20) {
                            NavigationLink(destination: GameView()) {
                                Text("Jogar")
                                    .font(.largeTitle)
                                    .bold()
                                    .foregroundColor(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: geometry.size.height * 0.1)
                                    .background(Color("azul"))
                                    .cornerRadius(20)
                                    .padding(.horizontal, geometry.size.width * 0.1)
                                    .accessibilityLabel("Jogar")
                            }
                            
                            NavigationLink(destination: VerificadorView()) {
                                Text("Verificar Notícia")
                                    .font(.largeTitle)
                                    .bold()
                                    .foregroundColor(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: geometry.size.height * 0.1)
                                    .background(Color("azul"))
                                    .cornerRadius(20)
                                    .padding(.horizontal, geometry.size.width * 0.1)
                                    .accessibilityLabel("Verificador")
                            }
                        }
                        .offset(y:-88)
                        
                        Spacer() // Espaço para centralizar os botões
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
    }
}

#Preview {
    ContentView()
}
