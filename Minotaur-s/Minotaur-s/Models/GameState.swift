//
// GameState.swift
// Minotaur-s
//
// Created by Gabriella San Martino Tomoda on 19/08/25.

import Foundation
class GameState: ObservableObject {
  @Published var acertos: Int = 0
  @Published var erros: Int = 0
  @Published var pulos: Int = 0
  @Published var currentIndex: Int = 0
  var facts: [Fact] = []       // banco completo (50 notícias)
  @Published var partidaFacts: [Fact] = [] // apenas as 10 escolhidas
  // IDs das notícias usadas na partida
  @Published var partidaIDs: [UUID] = []
  // Inicia uma nova partida
  func partida() {
    resetar()
  }
  // Avança para a próxima notícia
  func nextFact() {
    if currentIndex < partidaFacts.count - 1 {
      currentIndex += 1
    }
  }
  // Reseta o jogo e seleciona 10 notícias aleatórias
  func resetar() {
    acertos = 0
    erros = 0
    pulos = 0
    currentIndex = 0
    // Embaralha o banco completo in-place
    facts.shuffle()
    // Pega as 10 primeiras do shuffle
    partidaFacts = Array(facts.prefix(10))
    // Salva apenas os IDs para referência futura
    partidaIDs = partidaFacts.map { $0.id }
    // Debug: mostrar títulos ou IDs sorteados
    print(":twisted_rightwards_arrows: Notícias sorteadas:")
    partidaFacts.forEach { print($0.id) }
  }
  // Acesso direto ao fato atual
  var factAtual: Fact? {
    guard currentIndex < partidaFacts.count else { return nil }
    return partidaFacts[currentIndex]
  }
}
