import Foundation
import NaturalLanguage

/// Turns a free-form note or prompt into a short title, entirely on-device.
///
/// "Fix the alignment of these buttons and make the hover animation smoother."
///   → "Fix Button Alignment"
///
/// The approach is deliberately small: take the first clause, keep a leading
/// imperative verb, keep the content words (nouns, adjectives, numbers) and
/// reorder "X of Y" into "Y X". Apple's NaturalLanguage framework supplies
/// part-of-speech tags and lemmas, so no model download or network is needed.
public enum TitleGenerator {
    public static let maxWords = 4
    public static let maxLength = 40

    public static func title(for note: String) -> String? {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let line = text.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
        let sentence = stripLeadIns(firstSentence(of: line))
        let clause = firstClause(of: sentence)
        let tokens = tag(clause)
        guard !tokens.isEmpty else { return fallbackTitle(from: sentence) }

        var words: [String] = []
        var rest = tokens[...]
        var hasLeadVerb = false
        if let first = rest.first, isLeadVerb(first) {
            words.append(first.word)
            hasLeadVerb = true
            rest = rest.dropFirst()
        }

        let content = contentWords(Array(rest), dropVerbs: hasLeadVerb)
        words.append(contentsOf: content.prefix(maxWords - 1))

        // A lone verb ("Fix this") says too little; use the opening words instead.
        if words.count < 2 && (hasLeadVerb || words.isEmpty) {
            return fallbackTitle(from: clause.isEmpty ? sentence : clause)
        }
        return finish(words)
    }

    /// "Screenshot 001 — Oct 8, 10:42 PM" (day/month order and clock follow the user's locale).
    public static func sequentialTitle(number: Int, date: Date, locale: Locale = .current) -> String {
        let day = DateFormatter()
        day.locale = locale
        day.setLocalizedDateFormatFromTemplate("MMMd")
        let time = DateFormatter()
        time.locale = locale
        time.dateStyle = .none
        time.timeStyle = .short
        return String(format: "Screenshot %03d — %@, %@", number, day.string(from: date), time.string(from: date))
    }

    // MARK: - Steps

    private struct Token {
        let word: String
        let lower: String
        let lexicalClass: NLTag?
        let lemma: String?
    }

    private static let leadIns: [String] = [
        "please", "pls", "plz", "hey", "hi", "ok", "okay", "so", "also", "now", "then",
        "can you", "could you", "would you", "will you", "can we", "could we",
        "i need you to", "i want you to", "i'd like you to", "i would like you to",
        "i need to", "i want to", "we need to", "we should", "you should", "need to",
        "let's", "lets", "let us", "try to", "help me", "remember to", "make sure to",
        "todo", "to do", "note", "reminder", "prompt", "task",
    ]

    private static let imperativeVerbs: Set<String> = [
        "fix", "add", "remove", "update", "change", "make", "check", "review", "use", "move",
        "create", "implement", "refactor", "replace", "improve", "adjust", "align", "test",
        "debug", "investigate", "compare", "redesign", "clean", "rename", "delete", "show",
        "hide", "set", "increase", "decrease", "reduce", "center", "match", "copy",
        "translate", "explain", "write", "build", "design", "look", "find", "ask", "send",
        "convert", "extract", "summarize", "describe", "analyze", "analyse", "recreate",
        "rebuild", "resize", "restyle", "polish", "simplify", "optimize", "support", "handle",
        "follow", "apply", "swap", "drop", "keep", "turn", "enable", "disable", "connect",
        "document", "draft", "plan", "research", "identify", "list", "label", "tweak",
        "darken", "lighten", "shorten", "lengthen", "split", "merge", "sort", "group",
        "migrate", "upgrade", "install", "configure", "deploy", "verify", "confirm", "port",
        "animate", "style", "reorder", "crop", "export", "import", "share", "email", "call",
        "buy", "book", "read", "watch", "learn", "remember", "save", "track", "audit",
    ]

    /// Verbs that carry no meaning in a title.
    private static let weakVerbs: Set<String> = [
        "is", "are", "was", "were", "be", "been", "being", "am", "look", "looks", "looked",
        "seem", "seems", "seemed", "has", "have", "had", "do", "does", "did", "get", "gets",
        "got", "need", "needs", "want", "wants", "should", "would", "could", "can", "will",
        "may", "might", "must", "shall", "feel", "feels", "go", "goes", "going", "let",
        "mean", "means", "meant", "happen", "happens", "happened", "say", "says", "said",
    ]

    private static let stopWords: Set<String> = [
        "please", "thanks", "thank", "you", "i", "me", "we", "us", "it", "its", "this", "that",
        "these", "those", "something", "thing", "things", "stuff", "screenshot", "screenshots",
        "here", "there", "etc", "the", "a", "an", "my", "our", "your", "their", "some", "any",
        "all", "just", "really", "very", "also", "maybe", "kind", "sort", "bit", "lot",
        "what", "which", "who", "why", "how", "when", "where", "one", "ones",
    ]

    private static let determiners: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "our", "your", "their",
        "its", "his", "her", "all", "some", "each", "every", "both",
    ]

    private static func firstSentence(of text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            result = String(text[range])
            return false
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func stripLeadIns(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            let lower = current.lowercased()
            for lead in leadIns where lower.hasPrefix(lead) {
                let after = lower.dropFirst(lead.count)
                // Only strip whole words ("note:" yes, "notes" no).
                guard let next = after.first, next == " " || next == "," || next == ":" || next == "-" else { continue }
                current = String(current.dropFirst(lead.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,:-"))
                changed = !current.isEmpty
                break
            }
        }
        return current
    }

    private static func firstClause(of text: String) -> String {
        let separators = [",", ";", " and ", " but ", " so that ", " so ", " because ", " then ",
                          " — ", " – ", " - ", " which ", " while ", " since ", " as well as "]
        let lower = text.lowercased()
        var cut = lower.endIndex
        for separator in separators {
            if let range = lower.range(of: separator), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        let offset = lower.distance(from: lower.startIndex, to: cut)
        let prefix = String(text.prefix(offset)).trimmingCharacters(in: .whitespaces)
        // Keep the whole sentence if the cut would leave almost nothing.
        return prefix.split(separator: " ").count >= 2 ? prefix : text
    }

    private static func tag(_ text: String) -> [Token] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        var tokens: [Token] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            let word = String(text[range])
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            tokens.append(Token(word: word, lower: word.lowercased(), lexicalClass: tag, lemma: lemma))
            return true
        }
        return tokens
    }

    private static func isLeadVerb(_ token: Token) -> Bool {
        if imperativeVerbs.contains(token.lower) { return true }
        return token.lexicalClass == .verb && !weakVerbs.contains(token.lower)
    }

    private static func isContent(_ token: Token, dropVerbs: Bool) -> Bool {
        if stopWords.contains(token.lower) { return false }
        switch token.lexicalClass {
        case .noun?, .adjective?, .number?, .otherWord?:
            return true
        case .verb?:
            return !dropVerbs && !weakVerbs.contains(token.lower)
        case nil:
            return token.word.rangeOfCharacter(from: .letters) != nil
        default:
            return false
        }
    }

    private static func isNominal(_ token: Token) -> Bool {
        guard !stopWords.contains(token.lower) else { return false }
        switch token.lexicalClass {
        case .noun?, .adjective?, .number?, .otherWord?: return true
        default: return false
        }
    }

    /// Content words in order, with "alignment of these buttons" rewritten as "button alignment".
    private static func contentWords(_ tokens: [Token], dropVerbs: Bool) -> [String] {
        var result: [String] = []
        var runStart = 0  // start (in `result`) of the current run of adjacent content words
        var index = 0
        while index < tokens.count {
            let token = tokens[index]

            if token.lower == "of", index > 0, isNominal(tokens[index - 1]), runStart < result.count {
                var next = index + 1
                while next < tokens.count, determiners.contains(tokens[next].lower) { next += 1 }
                var phrase: [Token] = []
                while next < tokens.count, isNominal(tokens[next]) {
                    phrase.append(tokens[next])
                    next += 1
                }
                if !phrase.isEmpty {
                    let words = phrase.enumerated().map { offset, token in
                        offset == phrase.count - 1 && token.lexicalClass == .noun ? singular(token) : token.word
                    }
                    result.insert(contentsOf: words, at: runStart)
                    index = next
                    runStart = result.count
                    continue
                }
            }

            // "make the header sticky on scroll": once there's a phrase, a preposition ends it.
            if result.count >= 2, token.lower != "of",
               token.lexicalClass == .preposition || token.lexicalClass == .conjunction {
                break
            }

            // Plural nouns right after a noun are often tagged as verbs ("the API docs").
            let misTaggedNoun = token.lexicalClass == .verb && index > 0 && isNominal(tokens[index - 1])
                && runStart < result.count && !weakVerbs.contains(token.lower)
            if isContent(token, dropVerbs: dropVerbs) || misTaggedNoun {
                result.append(token.word)
            } else {
                runStart = result.count
            }
            index += 1
        }
        return result
    }

    private static func singular(_ token: Token) -> String {
        var base: String
        if let lemma = token.lemma, !lemma.isEmpty {
            base = lemma
        } else if token.lower.hasSuffix("ies") {
            base = String(token.lower.dropLast(3)) + "y"
        } else if token.lower.hasSuffix("s") && !token.lower.hasSuffix("ss") {
            base = String(token.lower.dropLast())
        } else {
            base = token.word
        }
        // Keep the user's capitalisation when the lemma only differs in case.
        if base.lowercased() == token.lower { base = token.word }
        return base
    }

    private static func fallbackTitle(from text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return finish(Array(words.prefix(maxWords)))
    }

    private static func finish(_ words: [String]) -> String? {
        var parts = words.map(titleCase)
        while parts.count > 1, parts.joined(separator: " ").count > maxLength {
            parts.removeLast()
        }
        let title = parts.joined(separator: " ")
        if title.isEmpty { return nil }
        if title.count > maxLength { return String(title.prefix(maxLength - 1)) + "…" }
        return title
    }

    private static func titleCase(_ word: String) -> String {
        // Leave acronyms and mixed-case names alone: "API", "iOS", "SwiftUI", "H1".
        let hasInnerCapital = word.dropFirst().contains { $0.isUppercase }
        if hasInnerCapital || word.contains(where: { $0.isNumber }) { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
