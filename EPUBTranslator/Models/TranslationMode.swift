import Foundation

/// The three translation modes supported by the app
enum TranslationMode: String, CaseIterable, Identifiable, Sendable {
    case bilingual = "Bilingual"
    case replace = "Replace"
    case annotated = "Annotated"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .bilingual:
            return "원문 뒤에 번역문 삽입 (이중 언어)"
        case .replace:
            return "원문을 번역문으로 교체"
        case .annotated:
            return "번역문 표시, 클릭 시 원문 확인"
        }
    }

    var icon: String {
        switch self {
        case .bilingual: return "text.badge.plus"
        case .replace: return "arrow.left.arrow.right"
        case .annotated: return "text.bubble"
        }
    }
}

/// Language option for the EPUB Table of Contents (목차).
/// The TOC is always written in a single language (either original or translated, never both).
enum TOCLanguageMode: String, CaseIterable, Identifiable, Sendable {
    case original = "Original"
    case translated = "Translated"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original:
            return "원문 목차"
        case .translated:
            return "번역문 목차"
        }
    }

    var description: String {
        switch self {
        case .original:
            return "목차를 원문 언어로 유지합니다"
        case .translated:
            return "목차를 번역문 내용에 맞춰 번역합니다"
        }
    }

    var icon: String {
        switch self {
        case .original:
            return "doc.text"
        case .translated:
            return "character.bubble.fill"
        }
    }

    /// Returns the default TOC language mode for a given translation mode:
    /// - Bilingual (원문 + 번역문): defaults to `.original`
    /// - Replace (번역문 교체) & Annotated (번역문 + 원문 접기): defaults to `.translated`
    static func defaultMode(for translationMode: TranslationMode) -> TOCLanguageMode {
        switch translationMode {
        case .bilingual:
            return .original
        case .replace, .annotated:
            return .translated
        }
    }
}

/// Supported target languages for translation
struct TargetLanguage: Identifiable, Hashable, Sendable {
    let id: String  // BCP 47 language code
    let displayName: String

    static let allLanguages: [TargetLanguage] = [
        TargetLanguage(id: "ko", displayName: "한국어"),
        TargetLanguage(id: "en", displayName: "English"),
        TargetLanguage(id: "ja", displayName: "日本語"),
        TargetLanguage(id: "zh-Hans", displayName: "简体中文"),
        TargetLanguage(id: "zh-Hant", displayName: "繁體中文"),
        TargetLanguage(id: "es", displayName: "Español"),
        TargetLanguage(id: "fr", displayName: "Français"),
        TargetLanguage(id: "de", displayName: "Deutsch"),
        TargetLanguage(id: "pt-BR", displayName: "Português (Brasil)"),
        TargetLanguage(id: "it", displayName: "Italiano"),
        TargetLanguage(id: "ru", displayName: "Русский"),
        TargetLanguage(id: "ar", displayName: "العربية"),
        TargetLanguage(id: "th", displayName: "ไทย"),
        TargetLanguage(id: "vi", displayName: "Tiếng Việt"),
        TargetLanguage(id: "id", displayName: "Bahasa Indonesia"),
    ]
}

/// Represents the current phase of the app workflow
enum AppPhase: Sendable {
    case idle
    case importing
    case analyzing
    case ready
    case translating
    case packaging
    case completed
    case error(String)
}

/// User-defined glossary entry to protect or enforce specific translations for terms/names
struct GlossaryEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    /// Source term in the original text (e.g. "Baker", "Hogwarts")
    var sourceTerm: String
    /// Replacement term in target language; if empty, preserves `sourceTerm` as-is
    var targetTerm: String

    var effectiveReplacement: String {
        let trimmed = targetTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }
}
