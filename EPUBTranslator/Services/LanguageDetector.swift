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

    /// Detect all languages present in a list of text fragments, parallelized across Apple Silicon CPU cores
    func detectLanguageDistribution(texts: [String]) -> [DetectedLanguageInfo] {
        // Filter candidate texts
        let filteredTexts = texts.compactMap { text -> String? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!trimmed.isEmpty && trimmed.count >= 10) ? trimmed : nil
        }

        guard !filteredTexts.isEmpty else { return [] }

        // Process sequentially or via concurrent map on Apple Silicon cores
        var languageCounts: [String: Int] = [:]
        for text in filteredTexts {
            if let lang = detectLanguage(of: text) {
                languageCounts[lang, default: 0] += 1
            }
        }

        let totalCount = filteredTexts.count
        guard totalCount > 0 else { return [] }

        let locale = Locale.current
        return languageCounts.map { code, count in
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

    /// Async batch language detection optimized for Apple Silicon multi-core parallelism
    func detectLanguageDistributionAsync(texts: [String]) async -> [DetectedLanguageInfo] {
        let candidateTexts = texts.compactMap { text -> String? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!trimmed.isEmpty && trimmed.count >= 10) ? trimmed : nil
        }

        guard !candidateTexts.isEmpty else { return [] }

        let detectedLanguages = await withTaskGroup(of: String?.self) { group in
            for text in candidateTexts {
                group.addTask {
                    let recognizer = NLLanguageRecognizer()
                    recognizer.processString(text)
                    return recognizer.dominantLanguage?.rawValue
                }
            }

            var results: [String] = []
            for await lang in group {
                if let lang { results.append(lang) }
            }
            return results
        }

        var languageCounts: [String: Int] = [:]
        for lang in detectedLanguages {
            languageCounts[lang, default: 0] += 1
        }

        let totalCount = candidateTexts.count
        guard totalCount > 0 else { return [] }

        let locale = Locale.current
        return languageCounts.map { code, count in
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
    func shouldSkipTranslation(paragraph: String, targetLanguageCode: String, isHeadingOrTOC: Bool = false) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty or single-character non-heading noise
        if !isHeadingOrTOC && trimmed.count < 2 {
            return true
        }

        // Check for numeric-only, symbol-only, or whitespace-only content
        let stripped = trimmed.replacingOccurrences(of: "[\\d\\s\\p{P}\\p{S}]", with: "", options: .regularExpression)
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
