import Foundation
import NaturalLanguage

/// Service responsible for detecting languages in text using NaturalLanguage framework
struct LanguageDetector: Sendable {

    /// Detect the dominant language of a given text
    func detectLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Detect language with confidence score
    func detectLanguageWithConfidence(of text: String) -> (language: String, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage else { return nil }

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        let confidence = hypotheses[dominant] ?? 0.0

        return (language: dominant.rawValue, confidence: confidence)
    }

    /// Detect all languages present in a list of text fragments and their approximate distribution
    func detectLanguageDistribution(texts: [String]) -> [DetectedLanguageInfo] {
        var languageCounts: [String: Int] = [:]
        var totalCount = 0

        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count >= 10 else { continue }

            if let lang = detectLanguage(of: trimmed) {
                languageCounts[lang, default: 0] += 1
                totalCount += 1
            }
        }

        guard totalCount > 0 else { return [] }

        return languageCounts.map { code, count in
            let locale = Locale.current
            let displayName = locale.localizedString(forLanguageCode: code) ?? code
            let percentage = Double(count) / Double(totalCount) * 100.0
            return DetectedLanguageInfo(
                languageCode: code,
                displayName: displayName,
                percentage: percentage
            )
        }
        .sorted { $0.percentage > $1.percentage }
    }

    /// Check if a paragraph's language matches the target language
    /// Returns true if the paragraph should be skipped (already in target language)
    func shouldSkipTranslation(paragraph: String, targetLanguageCode: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip very short text (likely not meaningful)
        guard trimmed.count >= 5 else { return true }

        // Check for numeric-only or whitespace-only content
        let stripped = trimmed.replacingOccurrences(of: "[\\d\\s\\p{P}]", with: "", options: .regularExpression)
        guard !stripped.isEmpty else { return true }

        guard let detected = detectLanguage(of: trimmed) else { return false }

        // Normalize language codes for comparison
        // e.g., "zh-Hans" should match "zh-Hans", "ko" matches "ko"
        let normalizedDetected = normalizeLanguageCode(detected)
        let normalizedTarget = normalizeLanguageCode(targetLanguageCode)

        return normalizedDetected == normalizedTarget
    }

    /// Normalize language codes for comparison
    private func normalizeLanguageCode(_ code: String) -> String {
        // Handle common variants
        let lowered = code.lowercased()

        // Map common variants
        switch lowered {
        case "zh", "zh-hans", "zh-cn":
            return "zh-hans"
        case "zh-hant", "zh-tw", "zh-hk":
            return "zh-hant"
        case "pt", "pt-br":
            return "pt-br"
        default:
            // Return base language code
            return lowered.components(separatedBy: "-").first ?? lowered
        }
    }
}
