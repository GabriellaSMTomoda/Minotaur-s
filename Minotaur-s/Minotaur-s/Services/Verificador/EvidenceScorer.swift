import Foundation

/// Rules of the evidence v3 policy. They were tuned on the development set
/// (`evaluation/data/dev_claims.jsonl`, not gold) with the offline harness in
/// `evaluation/harness/evidence.py`, which is the reference implementation: keep both in sync.
/// This is **not** a calibration; `EvidencePolicy.calibrated` stays false.
struct EvidenceRules: Sendable {
    var version = "evidence-v3-dev"
    var premisesPerArticle = 4
    var minimumSentenceSimilarity = 0.30
    var supportMinimumProbability = 0.60
    var supportMinimumMargin = 0.30
    var supportMinimumCoverage = 0.50
    var supportWithoutAnchorProbability = 0.97
    var refuteMinimumProbability = 0.70
    var refuteMinimumMargin = 0.40
    var refuteMinimumSimilarity = 0.45
    var numericMismatchMinimumContradiction = 0.40
    var explicitNegationBoost = 1.3
    var mixedMinimum = 0.90
    var partialWeight = 0.5
    var divergenceRatio = 0.6
    var divergenceMinimumSide = 0.9
    var divergenceMinimumOrigins = 2
    var balancedRatio = 0.85
    var rankMismatchScore = 0.8
    var debunkedReportScore = 0.8
    var singleOriginMinimum = 0.85
    var decideMinimum = 0.6
    func weight(for kind: TrustedDomain.Kind) -> Double {
        switch kind {
        case .encyclopedia, .primary: return 1.0
        case .factCheck: return 1.1
        case .journalism: return 0.8
        }
    }
    static let `default` = EvidenceRules()
}

/// Lexical features of the claim that every passage is checked against.
struct ClaimFeatures: Sendable, Equatable {
    let text: String
    let terms: [String]
    let names: [String]
    let nonNameTerms: [String]
    let anchors: [String]
    let numbers: [String]

    /// - Parameter rarity: higher = more specific word (XLM-R unigram surprisal). When it is
    ///   unavailable, longer words are treated as more specific.
    init(claim: String, rarity: ((String) -> Double?)? = nil) {
        text = claim
        let allTerms = EvidenceScorer.contentTerms(claim)
        let keys = EvidenceScorer.keyTerms(claim)
        let nameTerms = keys.filter { !$0.allSatisfy(\.isNumber) }
        terms = allTerms
        names = nameTerms
        nonNameTerms = allTerms.filter { term in !term.allSatisfy(\.isNumber) && !nameTerms.contains(term) }
        numbers = EvidenceScorer.numbers(claim)
        var candidates: [(String, Double)] = []
        for word in EvidenceScorer.words(claim) {
            let folded = ClaimAnalyzer.folded(word)
            guard !EvidenceScorer.stopwords.contains(folded), folded.count >= 3, !folded.allSatisfy(\.isNumber),
                  !keys.contains(folded), !candidates.contains(where: { $0.0 == folded }) else { continue }
            candidates.append((folded, rarity?(word.lowercased()).flatMap { $0 } ?? Double(word.count)))
        }
        anchors = candidates.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
    }
}

/// Decides whether one NLI passage is usable evidence for or against the claim.
///
/// The NLI model alone labels "same frame, different fact" as contradiction (a sentence about
/// pasta production "contradicts" a claim about coffee). A passage only votes when it is about
/// the claim: same subject with a conflicting attribute, or the same complete predicate with
/// another subject (superlatives and unique roles), or the same entities with another number.
enum EvidenceScorer {
    struct PassageScore: Equatable {
        var support = 0.0
        var refute = 0.0
        var reasons: [String] = []
        var coverage = 0.0
        var names = 0.0
        var reported = false
    }

    static let stopwords: Set<String> = Set("""
    a o as os um uma uns umas de da do das dos em na no nas nos por pela pelo pelas pelos para pra com sem sob \
    sobre entre ate até e ou mas que se ao aos à às é ser foi são era eram está estão esta este isso isto essa esse \
    seu sua seus suas lhe lhes já não nao mais muito muita também tambem como quando onde qual quais quem cujo cuja \
    há ha tem têm ter sido pode podem vai vão
    """.split(whereSeparator: \.isWhitespace).map { ClaimAnalyzer.folded(String($0)) })

    private static let debunk = try! NSRegularExpression(pattern: #"\b(e falso|falso que|nao e verdade|e fake|fake news|boato|enganos[oa]|desinformacao|mentira|desmente|desmentiu|nao procede|sem comprovacao|nao ha evidencias?|teoria da conspiracao|checagem|#fake|e #fake|e mito|mito que|desmentid[oa]s?|enganam|diferentemente do que|informacao falsa|noticia falsa|nao e capaz de|nao existem? evidencias?)\b"#)
    /// Sentences that report what circulates (a hoax quoted by a fact-check) do not assert it.
    private static let reportedClaim = try! NSRegularExpression(pattern: #"\b(circula(m|ram|va)?|circulou|viraliz\w*|nas redes|redes sociais|post(s|agens?)? (que|com)|publica(cao|coes) (que|nas|com)|alegacao|legenda|video que|mensage(m|ns) que|corrente|promete(m)?|trabalho de verificacao|teorias? da conspiracao|acredita(m)? que|quem acredita|terraplanistas?|segundo (o|a)s? (boatos?|posts?|publicac\w+)|usuarios? (afirma|compartilha)\w*)\b"#)
    private static let hedge = try! NSRegularExpression(pattern: #"\b(pode|podem|poderia|poderiam|talvez)\s+nao\b"#)
    /// Superlative claim vs. ranked passage: "7º maior produtor" refutes "o maior produtor".
    private static let superlative = try! NSRegularExpression(pattern: #"\b(o|a|os|as) (maior|menor|mais|melhor|pior|primeir[oa]|unic[oa])\b"#)
    private static let ranked = try! NSRegularExpression(pattern: #"(\b\d{1,2}\s?[ºª°o]|\b(segund|terceir|quart|quint|sext|setim|oitav|non|decim)[oa]s?\b)\s*(\w+\s){0,3}?(maior|menor|mais|melhor|pior|posicao|lugar|coloca)"#)
    /// Boilerplate that leaks names into passages ("Agência Brasil", photo credits, breadcrumbs).
    private static let boilerplate: [NSRegularExpression] = [
        #">>\s*Siga o canal.*$"#, #"\s*[—-]\s*Foto:.*$"#, #"Foto:\s*[^.]*?/\s*Agência Brasil"#, #"^PUBLICIDADE\s*"#,
        #"^(Página Inicial|Home)\s*».*?»\s*[^»]*?(?=[A-ZÀ-Ú][a-zà-ú]+ (é|foi|são|tem)\b)"#,
        #"\s*\|\s*(G1|Agência de Notícias|Agência Brasil)\s*$"#, #"\s+-\s+Portal Gov\.br\s*$"#, #"^Oferecido por\s+"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    /// Capitalized sentence starters that are not a competing subject.
    static let starters: Set<String> = Set("""
    outro outra outros outras ele ela eles elas segundo quando apesar hoje veja confira ainda assim porem contudo \
    entretanto alem desde durante enquanto embora depois antes agora entao tambem cada todo toda todos todas muitos \
    muitas alguns algumas este esta estes estas esse essa esses essas aquele aquela nesta neste nessa nesse por fim \
    leia saiba entenda
    """.split(whereSeparator: \.isWhitespace).map(String.init))
    private static let negation = try! NSRegularExpression(pattern: #"\b(nao|nunca|jamais|nem|nenhum|nenhuma)\b"#)
    private static let option = try! NSRegularExpression(pattern: #"^\(?[A-Ea-e1-5][).]\s"#)
    private static let number = try! NSRegularExpression(pattern: #"\b\d+(?:[.,]\d+)?\b"#)
    private static let word = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)

    static func words(_ text: String) -> [String] { matches(word, in: text) }
    static func numbers(_ text: String) -> [String] { matches(number, in: text) }

    static func contentTerms(_ text: String) -> [String] {
        var seen = Set<String>()
        return HybridRetrieval.terms(text).filter { term in
            guard !stopwords.contains(term), term.count >= 3 || term.allSatisfy(\.isNumber) else { return false }
            return seen.insert(term).inserted
        }
    }

    /// Capitalized words after the first one, numbers, and the first word when it is a name.
    static func keyTerms(_ claim: String) -> [String] {
        let tokens = words(claim)
        var keys: [String] = []
        for (index, token) in tokens.enumerated() {
            let isName = token.first?.isUppercase == true
            if (index > 0 && isName) || token.allSatisfy(\.isNumber)
                || (index == 0 && isName && !stopwords.contains(ClaimAnalyzer.folded(token))) {
                let folded = ClaimAnalyzer.folded(token)
                if !keys.contains(folded) { keys.append(folded) }
            }
        }
        return keys
    }

    static func debunks(_ text: String) -> Bool { contains(debunk, ClaimAnalyzer.folded(text)) }
    static func negates(_ text: String) -> Bool { contains(negation, ClaimAnalyzer.folded(text)) }

    static func cleanPremise(_ text: String) -> String {
        boilerplate.reduce(text) { current, regex in
            regex.stringByReplacingMatches(in: current, range: NSRange(current.startIndex..., in: current), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// Capitalized passage tokens that are not names of the claim (another subject).
    static func competitorNames(_ text: String, names: [String]) -> [String] {
        words(text).compactMap { word in
            let folded = ClaimAnalyzer.folded(word)
            guard word.first?.isUppercase == true, folded.count >= 3, !names.contains(folded),
                  !stopwords.contains(folded), !starters.contains(folded) else { return nil }
            return folded
        }
    }

    /// The claim's subject (first name) appears before its predicate in the passage.
    static func subjectFirst(_ features: ClaimFeatures, in text: String) -> Bool {
        guard let subject = features.names.first, !features.anchors.isEmpty else { return true }
        let tokens = HybridRetrieval.terms(text)
        guard let position = tokens.firstIndex(of: subject) else { return false }
        let anchorStems = Set(features.anchors.map(stem))
        guard let first = tokens.indices.first(where: { anchorStems.contains(stem(tokens[$0])) }) else { return true }
        return position < first
    }

    static func stem(_ term: String) -> String {
        term.count > 5 && !term.allSatisfy(\.isNumber) ? String(term.prefix(5)) : term
    }

    static func coverage(_ terms: [String], in passage: String) -> Double {
        guard !terms.isEmpty else { return 0 }
        let stems = Set(HybridRetrieval.terms(passage).map(stem))
        return Double(terms.filter { stems.contains(stem($0)) }.count) / Double(terms.count)
    }

    /// Exact folded match: "Brasil" must not match "brasileiro" nor "Brasília".
    static func nameCoverage(_ names: [String], in passage: String) -> Double {
        guard !names.isEmpty else { return 1 }
        let tokens = Set(HybridRetrieval.terms(passage))
        return Double(names.filter { tokens.contains($0) }.count) / Double(names.count)
    }

    /// Questions and multiple-choice options do not assert anything.
    static func isAssertion(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " \"”»'"))
        return trimmed.count >= 25 && !trimmed.hasSuffix("?") && !contains(option, sentence)
    }

    static func numericMismatch(_ features: ClaimFeatures, passage: String) -> Bool {
        guard !features.numbers.isEmpty else { return false }
        let found = numbers(passage)
        for value in features.numbers where !found.contains(value) {
            let isYear = value.count == 4
            if found.contains(where: { $0.count == value.count && (!isYear || ["18", "19", "20"].contains(String($0.prefix(2)))) }) {
                return true
            }
        }
        return false
    }

    static func score(_ passage: EvidencePassage, features: ClaimFeatures, rules: EvidenceRules = .default) -> PassageScore {
        let p = passage.probabilities, text = passage.text
        let folded = ClaimAnalyzer.folded(text)
        let cover = coverage(features.terms, in: text)
        let names = nameCoverage(features.names, in: text)
        let anchors = features.anchors.isEmpty ? 1 : coverage(features.anchors, in: text)
        let nonName = features.nonNameTerms.isEmpty ? 0 : coverage(features.nonNameTerms, in: text)
        let passageNumbers = numbers(text)
        let numbersPresent = features.numbers.allSatisfy(passageNumbers.contains)
        let debunks = contains(debunk, folded)
        let reported = contains(reportedClaim, folded)
        let foldedClaim = ClaimAnalyzer.folded(features.text)
        let rankMismatch = contains(superlative, foldedClaim) && !contains(ranked, foldedClaim) && contains(ranked, folded)
        let negated = contains(negation, folded) && !contains(negation, ClaimAnalyzer.folded(features.text))
        var result = PassageScore(coverage: cover, names: names, reported: reported)

        if p.entailment >= rules.supportMinimumProbability, p.entailment - p.contradiction >= rules.supportMinimumMargin,
           cover >= rules.supportMinimumCoverage, names == 1, numbersPresent,
           anchors > 0 || p.entailment >= rules.supportWithoutAnchorProbability {
            if debunks { result.reasons.append("support_blocked_debunk") }
            else if reported { result.reasons.append("support_blocked_reported") }
            else if rankMismatch { result.reasons.append("support_blocked_ranked") }
            else { result.support = p.entailment }
        }

        // Direct denial: the same names and most of the claim's words, negated.
        let directDenial = names == 1 && numbersPresent && negated && cover >= 0.6 && !contains(hedge, folded)
        let sameSubject = (names == 1 && numbersPresent && (anchors == 1 || features.nonNameTerms.count <= 2)
            && (subjectFirst(features, in: text) || negated)) || directDenial
        let samePredicate = names < 1 && numbersPresent && !features.nonNameTerms.isEmpty && nonName == 1
            && !competitorNames(text, names: features.names).isEmpty
        let nliRefutes = p.contradiction >= rules.refuteMinimumProbability
            && p.contradiction - p.entailment >= rules.refuteMinimumMargin
            && passage.similarity >= rules.refuteMinimumSimilarity
        let mismatch = !features.numbers.isEmpty && !numbersPresent && names == 1
            && coverage(features.terms.filter { !$0.allSatisfy(\.isNumber) }, in: text) >= 1
            && numericMismatch(features, passage: text)
        if nliRefutes && (sameSubject || samePredicate) {
            result.refute = p.contradiction
            result.reasons.append(sameSubject ? "same_subject" : "same_predicate")
            if sameSubject && negated && !contains(hedge, folded) {
                result.refute *= rules.explicitNegationBoost
                result.reasons.append("explicit_negation")
            }
        } else if mismatch && p.contradiction >= rules.numericMismatchMinimumContradiction {
            result.refute = max(p.contradiction, 0.75)
            result.reasons.append("numeric_mismatch")
        } else if debunks && sameSubject && p.entailment < 0.5 && cover >= 0.6 {
            result.refute = 0.7
            result.reasons.append("debunk_marker")
        } else if rankMismatch && names == 1 && coverage(features.nonNameTerms, in: text) >= 0.5 && p.entailment >= 0.5 {
            result.refute = rules.rankMismatchScore
            result.reasons.append("rank_mismatch")
        }
        return result
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
    private static func contains(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
