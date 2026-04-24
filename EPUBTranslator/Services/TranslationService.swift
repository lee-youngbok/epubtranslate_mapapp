import Foundation
import Translation

/// Service responsible for translating text using Apple's Translation framework.
/// On macOS 15+, TranslationSession is obtained via the .translationTask SwiftUI modifier.
/// This service is @MainActor to match TranslationSession's isolation.
@available(macOS 15.0, *)
@MainActor
final class TranslationService {

    private var session: TranslationSession?

    /// Set the translation session (obtained from SwiftUI's .translationTask modifier)
    func setSession(_ session: TranslationSession) {
        self.session = session
    }

    /// Check if a session is available
    var hasSession: Bool {
        session != nil
    }

    /// Translate a batch of texts for efficiency
    func translateBatch(
        texts: [String],
        progressHandler: @Sendable @MainActor (Int) -> Void = { _ in }
    ) async throws -> [String] {
        guard let session = self.session else {
            throw TranslationError.noSession
        }
        nonisolated(unsafe) let unsafeSession = session

        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: "\(index)")
        }

        // Use batch translation
        var translatedMap: [String: String] = [:]
        for try await response in unsafeSession.translate(batch: requests) {
            translatedMap[response.clientIdentifier ?? ""] = response.targetText
            progressHandler(translatedMap.count)
        }

        // Reconstruct in order
        var results: [String] = []
        results.reserveCapacity(texts.count)
        for i in 0..<texts.count {
            if let translated = translatedMap["\(i)"] {
                results.append(translated)
            } else {
                results.append(texts[i]) // Fallback to original
            }
        }

        return results
    }

    /// Translate a single text
    func translate(text: String) async throws -> String {
        guard let session = self.session else {
            throw TranslationError.noSession
        }
        nonisolated(unsafe) let unsafeSession = session
        let response = try await unsafeSession.translate(text)
        return response.targetText
    }
}

/// Errors for Translation Service
enum TranslationError: LocalizedError {
    case noSession
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "번역 세션이 초기화되지 않았습니다. Translation 모델이 다운로드되어 있는지 확인하세요."
        case .translationFailed(let reason):
            return "번역 실패: \(reason)"
        }
    }
}

/// Create a Locale.Language from a BCP 47 language code
extension Locale.Language {
    static func fromCode(_ code: String) -> Locale.Language {
        return Locale.Language(identifier: code)
    }
}
