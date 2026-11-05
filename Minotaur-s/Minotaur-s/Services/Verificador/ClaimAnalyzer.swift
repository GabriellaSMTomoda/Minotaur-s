import Foundation
import NaturalLanguage

enum ClaimAnalyzer {
    struct Analysis {
        let candidates: [String]
        let needsRephrasing: Bool
    }

    static func analyze(_ input: String) -> Analysis {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.setLanguage(.portuguese)
        tokenizer.string = input
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: input.startIndex..<input.endIndex) { range, _ in
            let sentence = input[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        if sentences.isEmpty { sentences = [input.trimmingCharacters(in: .whitespacesAndNewlines)] }
        let dependent = sentences.contains {
            matches(#"^(ele|ela|eles|elas|isso|isto|esse|essa|esses|essas|por isso|além disso|também)\b"#, in: folded($0))
        }
        // Do not invent subjects to split a conjunction. Ask for an atomic statement.
        let compound = sentences.contains {
            matches(#"\s(?:e|mas|porém|enquanto)\s+(?:a|o|os|as|um|uma)\s+\p{Lu}[\p{L}]+\s"#, in: $0)
        }
        return Analysis(candidates: Array(NSOrderedSet(array: sentences)) as? [String] ?? sentences,
                        needsRephrasing: dependent || compound)
    }

    static func context(for text: String, at date: Date = Date()) -> ClaimContext {
        let lower = folded(text)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let today = calendar.startOfDay(for: date)
        let attribution = matches(#"\b(diz|disse|afirma|afirmou|alega|alegou|segundo|de acordo com)\b"#, in: lower)
        func context(_ kind: ClaimContext.TemporalKind, _ start: Date? = nil, _ end: Date? = nil) -> ClaimContext {
            ClaimContext(text: text, referenceDate: date, temporalKind: kind,
                         startDate: start, endDate: end, containsAttribution: attribution)
        }
        if matches(#"\b(hoje|ontem)\b"#, in: lower) {
            let day = lower.contains("ontem") ? calendar.date(byAdding: .day, value: -1, to: today)! : today
            return context(.recent, day, calendar.date(byAdding: .day, value: 1, to: day))
        }
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})/(20\d{2}|19\d{2})\b"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let d = Range(match.range(at: 1), in: text), let m = Range(match.range(at: 2), in: text),
           let y = Range(match.range(at: 3), in: text),
           let start = calendar.date(from: DateComponents(year: Int(text[y]), month: Int(text[m]), day: Int(text[d]))) {
            return context(.historical, start, calendar.date(byAdding: .day, value: 1, to: start))
        }
        if let range = text.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression),
           let year = Int(text[range]), let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
            return context(.historical, start, calendar.date(byAdding: .year, value: 1, to: start))
        }
        if matches(#"\b(atualmente|atual|agora|e presidente|preside|ocupa o cargo|esta no cargo)\b"#, in: lower) {
            return context(.current, calendar.date(byAdding: .day, value: -30, to: today), date)
        }
        if matches(#"\b(recentemente|nesta semana|esta semana|ultimos dias|acabou de)\b"#, in: lower) {
            return context(.recent, calendar.date(byAdding: .day, value: -7, to: today), date)
        }
        return context(.timeless)
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }
    static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
