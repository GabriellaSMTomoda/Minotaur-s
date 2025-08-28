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

                VStack {
                    Text("Fato ou Farsa?")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(Color("azul"))
                        .padding()

                    NavigationLink(destination: GameView()) {
                        Text("JOGAR")
                            .font(.title)
                            .bold()
                            .foregroundColor(Color("background"))
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color("azul"))
                            .cornerRadius(20)
                            .padding()
                    }
                    
                    NavigationLink(destination: GameView()) {
                        Text("COMO JOGAR")
                            .font(.title)
                            .bold()
                            .foregroundColor(Color("background"))
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(Color("vermelho"))
                            .cornerRadius(20)
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

