// SPIKE 7 — caminho (b), parte 2: QUANTO CUSTA gerar a negação em PT-BR.
//
// O caminho (b) só é implementável se existir uma forma confiável de negar a
// afirmação do usuário **on-device**. Este negador usa exatamente a ferramenta
// que o app teria à mão: `NLTagger` do NaturalLanguage, o mesmo já usado pelo
// `ChunkQualityFilter` e pelo `TextChunker`. Nada de LLM (§5 da spec proíbe),
// nada de serviço de rede (NF-07).
//
// A regra é a mais direta possível, e é de propósito: se nem a regra simples
// funcionar, o custo do caminho (b) deixa de ser "dobrar a inferência" e passa a
// ser "construir um negador de português", que é um projeto por si só.
//
//   1. afirmação já negativa  -> remove a marca de negação (vira afirmativa);
//   2. afirmação afirmativa   -> insere "não" antes do primeiro verbo finito.
//
// Uso (código descartável, não faz parte do app):
//   swift negador.swift ../build/claims.json ../build/negacoes_auto.json

import Foundation
import NaturalLanguage

// MARK: - Entrada/saída

let argumentos = CommandLine.arguments
guard argumentos.count == 3 else {
    FileHandle.standardError.write("uso: negador.swift <claims.json> <saida.json>\n".data(using: .utf8)!)
    exit(2)
}

let entrada = URL(fileURLWithPath: argumentos[1])
let saida = URL(fileURLWithPath: argumentos[2])

guard let dados = try? Data(contentsOf: entrada),
      let claims = try? JSONDecoder().decode([String].self, from: dados)
else {
    FileHandle.standardError.write("não consegui ler \(entrada.path)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Negação

/// Marcas de negação que, se presentes, tornam a afirmação já negativa. Negar uma
/// negativa é removê-las, não empilhar outro "não".
let marcasDeNegacao = ["não", "nao", "nunca", "jamais", "nenhum", "nenhuma", "nada", "ninguém"]

func palavras(_ texto: String) -> [(texto: String, faixa: Range<String.Index>)] {
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.setLanguage(.portuguese, range: texto.startIndex..<texto.endIndex)
    tagger.string = texto

    var resultado: [(String, Range<String.Index>)] = []
    tagger.enumerateTags(
        in: texto.startIndex..<texto.endIndex,
        unit: .word,
        scheme: .lexicalClass,
        options: [.omitWhitespace, .omitPunctuation]
    ) { _, faixa in
        resultado.append((String(texto[faixa]), faixa))
        return true
    }
    return resultado
}

/// Faixa do primeiro verbo finito da afirmação, se houver.
func primeiroVerbo(_ texto: String) -> Range<String.Index>? {
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.setLanguage(.portuguese, range: texto.startIndex..<texto.endIndex)
    tagger.string = texto

    var encontrado: Range<String.Index>?
    tagger.enumerateTags(
        in: texto.startIndex..<texto.endIndex,
        unit: .word,
        scheme: .lexicalClass,
        options: [.omitWhitespace, .omitPunctuation]
    ) { tag, faixa in
        if tag == .verb {
            encontrado = faixa
            return false
        }
        return true
    }
    return encontrado
}

func normalizada(_ palavra: String) -> String {
    palavra.folding(options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "pt_BR"))
}

struct Resultado: Encodable {
    let claim: String
    let negacao: String?
    /// Regra que produziu a saída, para o RESULTADO.md conseguir separar os
    /// modos de falha em vez de reportar só uma taxa agregada.
    let regra: String
}

func negar(_ claim: String) -> Resultado {
    let aparado = claim.trimmingCharacters(in: .whitespacesAndNewlines)
    let temPonto = aparado.hasSuffix(".")
    let corpo = temPonto ? String(aparado.dropLast()) : aparado

    let tokens = palavras(corpo)

    // 1. Já é negativa: remover a marca.
    if let marca = tokens.first(where: {
        marcasDeNegacao.contains(normalizada($0.texto).lowercased())
    }) {
        var resultado = corpo
        resultado.removeSubrange(marca.faixa)
        resultado = resultado
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return Resultado(claim: claim,
                         negacao: resultado + (temPonto ? "." : ""),
                         regra: "remocao-de-negacao")
    }

    // 2. Afirmativa: "não" antes do primeiro verbo finito.
    guard let verbo = primeiroVerbo(corpo) else {
        return Resultado(claim: claim, negacao: nil, regra: "falha-sem-verbo")
    }

    var resultado = corpo
    resultado.insert(contentsOf: "não ", at: verbo.lowerBound)
    return Resultado(claim: claim,
                     negacao: resultado + (temPonto ? "." : ""),
                     regra: "nao-antes-do-verbo")
}

// MARK: - Execução

let resultados = claims.map(negar)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(resultados).write(to: saida)

for r in resultados {
    print("\(r.regra.padding(toLength: 22, withPad: " ", startingAt: 0)) \(r.claim)  ->  \(r.negacao ?? "<FALHOU>")")
}
print("\n-> \(saida.path)")
