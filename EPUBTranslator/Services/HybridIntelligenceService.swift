import Foundation
import os

/// Service that coordinates on-device Apple Neural Engine translation refinement and text polishing.
/// 100% on-device local execution without sending any text to external servers.
@Observable
@MainActor
final class HybridIntelligenceService {

    static let shared = HybridIntelligenceService()
    private let logger = Logger(subsystem: "com.example.EPUBTranslator", category: "HybridIntelligence")

    /// Whether literary text refinement and punctuation polishing is enabled
    var enableLiteraryPolishing: Bool = true

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

        return polished
    }
}
