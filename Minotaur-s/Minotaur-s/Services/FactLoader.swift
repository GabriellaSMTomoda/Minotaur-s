//
// FactLoader.swift
// Minotaur-s
//
// Created by Gabriella San Martino Tomoda on 19/08/25.
//
import Foundation
class FactLoader {
  static func loadFacts() -> [Fact] {
    guard let url = Bundle.main.url(forResource: "Banco_Dados", withExtension: "tsv"),
       let content = try? String(contentsOf: url, encoding: .utf8) else {
      return []
    }
    var facts: [Fact] = []
    let lines = content.components(separatedBy: "\n")
    // pular a primeira linha (header)
    for line in lines.dropFirst() {
      let columns = line.components(separatedBy: "\t")
      if columns.count >= 9 {
        let fact = Fact(
          url: columns[1],
          fonte: columns[2],
          data: columns[3],
          motivo: columns[4],
          resumo: columns[5],
          titulo: columns[6],
          binario: columns[7],
          assunto: columns[8],
          autor: columns[9]
        )
        facts.append(fact)
      }
    }
    return facts
  }
}
