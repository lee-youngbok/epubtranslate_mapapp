import SwiftUI
import Foundation
import Translation
import NaturalLanguage
import SwiftSoup

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

    private let epubParser = EPUBParser()
    private let languageDetector = LanguageDetector()
    let translationService = TranslationService()
    private let htmlProcessor = HTMLProcessor()
    private let epubPackager = EPUBPackager()

    // MARK: - Computed Properties

    var selectedChaptersCount: Int {
        book?.chapters.filter(\.isSelected).count ?? 0
    }

    var targetLanguageDisplayName: String {
        TargetLanguage.allLanguages.first(where: { $0.id == targetLanguageCode })?.displayName ?? targetLanguageCode
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
            // Access security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                appPhase = .error("파일 접근 권한이 없습니다.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Copy to temp location for processing
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)

            appPhase = .analyzing
            statusMessage = "EPUB 구조를 분석하는 중..."

            // Parse the EPUB
            var parsedBook = try await epubParser.parseEPUB(at: tempURL)

            statusMessage = "언어를 감지하는 중..."

            // Detect languages across all chapters
            var allTexts: [String] = []
            for chapter in parsedBook.chapters {
                let chapterURL = parsedBook.extractedPath.appendingPathComponent(chapter.relativePath)
                if let data = try? Data(contentsOf: chapterURL) {
                    let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) ?? ""
                    if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        do {
                            let doc = try SwiftSoup.parse(html)
                            let paragraphs = try doc.select("p, h1, h2, h3, h4, h5, h6")
                            for p in paragraphs.array() {
                                let text = try p.text().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                                if !text.isEmpty {
                                    allTexts.append(text)
                                }
                            }
                        } catch {
                            print("[DEBUG-ViewModel] SwiftSoup 파싱 에러 (전체 언어 감지) - 챕터: \(chapter.title), 에러: \(error)")
                        }
                    }
                }
            }

            let detectedLanguages = languageDetector.detectLanguageDistribution(texts: allTexts)
            parsedBook.detectedLanguages = detectedLanguages

            // Detect per-chapter languages
            for i in 0..<parsedBook.chapters.count {
                let chapterURL = parsedBook.extractedPath.appendingPathComponent(parsedBook.chapters[i].relativePath)
                if let data = try? Data(contentsOf: chapterURL) {
                    let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) ?? ""
                    if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        do {
                            let doc = try SwiftSoup.parse(html)
                            let paragraphs = try doc.select("p")
                            let chapterTexts = try paragraphs.array().compactMap { try $0.text() }
                            let combined = chapterTexts.joined(separator: " ")
                            parsedBook.chapters[i].detectedLanguage = languageDetector.detectLanguage(of: combined)
                        } catch {
                            print("[DEBUG-ViewModel] SwiftSoup 파싱 에러 (챕터별 언어 감지) - 챕터: \(parsedBook.chapters[i].title), 에러: \(error)")
                        }
                    }
                }
            }

            self.book = parsedBook
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
        translationConfig = .init(target: targetLang)
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

        do {
            for (chapterIndex, chapter) in selectedChapters.enumerated() {
                if cancellationRequested { break }

                currentChapterTitle = chapter.title
                currentChapterProgress = 0.0
                statusMessage = "번역 중: \(chapter.title)"

                let chapterURL = book.extractedPath.appendingPathComponent(chapter.relativePath)

                // Extract paragraphs
                let (_, paragraphs, _) = try htmlProcessor.extractParagraphs(from: chapterURL)

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

                    // Map translations back
                    for (j, item) in textsToTranslate.enumerated() {
                        if j < translated.count {
                            translationEntries[item.index] = (
                                original: item.text,
                                translated: translated[j],
                                skipped: false
                            )
                        }
                    }
                }

                // Apply translations to HTML
                let modifiedHTML = try htmlProcessor.applyTranslations(
                    fileURL: chapterURL,
                    translations: translationEntries,
                    mode: translationMode
                )

                // Write modified HTML back
                try modifiedHTML.write(to: chapterURL, atomically: true, encoding: .utf8)

                completedChapters = chapterIndex + 1
                currentChapterProgress = 1.0
            }

            if cancellationRequested {
                statusMessage = "번역이 취소되었습니다."
                appPhase = .ready
                return
            }

            // Package the translated EPUB
            appPhase = .packaging
            statusMessage = "EPUB 파일을 재패키징하는 중..."

            let outputFileName = "\(book.originalFileName)_\(targetLanguageDisplayName)_\(translationMode.rawValue).epub"
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

            try epubPackager.packageEPUB(from: book.extractedPath, to: outputURL)

            self.exportedFileURL = outputURL
            self.exportedEPUBData = try Data(contentsOf: outputURL)

            appPhase = .completed
            statusMessage = "번역 완료! 파일을 저장하세요."
            showFileExporter = true

        } catch {
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
}
