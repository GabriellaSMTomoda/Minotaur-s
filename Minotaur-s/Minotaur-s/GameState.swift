//
//  GameState.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 19/08/25.
//

import Foundation

class GameState: ObservableObject {
    @Published var acertos: Int = 0
    @Published var erros: Int = 0
    @Published var pulos: Int = 0
    @Published var currentIndex: Int = 0
    
    var facts: [Fact] = []              // banco completo
    @Published var partidaFacts: [Fact] = [] // apenas as 10 escolhidas
    
    // Novo: IDs das notícias usadas na partida
    @Published var partidaIDs: [UUID] = []
    
    // Inicia uma nova partida
    func partida() {
        resetar()
        
        // embaralha e pega 10 notícias do banco
        partidaFacts = Array(facts.shuffled().prefix(10))
        
        // salva apenas os IDs para referência futura
        partidaIDs = partidaFacts.map { $0.id }
    }
    
    func acertou() {
        acertos += 1
        nextFact()
    }
    
    func errou() {
        erros += 1
        nextFact()
    }
    
    func pulouQuestao() {
        pulos += 1
        nextFact()
    }
    
    func nextFact() {
        if currentIndex < partidaFacts.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = 0
//            print("Fim da partida! IDs jogados: \(partidaIDs)")
        }
    }
    
    func resetar() {
        acertos = 0
        erros = 0
        pulos = 0
        currentIndex = 0
        partidaIDs = []
    }
}

