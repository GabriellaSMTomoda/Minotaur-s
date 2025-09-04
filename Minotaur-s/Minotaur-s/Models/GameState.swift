//
// GameState.swift
// Minotaur-s
//
// Created by Gabriella San Martino Tomoda on 19/08/25.
//
import Foundation
class GameState: ObservableObject {
  @Published var acertos: Int = 0
  @Published var erros: Int = 0
  @Published var pulos: Int = 0
  @Published var currentIndex: Int = 0
  var facts: [Fact] = []    // banco completo
  @Published var partidaFacts: [Fact] = [] // apenas as 10 escolhidas
  @Published var partidaIDs: [UUID] = []
  @Published var resultados: [UUID: Bool] = [:]  //armazena se acertou por ID
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
  resultados = [:]
  // Embaralha o banco completo in-place
  facts.shuffle()
  // Pega as 10 primeiras do shuffle
  partidaFacts = Array(facts.prefix(10))
  // Salva apenas os IDs para referência futura
  partidaIDs = partidaFacts.map { $0.id }
  partidaFacts.forEach { print($0.id) }
 }
  func registrarResultado(para factID: UUID, acertou: Bool) {
      resultados[factID] = acertou
    }
 // Acesso ao fato atual
 var factAtual: Fact? {
  guard currentIndex < partidaFacts.count else { return nil }
  return partidaFacts[currentIndex]
 }
}
// salvar game state
