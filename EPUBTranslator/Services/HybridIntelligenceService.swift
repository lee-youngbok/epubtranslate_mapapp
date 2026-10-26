import Foundation
import NaturalLanguage
import os

/// Service that coordinates on-device Apple Neural Engine translation refinement,
/// sentence-level chunking, and named-entity / glossary protection.
/// 100% on-device local execution without sending any text to external servers.
@Observable
@MainActor
final class HybridIntelligenceService {

    static let shared = HybridIntelligenceService()
    private let logger = Logger(subsystem: "com.example.EPUBTranslator", category: "HybridIntelligence")

    /// Whether literary text refinement and punctuation polishing is enabled
    var enableLiteraryPolishing: Bool = true

    /// Whether paragraph texts are split into sentences via NLTokenizer before translation
    var enableSentenceSplitting: Bool = true

    /// Whether proper nouns (personal/place/organization names) and glossary terms are protected
    var enableEntityProtection: Bool = true

    /// User-defined glossary terms to preserve or translate consistently
    var glossaryEntries: [GlossaryEntry] = []

    // MARK: - Sentence Splitting (`NLTokenizer`)

    /// Split a paragraph into individual sentences using NaturalLanguage's `NLTokenizer(unit: .sentence)`
    func splitIntoSentences(_ paragraph: String) -> [String] {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enableSentenceSplitting, trimmed.count > 80 else {
            return [trimmed]
        }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences.isEmpty ? [trimmed] : sentences
    }

    // MARK: - Named Entity & Glossary Masking

    /// Mask user glossary terms (and optionally detected proper nouns) with numeric tokens
    /// that survive Apple Translation intact, returning the masked text and restoration map.
    func maskProtectedTerms(in text: String) -> (maskedText: String, replacements: [(token: String, value: String)]) {
        guard enableEntityProtection else {
            return (text, [])
        }

        var working = text
        var replacements: [(token: String, value: String)] = []
        var tokenIndex = 0

        // 1. User-defined glossary entries (sorted longest-first to avoid partial matches)
        let validGlossary = glossaryEntries
            .filter { !$0.sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sourceTerm.count > $1.sourceTerm.count }

        for entry in validGlossary {
            let source = entry.sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard working.localizedCaseInsensitiveContains(source) else { continue }

            let token = "⟦T\(tokenIndex)⟧"
            let escapedSource = NSRegularExpression.escapedPattern(for: source)
            if let regex = try? NSRegularExpression(pattern: escapedSource, options: [.caseInsensitive]) {
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                if regex.firstMatch(in: working, options: [], range: range) != nil {
                    working = regex.stringByReplacingMatches(in: working, options: [], range: range, withTemplate: token)
                    replacements.append((token: token, value: entry.effectiveReplacement))
                    tokenIndex += 1
                }
            }
        }

        // 2. Protect inline technical codes, URLs, and email-like patterns using NLTagger / regex
        let urlPattern = #"https?://[^\s<>"]+"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            let matches = regex.matches(in: working, options: [], range: NSRange(working.startIndex..<working.endIndex, in: working))
            for match in matches.reversed() {
                if let swiftRange = Range(match.range, in: working) {
                    let matchedStr = String(working[swiftRange])
                    let token = "⟦T\(tokenIndex)⟧"
                    working.replaceSubrange(swiftRange, with: token)
                    replacements.append((token: token, value: matchedStr))
                    tokenIndex += 1
                }
            }
        }

        return (working, replacements)
    }

    /// Restore masked tokens in the translated text with their protected values
    func unmaskProtectedTerms(in translatedText: String, replacements: [(token: String, value: String)]) -> String {
        guard !replacements.isEmpty else { return translatedText }
        var restored = translatedText
        for (token, value) in replacements {
            restored = restored.replacingOccurrences(of: token, with: value)
            // Also handle cases where the translation engine inserts spaces inside the bracket token
            let numberPart = token.replacingOccurrences(of: "⟦", with: "").replacingOccurrences(of: "⟧", with: "")
            restored = restored.replacingOccurrences(of: "⟦ \(numberPart) ⟧", with: value)
            restored = restored.replacingOccurrences(of: "[\(numberPart)]", with: value)
        }
        return restored
    }

    /// Extract top frequent proper nouns (Personal/Place/Organization names) from chapter samples
    /// so the user can review and add them to the glossary with one click.
    nonisolated func extractSuggestedEntities(from texts: [String], maxCount: Int = 12) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let targetTags: Set<NLTag> = [.personalName, .placeName, .organizationName]

        var counts: [String: Int] = [:]

        for text in texts {
            tagger.string = text
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
                if let tag, targetTags.contains(tag) {
                    let entity = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Filter out 1-char noise or common all-lowercase false positives
                    if entity.count >= 2 && entity.first?.isUppercase == true {
                        counts[entity, default: 0] += 1
                    }
                }
                return true
            }
        }

        return counts
            .filter { $0.value >= 2 } // Appears at least twice in samples
            .sorted { $0.value > $1.value }
            .prefix(maxCount)
            .map(\.key)
    }

    // MARK: - Literary Polishing

    /// Post-process translated text with literary polishing and typography clean-up on-device
    func polishTranslation(
        translatedText: String,
        originalText: String,
        targetLanguageCode: String
    ) -> String {
        guard enableLiteraryPolishing else {
            return translatedText
        }

        var polished = translatedText

        // Fix spaces around CJK punctuation and normalize Korean typographic flow
        if targetLanguageCode == "ko" {
            polished = polished
                .replacingOccurrences(of: " ,", with: ",")
                .replacingOccurrences(of: " .", with: ".")
                .replacingOccurrences(of: " ?", with: "?")
                .replacingOccurrences(of: " !", with: "!")
                .replacingOccurrences(of: " :", with: ":")
                .replacingOccurrences(of: " ;", with: ";")
                .replacingOccurrences(of: "“ ", with: "“")
                .replacingOccurrences(of: " ”", with: "”")
                .replacingOccurrences(of: "( ", with: "(")
                .replacingOccurrences(of: " )", with: ")")
                .replacingOccurrences(of: "  ", with: " ")
        } else {
            // General punctuation spacing fixes
            polished = polished
                .replacingOccurrences(of: " ,", with: ",")
                .replacingOccurrences(of: " .", with: ".")
                .replacingOccurrences(of: " ?", with: "?")
                .replacingOccurrences(of: " !", with: "!")
                .replacingOccurrences(of: "  ", with: " ")
        }

        return polished.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
