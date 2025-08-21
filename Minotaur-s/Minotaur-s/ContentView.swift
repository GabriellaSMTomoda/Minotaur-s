//
//  ContentView.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 18/08/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack { // permite navegação
            
            VStack {
                Text("NOME DO APP")
                    .font(.title3)

                NavigationLink(destination: GameView()) {
                    Text("Start")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .padding()
                }
                
                //                NavigationLink(destination: TutorialView()) {
                //                    Text("Tutorial")
                //                        .font(.title)
                //                        .foregroundColor(.white)
                //                        .frame(maxWidth: .infinity, minHeight: 60)
                //                        .background(Color.blue)
                //                        .cornerRadius(10)
                //                        .padding()
                //                }
            }
        }
    }
}

#Preview {
    ContentView()
}



