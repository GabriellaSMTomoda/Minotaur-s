//
//  ChunkQualityFilter.swift
//  Minotaur-s
//
//  Created by Claude Code on 03/08/26.
//

import Foundation
import NaturalLanguage

/// Descarta chunks sem valor proposicional antes que virem premissa do NLI (DT-33).
///
/// **Por que existe.** A investigação pós-Fase 5 encontrou chegando ao NLI premissas como
/// `"Navegue direto pelo app … Por Giulia Vidale — São Paulo 27/04/2023 15h57"`, `"Fim do Mais
/// lidas"` e uma fonte inteira cujo único chunk era o título de um Web Story — que votou
/// `entailment` e entrou na contagem da RF-08.3 como se fosse evidência jornalística. Byline,
/// navegação, legenda e título de página repetem as palavras-chave da afirmação, então pontuam
/// **alto** na similaridade de cosseno (RF-06.5) e passam folgadamente pelo piso da RF-06.7 —
/// o filtro de similaridade não protege contra eles, porque o problema não é o assunto, é a
/// ausência de qualquer proposição verificável.
///
/// **O que este filtro não é.** Correção parcial e de risco zero, nas palavras da própria DT-33:
/// não ataca a causa dominante do risco materializado em 7.1 (o julgamento do modelo em PT-BR),
/// que é objeto do Spike 7. Some ruído da entrada; não conserta o que o NLI faz com uma
/// premissa boa.
///
/// **Postura conservadora, de propósito.** Todo chunk descartado é evidência potencialmente
/// perdida — um falso positivo aqui custa mais caro que deixar passar um pedaço de navegação.
/// Os limiares e padrões abaixo são calibrados para os casos reais observados, não para varrer
/// tudo que pareça suspeito.
enum ChunkQualityFilter {

    /// Comprimento mínimo, em caracteres, do corpo do chunk depois de removido o material de
    /// byline/carimbo/crédito (ver `strippingChrome`).
    ///
    /// 40 fica bem abaixo de um parágrafo real: a RF-06.1 divide por parágrafo, e o menor
    /// parágrafo com proposição dos artigos observados passa de 100 caracteres. Serve para
    /// pegar sobras curtas (`"Fim do Mais lidas"`, `"Imagem do planeta Terra —"`), não para
    /// julgar densidade de conteúdo.
    static let minimumCharacters = 40

    /// Mínimo de palavras, pela mesma razão do comprimento mínimo. Um chunk pode passar dos 40
    /// caracteres com duas palavras longas e ainda não afirmar nada.
    static let minimumWords = 5

    /// Motivo pelo qual um chunk foi descartado. Existe para o teste conseguir afirmar **qual**
    /// regra pegou cada caso real — sem isso, um chunk descartado pelo motivo errado passaria
    /// despercebido.
    enum Rejection: Equatable {
        /// Título de página / de Web Story, não corpo de artigo.
        case pageTitle
        /// Navegação, rodapé, publicidade e afins.
        case navigation
        /// Curto demais depois de removido byline/carimbo/crédito.
        case tooShort
        /// Nenhum verbo — sem verbo não há proposição a confirmar ou contradizer.
        case noVerb
    }

    // MARK: - API

    /// Os chunks que seguem para embeddings e NLI, na ordem original.
    ///
    /// Devolver vazio é um resultado legítimo e esperado: o artigo cujo único chunk era o título
    /// do Web Story sai daqui sem nenhum chunk e, por consequência, **não vira fonte válida** —
    /// é descartado pelo mesmo caminho de uma extração fracassada (RF-05.3), sem abortar a
    /// verificação das demais fontes.
    static func keeping(_ chunks: [String]) -> [String] {
        chunks.filter { rejection(for: $0) == nil }
    }

    /// Linha que é *estrutura da página*, não texto do artigo: título de página e navegação.
    ///
    /// Subconjunto deliberado das regras de `rejection(for:)`, aplicado **por parágrafo, antes
    /// da montagem dos chunks** (`TextChunker`). O motivo é a sobreposição de uma frase da
    /// RF-06.1: uma linha de navegação no meio do artigo não vira só um chunk ruim, ela vaza
    /// como prefixo para o chunk **seguinte**. Filtrar só a saída do chunker faria o parágrafo
    /// legítimo logo abaixo de "Fim do Mais lidas" ser descartado junto — perda de evidência
    /// real, exatamente o que este filtro não pode causar.
    ///
    /// Fora daqui ficam o comprimento mínimo e o verbo: parágrafo curto e legítimo (uma citação
    /// de uma linha) se junta ao contexto anterior pela sobreposição e sobrevive como chunk. É
    /// no chunk montado que essas duas regras fazem sentido.
    static func isStructuralBoilerplate(_ paragraph: String) -> Bool {
        let text = normalizingWhitespace(paragraph)
        return isPageTitle(text) || containsNavigationMarker(text)
    }

    /// `nil` quando o chunk tem valor proposicional; o motivo do descarte caso contrário.
    ///
    /// A ordem das regras é a da DT-33 e importa para o diagnóstico, não para o resultado: um
    /// chunk reprovado por mais de uma regra reporta a primeira.
    static func rejection(for chunk: String) -> Rejection? {
        let text = normalizingWhitespace(chunk)

        if isPageTitle(text) { return .pageTitle }
        if containsNavigationMarker(text) { return .navigation }

        // O corpo é o que sobra depois de tirar byline, carimbo de data/hora e crédito de foto.
        // Medir o chunk cru deixaria passar legenda de imagem só por ela ser comprida.
        let body = strippingChrome(text)

        if body.count < minimumCharacters { return .tooShort }
        if wordCount(body) < minimumWords { return .tooShort }
        if !containsVerb(body) { return .noVerb }

        return nil
    }

    // MARK: - Título de página

    /// Título de página/Web Story em vez de corpo de artigo.
    ///
    /// Dois sinais, ambos vindos do caso real do Web Story da CNN
    /// (`"Title: Torcida do Bahia faz mosaico … | Web Stories CNN Brasil"`):
    /// o prefixo `Title:` com que o `content` da Tavily (fallback da RF-05.3) marca páginas sem
    /// corpo extraível, e o separador ` | ` num texto que não termina em pontuação de frase —
    /// título de página não termina em ponto, parágrafo de artigo quase sempre termina.
    private static func isPageTitle(_ text: String) -> Bool {
        if folded(text).hasPrefix("title:") { return true }

        guard text.contains(" | ") else { return false }
        return !endsWithSentencePunctuation(text)
    }

    private static func endsWithSentencePunctuation(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".!?…".contains(last)
    }

    // MARK: - Navegação e rodapé

    /// Marcadores de navegação/rodapé/publicidade observados nos artigos da allowlist.
    ///
    /// A lista é deliberadamente curta e literal: só entram trechos que **não têm** uso
    /// jornalístico corrente no corpo de uma notícia. `"menu"`, `"siga"`, `"assine"` e
    /// `"publicidade"` soltos ficaram de fora justamente por aparecerem em texto legítimo —
    /// uma matéria sobre o mercado publicitário não pode sumir por causa de uma palavra.
    /// Por isso `"continua depois da publicidade"` entra inteira, e não só o substantivo.
    private static let navigationMarkers = [
        "navegue direto pelo app",
        "mais lidas",
        "leia também",
        "leia mais",
        "veja também",
        "continua depois da publicidade",
        "compartilhe",
        "últimas notícias",
        "pular para o conteúdo",
        "todos os direitos reservados",
        "receba as principais notícias",
        "assine a newsletter",
        "newsletter",
        "clique aqui",
        "web stories",
    ]

    /// Marcadores já normalizados, para não refazer o `folding` a cada chunk.
    private static let foldedNavigationMarkers = navigationMarkers.map(folded)

    private static func containsNavigationMarker(_ text: String) -> Bool {
        let text = folded(text)
        return foldedNavigationMarkers.contains { text.contains($0) }
    }

    // MARK: - Byline, carimbo e crédito

    /// Padrões de byline/carimbo/legenda removidos antes de medir o corpo.
    ///
    /// Removidos em vez de reprovados: um parágrafo real que traga um crédito no fim continua
    /// sendo um parágrafo real, e reprovar o chunk inteiro por causa do crédito descartaria
    /// evidência. Só é reprovado o chunk que, **sem** esse material, não sobra nada — que é o
    /// caso de `"Por Eli Elster* 10/12/2025 04h01 Atualizado Imagem do planeta Terra —
    /// Foto: ESA/NASA"`.
    private static let chromePatterns: [String] = [
        // Byline: "Por " seguido de nome próprio capitalizado, com o asterisco de colaborador.
        // Exige capitalização para não comer "Por causa da chuva, o evento foi adiado".
        #"\bPor\s+\p{Lu}[\p{L}'-]+(?:\s+(?:d[aeo]s?\s+)?\p{Lu}[\p{L}'-]+)*\*?"#,
        // Carimbo de data e de hora: 27/04/2023, 15h57, 04:01.
        #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#,
        #"\b\d{1,2}h\d{2}\b"#,
        #"\b\d{1,2}:\d{2}\b"#,
        // Marcações de publicação que acompanham o carimbo.
        #"\b(?:Atualizado|Publicado)(?:\s+em)?\b"#,
        // Crédito de foto/arte até o fim do chunk: o que vem depois do rótulo é o crédito.
        #"\b(?:Foto|Fotos|Imagem|Imagens|Crédito|Créditos|Arte|Ilustração|Legenda|Reprodução|Divulgação)\s*:.*$"#,
    ]

    private static let chromeExpressions: [NSRegularExpression] = chromePatterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [])
    }

    private static func strippingChrome(_ text: String) -> String {
        var result = text
        for expression in chromeExpressions {
            result = expression.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        return normalizingWhitespace(result)
            .trimmingCharacters(in: CharacterSet(charactersIn: " —–-•|,;:"))
    }

    // MARK: - Verbo

    /// Há ao menos um verbo no texto.
    ///
    /// Sem verbo não há proposição: manchete nominal, byline e legenda são sintagmas, e o NLI
    /// não tem o que confirmar ou contradizer neles. O `NLTagger` roda on-device, com o idioma
    /// fixado em português — a feature não suporta outros (§5 da spec).
    ///
    /// Não é infalível nos dois sentidos, e a calibração leva isso em conta: ele marca `"lidas"`
    /// como verbo em `"Fim do Mais lidas"` (falso negativo desta regra, coberto pelo marcador de
    /// navegação e pelo comprimento mínimo) e não acha verbo nenhum na byline da Giulia Vidale
    /// nem na do Eli Elster (onde acerta). Nenhuma regra sozinha responde por todos os casos.
    private static func containsVerb(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.setLanguage(.portuguese, range: text.startIndex..<text.endIndex)
        tagger.string = text

        var found = false
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, _ in
            if tag == .verb {
                found = true
                return false
            }
            return true
        }
        return found
    }

    // MARK: - Utilidades

    private static func normalizingWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Minúsculas sem acento, para comparar marcador com texto sem depender de como o veículo
    /// escreveu ("Últimas notícias" / "ULTIMAS NOTICIAS").
    private static func folded(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
    }
}
