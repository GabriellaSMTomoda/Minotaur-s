//
//  ContentView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.
//

import SwiftUI
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color("background") 
                    .ignoresSafeArea() // ocupa toda a tela

                VStack(spacing: 15) {
                    Image("icon_app")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: UIScreen.main.bounds.width * 1/2, maxHeight: UIScreen.main.bounds.width * 1/2)
                        .cornerRadius(20)
//                    Text("Fato ou Farsa?")
//                        .font(.system(size: 80, weight: .bold))
//                        .foregroundColor(Color("azul"))
//                        .padding()
//                    Spacer(minLength: 5)

                    NavigationLink(destination: GameView()) {
                        Text("JOGAR")
                            .font(.title)
                            .bold()
                            .foregroundColor(Color("background"))
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .background(Color("azul"))
                            .cornerRadius(22)
                            .padding()
                    }
                    
                    NavigationLink(destination: GameView()) {
                        Text("COMO JOGAR")
                            .font(.title)
                            .bold()
                            .foregroundColor(Color("background"))
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .background(Color("vermelho"))
                            .cornerRadius(22)
                            .padding()
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
        }
    }
}

#Preview {
    ContentView()
}

