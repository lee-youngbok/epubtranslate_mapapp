import SwiftUI
import Foundation
import Translation
import NaturalLanguage
import SwiftSoup
import os

/// Main ViewModel for the EPUB Translator app
@available(macOS 15.0, *)
@Observable
@MainActor
final class TranslatorViewModel {

    // MARK: - Published State

    /// Current app phase
    var appPhase: AppPhase = .idle

    /// Loaded EPUB book
    var book: EPUBBook?

    /// Selected translation mode
    var translationMode: TranslationMode = .bilingual

    /// Selected target language (default: Korean)
    var targetLanguageCode: String = "ko"

    /// Dynamically loaded available languages
    var availableLanguages: [TargetLanguage] = TargetLanguage.allLanguages

    /// Whether file importer sheet is shown
    var showFileImporter = false

    /// Whether file exporter sheet is shown
    var showFileExporter = false

    /// Whether all chapters are selected
    var allChaptersSelected = true

    // MARK: - Progress State

    /// Current chapter being translated
    var currentChapterTitle: String = ""

    /// Overall progress (chapters completed)
    var completedChapters: Int = 0

    /// Total chapters to translate
    var totalChaptersToTranslate: Int = 0

    /// Current chapter's paragraph progress (0.0 - 1.0)
    var currentChapterProgress: Double = 0.0

    /// Status message for the UI
    var statusMessage: String = ""

    /// Whether a cancellation has been requested
    var cancellationRequested = false

    /// The packaged EPUB data for export
    var exportedEPUBData: Data?

    /// URL of the exported file
    var exportedFileURL: URL?

    /// Translation configuration trigger for .translationTask
    var translationConfig: TranslationSession.Configuration?

    // MARK: - Services

    let networkMonitor = NetworkMonitor.shared
    var hybridService = HybridIntelligenceService.shared
    private let logger = Logger(subsystem: "com.example.EPUBTranslator", category: "TranslatorViewModel")

    private let epubParser = EPUBParser()
    private let languageDetector = LanguageDetector()
    let translationService = TranslationService()
    private let htmlProcessor = HTMLProcessor()
    private let epubPackager = EPUBPackager()

    // MARK: - Initialization

    init() {
        Task {
            await loadSupportedLanguages()
        }
    }

    private func loadSupportedLanguages() async {
        let languages = await fetchLanguages()
        
        let mapped = languages.map { lang -> TargetLanguage in
            let id = lang.minimalIdentifier
            let locale = Locale(identifier: "ko_KR")
            let name = locale.localizedString(forLanguageCode: id) ?? id
            return TargetLanguage(id: id, displayName: name)
        }.sorted { $0.displayName < $1.displayName }

        if !mapped.isEmpty {
            self.availableLanguages = mapped
        }
    }

    nonisolated private func fetchLanguages() async -> [Locale.Language] {
        let availability = LanguageAvailability()
        return await availability.supportedLanguages
    }

    // MARK: - Computed Properties

    var selectedChaptersCount: Int {
        book?.chapters.filter(\.isSelected).count ?? 0
    }

    var targetLanguageDisplayName: String {
        availableLanguages.first(where: { $0.id == targetLanguageCode })?.displayName ?? targetLanguageCode
    }

    var isReadyToTranslate: Bool {
        book != nil && selectedChaptersCount > 0
    }

    var progressFraction: Double {
        guard totalChaptersToTranslate > 0 else { return 0 }
        let chapterContribution = Double(completedChapters) / Double(totalChaptersToTranslate)
        let withinChapter = currentChapterProgress / Double(totalChaptersToTranslate)
        return chapterContribution + withinChapter
    }

    // MARK: - File Import

    /// Handle an imported EPUB file URL
    func importEPUB(url: URL) async {
        appPhase = .importing
        statusMessage = "EPUB 파일을 읽는 중..."

        do {
            // Clean up any previous session files before importing a new one
            if let oldExtractedPath = book?.extractedPath {
                try? FileManager.default.removeItem(at: oldExtractedPath)
            }
            if let oldExportedURL = exportedFileURL {
                try? FileManager.default.removeItem(at: oldExportedURL)
            }

            // Access security-scoped resource if available
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Copy to temp location for processing
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)

            appPhase = .analyzing
            statusMessage = "EPUB 구조를 분석하는 중..."

            // Parse the EPUB (extracts chapter titles, paragraph counts, and sample texts in one pass)
            var parsedBook = try await epubParser.parseEPUB(at: tempURL)

            statusMessage = "언어를 감지하는 중..."

            // Detect languages across all chapters using already extracted sampleTexts
            let allTexts = parsedBook.chapters.flatMap { $0.sampleTexts.prefix(10) }
            let detectedLanguages = await languageDetector.detectLanguageDistributionAsync(texts: allTexts)
            parsedBook.detectedLanguages = detectedLanguages

            // Detect per-chapter languages from sampleTexts
            for i in 0..<parsedBook.chapters.count {
                let combined = parsedBook.chapters[i].sampleTexts.joined(separator: " ")
                if !combined.isEmpty {
                    parsedBook.chapters[i].detectedLanguage = languageDetector.detectLanguage(of: combined)
                }
            }

            self.book = parsedBook
            self.allChaptersSelected = true
            self.translationConfig = nil
            appPhase = .ready
            statusMessage = "분석 완료! 번역할 챕터를 선택하세요."

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

        } catch {
            appPhase = .error("EPUB 파싱 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Chapter Selection

    func toggleAllChapters() {
        guard var book = self.book else { return }
        allChaptersSelected.toggle()
        for i in 0..<book.chapters.count {
            book.chapters[i].isSelected = allChaptersSelected
        }
        self.book = book
    }

    func toggleChapter(id: UUID) {
        guard var book = self.book else { return }
        if let index = book.chapters.firstIndex(where: { $0.id == id }) {
            book.chapters[index].isSelected.toggle()
            allChaptersSelected = book.chapters.allSatisfy(\.isSelected)
            self.book = book
        }
    }

    // MARK: - Translation

    /// Trigger the translation by setting the configuration (triggers .translationTask)
    func requestTranslation() {
        let targetLang = Locale.Language(identifier: targetLanguageCode)
        
        // 가장 비중이 높은 감지된 언어를 출발 언어로 설정
        let dominantLangCode = book?.detectedLanguages.first?.languageCode ?? "en"
        
        if dominantLangCode == targetLanguageCode {
            appPhase = .error("원본 문서의 주요 언어와 도착 언어가 동일하여 번역할 수 없습니다.")
            return
        }
        
        let sourceLang = Locale.Language(identifier: dominantLangCode == "und" ? "en" : dominantLangCode)
        let newConfig = TranslationSession.Configuration(source: sourceLang, target: targetLang)
        if translationConfig != nil {
            translationConfig?.invalidate()
        }
        translationConfig = newConfig
    }

    /// Execute translation with the provided session from .translationTask
    func executeTranslation(session: TranslationSession) async {
        guard let book = self.book else { return }

        // Store the session in our service
        translationService.setSession(session)

        appPhase = .translating
        cancellationRequested = false
        let selectedChapters = book.chapters.filter(\.isSelected)
        totalChaptersToTranslate = selectedChapters.count
        completedChapters = 0
        currentChapterProgress = 0.0

        // Create an isolated working copy of the extracted EPUB directory
        // so that canceling or re-running with a different mode never mutates the clean source files.
        let workingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBWorking_\(UUID().uuidString)")

        defer {
            try? FileManager.default.removeItem(at: workingDir)
        }

        do {
            try FileManager.default.copyItem(at: book.extractedPath, to: workingDir)

            for (chapterIndex, chapter) in selectedChapters.enumerated() {
                if cancellationRequested { break }

                currentChapterTitle = chapter.title
                currentChapterProgress = 0.0
                statusMessage = "번역 중: \(chapter.title)"

                let chapterURL = workingDir.appendingPathComponent(chapter.relativePath)

                // Extract paragraphs and keep the parsed Document in memory to avoid double parsing
                let (document, paragraphs, isXHTML) = try htmlProcessor.extractParagraphs(from: chapterURL)

                guard !paragraphs.isEmpty else {
                    completedChapters = chapterIndex + 1
                    continue
                }

                // Determine which paragraphs to skip
                var translationEntries: [(original: String, translated: String, skipped: Bool)] = []
                var textsToTranslate: [(index: Int, text: String)] = []

                for (i, para) in paragraphs.enumerated() {
                    let shouldSkip = languageDetector.shouldSkipTranslation(
                        paragraph: para.text,
                        targetLanguageCode: targetLanguageCode
                    )

                    if shouldSkip {
                        translationEntries.append((original: para.text, translated: para.text, skipped: true))
                    } else {
                        translationEntries.append((original: para.text, translated: "", skipped: false))
                        textsToTranslate.append((index: i, text: para.text))
                    }
                }

                // Batch translate non-skipped paragraphs
                if !textsToTranslate.isEmpty && !cancellationRequested {
                    let textsOnly = textsToTranslate.map(\.text)
                    let totalToTranslate = textsOnly.count

                    let translated = try await translationService.translateBatch(
                        texts: textsOnly
                    ) { [weak self] completed in
                        Task { @MainActor in
                            self?.currentChapterProgress = Double(completed) / Double(totalToTranslate)
                        }
                    }

                    // Map translations back with on-device text refinement
                    for (j, item) in textsToTranslate.enumerated() {
                        if j < translated.count {
                            let polished = hybridService.polishTranslation(
                                translatedText: translated[j],
                                originalText: item.text,
                                targetLanguageCode: targetLanguageCode
                            )
                            translationEntries[item.index] = (
                                original: item.text,
                                translated: polished,
                                skipped: false
                            )
                        }
                    }
                }

                // Apply translations to the in-memory HTML document
                let modifiedHTML = try htmlProcessor.applyTranslations(
                    document: document,
                    isXHTML: isXHTML,
                    translations: translationEntries,
                    mode: translationMode,
                    targetLanguageCode: targetLanguageCode
                )

                // Write modified HTML back to the working copy
                try modifiedHTML.write(to: chapterURL, atomically: true, encoding: .utf8)

                completedChapters = chapterIndex + 1
                currentChapterProgress = 1.0
            }

            if cancellationRequested {
                statusMessage = "번역이 취소되었습니다."
                translationConfig = nil
                appPhase = .ready
                return
            }

            // Update OPF metadata language tag in the working copy to target language
            updateOPFLanguage(workingDir: workingDir, opfRelativePath: book.opfRelativePath, targetLanguageCode: targetLanguageCode)

            // Package the translated EPUB from working copy
            appPhase = .packaging
            statusMessage = "EPUB 파일을 재패키징하는 중..."

            let outputFileName = "\(book.originalFileName)_\(targetLanguageDisplayName)_\(translationMode.rawValue).epub"
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

            try epubPackager.packageEPUB(from: workingDir, to: outputURL)

            self.exportedFileURL = outputURL
            self.exportedEPUBData = try Data(contentsOf: outputURL)
            self.translationConfig = nil

            appPhase = .completed
            statusMessage = "번역 완료! 파일을 저장하세요."
            showFileExporter = true

        } catch {
            self.translationConfig = nil
            appPhase = .error("번역 중 오류 발생: \(error.localizedDescription)")
        }
    }

    /// Cancel the current translation
    func cancelTranslation() {
        cancellationRequested = true
        statusMessage = "번역을 취소하는 중..."
    }

    /// Reset the app state
    func reset() {
        // Clean up temp files
        if let extractedPath = book?.extractedPath {
            try? FileManager.default.removeItem(at: extractedPath)
        }
        if let exportedURL = exportedFileURL {
            try? FileManager.default.removeItem(at: exportedURL)
        }

        book = nil
        appPhase = .idle
        statusMessage = ""
        completedChapters = 0
        totalChaptersToTranslate = 0
        currentChapterProgress = 0.0
        currentChapterTitle = ""
        exportedEPUBData = nil
        exportedFileURL = nil
        cancellationRequested = false
        translationConfig = nil
    }

    /// Save exported EPUB to user-selected location
    func saveExportedFile(to destinationURL: URL) {
        guard let sourceURL = exportedFileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            statusMessage = "파일이 저장되었습니다: \(destinationURL.lastPathComponent)"
        } catch {
            appPhase = .error("파일 저장 실패: \(error.localizedDescription)")
        }
    }

    /// Update OPF <dc:language> tag to the target language for proper e-reader rendering
    private func updateOPFLanguage(workingDir: URL, opfRelativePath: String, targetLanguageCode: String) {
        let opfURL = workingDir.appendingPathComponent(opfRelativePath)
        guard let opfContent = try? String(contentsOf: opfURL, encoding: .utf8) else { return }

        // Match <dc:language>...</dc:language> or <dc:language id="...">...</dc:language>
        let pattern = "<dc:language([^>]*)>[^<]*</dc:language>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(location: 0, length: (opfContent as NSString).length)
            let updated = regex.stringByReplacingMatches(
                in: opfContent,
                options: [],
                range: range,
                withTemplate: "<dc:language$1>\(targetLanguageCode)</dc:language>"
            )
            try? updated.write(to: opfURL, atomically: true, encoding: .utf8)
            logger.info("Updated OPF language metadata to '\(targetLanguageCode)'")
        }
    }
}
