//
//  GamePersistence.swift
//  Minotaur-s
//
//  Created by Gabriella San Martino Tomoda on 24/08/25.
//

import Foundation

struct GamePersistence {
    private static let saveKey = "SavedGameState"

    /// Estrutura simplificada só com os dados que precisamos salvar
    struct SavedData: Codable {
        var acertos: Int
        var erros: Int
        var pulos: Int
        var currentIndex: Int
        var partidaIDs: [UUID]
    }
    
    /// Salva os dados do GameState no UserDefaults
    static func save(gameState: GameState) {
        let data = SavedData(
            acertos: gameState.acertos,
            erros: gameState.erros,
            pulos: gameState.pulos,
            currentIndex: gameState.currentIndex,
            partidaIDs: gameState.partidaIDs
        )
        
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    /// Carrega os dados salvos, se existirem
    static func load(into gameState: GameState) {
        guard let savedData = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode(SavedData.self, from: savedData) else {
            return
        }
        
        // Restaura o progresso
        gameState.acertos = decoded.acertos
        gameState.erros = decoded.erros
        gameState.pulos = decoded.pulos
        gameState.currentIndex = decoded.currentIndex
        
        // Reconstrói a lista de fatos da partida
        gameState.facts = FactLoader.loadFacts()
        gameState.partidaFacts = gameState.facts.filter { decoded.partidaIDs.contains($0.id) }
        gameState.partidaIDs = decoded.partidaIDs
    }
    
    /// Apaga o progresso salvo (quando reiniciar partida)
    static func clear() {
        UserDefaults.standard.removeObject(forKey: saveKey)
    }
}

