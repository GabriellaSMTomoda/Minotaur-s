
import Foundation
import NaturalLanguage

/// Reduz a afirmação do usuário à query enviada ao provedor de busca (RF-02.1/RF-02.2).
///
/// A estratégia é a **primeira frase truncada em 200 caracteres** (DT-22). O saco-de-palavras
/// foi testado e descartado: no Spike 5 os vazamentos de domínio se concentraram em buscas
/// dominadas por um termo genérico isolado, e a frase inteira preserva o contexto sintático
/// da afirmação. A restrição por domínio não entra aqui — é o `include_domains` da chamada
/// de busca (RF-02.3), nativo da API.
enum SearchQueryBuilder {

    /// Comprimento máximo da query (RF-02.1/RF-02.2).
    static let maxQueryLength = 200

    /// Query de busca para a afirmação digitada pelo usuário.
    ///
    /// Afirmação com uma frase curta sai inalterada — o limite da RF-01.2 (1.000 caracteres)
    /// é do campo de texto, não da query.
    ///
    /// - Returns: string vazia se a afirmação não tiver conteúdo além de espaços; nesse caso
    ///   não há busca a fazer (a validação de RF-01.2 já bloqueia o botão antes disso).
    static func query(from claim: String) -> String {
        let trimmed = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let sentence = firstSentence(of: trimmed) ?? trimmed
        return truncate(sentence, to: maxQueryLength)
    }

    // MARK: - Segmentação

    /// Primeira frase da afirmação, pelo `NLTokenizer` com idioma fixado em português
    /// (a feature não suporta outros — §5 da spec). Mesma abordagem do `TextChunker`.
    ///
    /// Texto sem pontuação de fim de frase devolve o texto inteiro como frase única — daí o
    /// truncamento adiante ser o que garante o limite, não a segmentação.
    private static func firstSentence(of text: String) -> String? {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.portuguese)
        tokenizer.string = text

        var first: String?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.isEmpty { return true }
            first = sentence
            return false
        }
        return first
    }

    // MARK: - Truncamento

    /// Corta em `limit` caracteres **sem partir palavra ao meio**.
    ///
    /// Cortar no meio de uma palavra produziria um fragmento que o buscador trataria como
    /// termo próprio ("presiden"), justamente o tipo de termo degradado que a DT-22 quis
    /// evitar. Se não houver espaço algum dentro do limite (palavra única gigante), aí sim
    /// corta seco — é o único jeito de respeitar o limite.
    private static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }

        let head = text.prefix(limit)
        guard let lastSpace = head.lastIndex(where: { $0.isWhitespace }) else {
            return String(head)
        }

        let clipped = head[head.startIndex..<lastSpace]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.isEmpty ? String(head) : clipped
    }
}
