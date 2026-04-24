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
