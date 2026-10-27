import SwiftUI
import Foundation
import Translation
import NaturalLanguage
import SwiftSoup
import os
#if os(macOS)
import AppKit
#endif

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

    // MARK: - Apple Books & Metadata Options

    /// If true, sends the packaged EPUB directly to Apple Books upon completion without showing file save dialog
    var exportDirectlyToAppleBooks = false

    /// Editable book title for OPF metadata and Apple Books display
    var customBookTitle: String = ""

    /// Editable book author for OPF metadata and Apple Books display
    var customBookAuthor: String = ""

    /// Detected proper nouns from the book suggested for glossary protection
    var suggestedEntities: [String] = []

    // MARK: - Typography / Font Options (언어별 원문 & 번역문 폰트 설정)

    /// Font selections for original (source) text keyed by BCP 47 language code
    var sourceFontByLanguage: [String: FontSelection] = [:]

    /// Font selections for translated (target) text keyed by BCP 47 language code
    var targetFontByLanguage: [String: FontSelection] = [:]

    /// Currently active source language code selected in the Font Settings UI
    var selectedSourceLanguageForFont: String = "en"

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
    let fontManager = FontManager.shared
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

            // Extract suggested proper nouns (names/places) from sample texts for glossary protection
            self.suggestedEntities = hybridService.extractSuggestedEntities(from: allTexts)

            // Initialize editable metadata for Apple Books export
            self.customBookTitle = parsedBook.title
            self.customBookAuthor = parsedBook.author

            // Set default source language in Font Settings to dominant detected language
            if let dominantLang = parsedBook.detectedLanguages.first?.languageCode, dominantLang != "und" {
                self.selectedSourceLanguageForFont = dominantLang
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

    // MARK: - Typography & Font Management (언어별 원문 / 번역문 폰트 설정)

    /// Available source languages to configure fonts for (prioritizes book's detected languages if loaded)
    var configurableSourceLanguages: [TargetLanguage] {
        var result: [TargetLanguage] = []
        var seen = Set<String>()

        if let detected = book?.detectedLanguages {
            for info in detected where info.languageCode != "und" {
                if !seen.contains(info.languageCode) {
                    seen.insert(info.languageCode)
                    result.append(TargetLanguage(
                        id: info.languageCode,
                        displayName: "\(info.displayName) (\(Int(info.percentage.rounded()))%)"
                    ))
                }
            }
        }

        for lang in availableLanguages where !seen.contains(lang.id) {
            seen.insert(lang.id)
            result.append(lang)
        }
        return result
    }

    func displayName(forLanguageCode code: String) -> String {
        if let match = availableLanguages.first(where: { $0.id == code }) {
            return match.displayName
        }
        if let detected = book?.detectedLanguages.first(where: { $0.languageCode == code }) {
            return detected.displayName
        }
        return Locale(identifier: "ko_KR").localizedString(forLanguageCode: code) ?? code
    }

    func sourceFontSelection(for languageCode: String) -> FontSelection {
        sourceFontByLanguage[languageCode] ?? .original
    }

    func setSourceFont(_ selection: FontSelection, for languageCode: String) {
        if selection.isOriginal {
            sourceFontByLanguage.removeValue(forKey: languageCode)
        } else {
            sourceFontByLanguage[languageCode] = selection
        }
        if case .downloadable(let font) = selection {
            Task {
                try? await fontManager.ensureFontDownloaded(font)
            }
        }
    }

    func targetFontSelection(for languageCode: String) -> FontSelection {
        targetFontByLanguage[languageCode] ?? .original
    }

    func setTargetFont(_ selection: FontSelection, for languageCode: String) {
        if selection.isOriginal {
            targetFontByLanguage.removeValue(forKey: languageCode)
        } else {
            targetFontByLanguage[languageCode] = selection
        }
        if case .downloadable(let font) = selection {
            Task {
                try? await fontManager.ensureFontDownloaded(font)
            }
        }
    }

    var currentSourceFontSelection: FontSelection {
        get { sourceFontSelection(for: selectedSourceLanguageForFont) }
        set { setSourceFont(newValue, for: selectedSourceLanguageForFont) }
    }

    var currentTargetFontSelection: FontSelection {
        get { targetFontSelection(for: targetLanguageCode) }
        set { setTargetFont(newValue, for: targetLanguageCode) }
    }

    /// Ensures any selected downloadable commercial-free fonts are downloaded and copied into the EPUB working directory
    private func prepareEmbeddedFontAssets(
        workingDir: URL,
        opfRelativePath: String
    ) async throws -> [DownloadableFont: HTMLProcessor.EmbeddedFontAsset] {
        var neededFonts = Set<DownloadableFont>()
        for selection in sourceFontByLanguage.values {
            if case .downloadable(let font) = selection {
                neededFonts.insert(font)
            }
        }
        if case .downloadable(let font) = currentTargetFontSelection {
            neededFonts.insert(font)
        }

        guard !neededFonts.isEmpty else { return [:] }

        let opfDir = (opfRelativePath as NSString).deletingLastPathComponent
        let fontsRelDir = opfDir.isEmpty ? "Fonts" : "\(opfDir)/Fonts"
        let fontsDirURL = workingDir.appendingPathComponent(fontsRelDir, isDirectory: true)
        try FileManager.default.createDirectory(at: fontsDirURL, withIntermediateDirectories: true)

        var assets: [DownloadableFont: HTMLProcessor.EmbeddedFontAsset] = [:]

        for font in neededFonts {
            statusMessage = "폰트 준비 중: \(font.displayName)..."
            let cachedFontURL = try await fontManager.ensureFontDownloaded(font)
            let fileName = cachedFontURL.lastPathComponent
            let destURL = fontsDirURL.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: cachedFontURL, to: destURL)

            let epubRelativePath = "\(fontsRelDir)/\(fileName)"
            assets[font] = HTMLProcessor.EmbeddedFontAsset(
                font: font,
                epubRelativePath: epubRelativePath,
                fileExtension: cachedFontURL.pathExtension.lowercased()
            )
        }

        return assets
    }

    // MARK: - Glossary Management

    func addGlossaryEntry(source: String, target: String = "") {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return }
        guard !hybridService.glossaryEntries.contains(where: { $0.sourceTerm.caseInsensitiveCompare(trimmedSource) == .orderedSame }) else {
            return
        }
        hybridService.glossaryEntries.append(GlossaryEntry(sourceTerm: trimmedSource, targetTerm: target))
    }

    func removeGlossaryEntry(id: UUID) {
        hybridService.glossaryEntries.removeAll { $0.id == id }
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

            let dominantSourceLang = book.detectedLanguages.first(where: { $0.languageCode != "und" })?.languageCode ?? "en"

            // Ensure any selected commercial-free downloadable fonts are downloaded and copied into the EPUB working copy
            let embeddedFontAssets = try await prepareEmbeddedFontAssets(
                workingDir: workingDir,
                opfRelativePath: book.opfRelativePath
            )

            let fontConfig = HTMLProcessor.FontStyleConfiguration(
                sourceFontByLanguage: sourceFontByLanguage,
                dominantSourceLanguageCode: dominantSourceLang,
                targetFont: currentTargetFontSelection,
                embeddedAssets: embeddedFontAssets
            )

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

                // Determine which paragraphs to skip, and split non-skipped paragraphs into sentences
                // while masking glossary/entity terms.
                var translationEntries: [(original: String, translated: String, skipped: Bool, sourceLang: String)] = []

                struct SentenceTask {
                    let paragraphIndex: Int
                    let maskedText: String
                    let replacements: [(token: String, value: String)]
                }
                var sentenceTasks: [SentenceTask] = []

                let chapterFallbackLang = chapter.detectedLanguage ?? dominantSourceLang

                for (i, para) in paragraphs.enumerated() {
                    let detectedParaLang = languageDetector.detectLanguage(of: para.text) ?? chapterFallbackLang
                    let shouldSkip = languageDetector.shouldSkipTranslation(
                        paragraph: para.text,
                        targetLanguageCode: targetLanguageCode
                    )

                    if shouldSkip {
                        translationEntries.append((original: para.text, translated: para.text, skipped: true, sourceLang: detectedParaLang))
                    } else {
                        translationEntries.append((original: para.text, translated: "", skipped: false, sourceLang: detectedParaLang))
                        let sentences = hybridService.splitIntoSentences(para.text)
                        for sentence in sentences {
                            let (masked, replacements) = hybridService.maskProtectedTerms(in: sentence)
                            sentenceTasks.append(SentenceTask(
                                paragraphIndex: i,
                                maskedText: masked,
                                replacements: replacements
                            ))
                        }
                    }
                }

                // Batch translate sentence chunks
                if !sentenceTasks.isEmpty && !cancellationRequested {
                    let textsOnly = sentenceTasks.map(\.maskedText)
                    let totalToTranslate = textsOnly.count

                    let translatedChunks = try await translationService.translateBatch(
                        texts: textsOnly
                    ) { [weak self] completed in
                        Task { @MainActor in
                            self?.currentChapterProgress = Double(completed) / Double(totalToTranslate)
                        }
                    }

                    // Group translated sentences back by paragraph index and unmask protected terms
                    var paragraphSentences: [Int: [String]] = [:]
                    for (j, task) in sentenceTasks.enumerated() {
                        if j < translatedChunks.count {
                            let unmasked = hybridService.unmaskProtectedTerms(
                                in: translatedChunks[j],
                                replacements: task.replacements
                            )
                            paragraphSentences[task.paragraphIndex, default: []].append(unmasked)
                        }
                    }

                    for (paraIdx, sentences) in paragraphSentences {
                        let combined = sentences.joined(separator: " ")
                        let originalText = translationEntries[paraIdx].original
                        let sourceLang = translationEntries[paraIdx].sourceLang
                        let polished = hybridService.polishTranslation(
                            translatedText: combined,
                            originalText: originalText,
                            targetLanguageCode: targetLanguageCode
                        )
                        translationEntries[paraIdx] = (
                            original: originalText,
                            translated: polished,
                            skipped: false,
                            sourceLang: sourceLang
                        )
                    }
                }

                // Apply translations and custom typography to the in-memory HTML document
                let modifiedHTML = try htmlProcessor.applyTranslations(
                    document: document,
                    isXHTML: isXHTML,
                    translations: translationEntries,
                    mode: translationMode,
                    targetLanguageCode: targetLanguageCode,
                    chapterRelativePath: chapter.relativePath,
                    fontConfig: fontConfig
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

            // Update OPF metadata (language, title, author, and embedded font manifest items) in the working copy
            updateOPFMetadata(
                workingDir: workingDir,
                opfRelativePath: book.opfRelativePath,
                targetLanguageCode: targetLanguageCode,
                title: customBookTitle,
                author: customBookAuthor,
                embeddedFontAssets: Array(embeddedFontAssets.values)
            )

            // Package the translated EPUB from working copy
            appPhase = .packaging
            statusMessage = "EPUB 파일을 재패키징하는 중..."

            let sanitizedTitle = sanitizeFileName(customBookTitle.isEmpty ? book.originalFileName : customBookTitle)
            let outputFileName = "\(sanitizedTitle)_\(targetLanguageDisplayName)_\(translationMode.rawValue).epub"
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)

            try epubPackager.packageEPUB(from: workingDir, to: outputURL)

            self.exportedFileURL = outputURL
            self.exportedEPUBData = try Data(contentsOf: outputURL)
            self.translationConfig = nil

            appPhase = .completed
            if exportDirectlyToAppleBooks {
                openInAppleBooks(fileURL: outputURL)
            } else {
                statusMessage = "번역 완료! 파일을 저장하세요."
                showFileExporter = true
            }

        } catch {
            self.translationConfig = nil
            appPhase = .error("번역 중 오류 발생: \(error.localizedDescription)")
        }
    }

    /// Open the exported EPUB file directly in Apple Books without showing a file save dialog
    func openInAppleBooks(fileURL: URL? = nil) {
        guard let targetURL = fileURL ?? exportedFileURL else { return }
        #if os(macOS)
        if let booksAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iBooksX") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([targetURL], withApplicationAt: booksAppURL, configuration: config) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.statusMessage = "도서 앱 실행 실패: \(error.localizedDescription)"
                    } else {
                        self?.statusMessage = "Apple 도서 앱으로 바로 내보냈습니다!"
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(targetURL)
            statusMessage = "Apple 도서 앱으로 바로 내보냈습니다!"
        }
        #else
        statusMessage = "생성된 EPUB 파일을 도서 앱에서 열 준비가 완료되었습니다."
        #endif
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "TranslatedBook" : cleaned
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

    /// Update OPF <dc:language>, <dc:title>, <dc:creator> metadata tags and register embedded font assets in <manifest>
    private func updateOPFMetadata(
        workingDir: URL,
        opfRelativePath: String,
        targetLanguageCode: String,
        title: String,
        author: String,
        embeddedFontAssets: [HTMLProcessor.EmbeddedFontAsset] = []
    ) {
        let opfURL = workingDir.appendingPathComponent(opfRelativePath)
        guard var opfContent = try? String(contentsOf: opfURL, encoding: .utf8) else { return }

        func replaceXMLTag(_ tagName: String, with newValue: String, in content: inout String) {
            let escapedValue = newValue
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let escapedTemplate = NSRegularExpression.escapedTemplate(for: escapedValue)
            let pattern = "<\(tagName)([^>]*)>[^<]*</\(tagName)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: (content as NSString).length)
                if regex.firstMatch(in: content, options: [], range: range) != nil {
                    content = regex.stringByReplacingMatches(
                        in: content,
                        options: [],
                        range: range,
                        withTemplate: "<\(tagName)$1>\(escapedTemplate)</\(tagName)>"
                    )
                }
            }
        }

        replaceXMLTag("dc:language", with: targetLanguageCode, in: &opfContent)

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            replaceXMLTag("dc:title", with: trimmedTitle, in: &opfContent)
        }

        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuthor.isEmpty {
            replaceXMLTag("dc:creator", with: trimmedAuthor, in: &opfContent)
        }

        // Register embedded fonts in OPF <manifest>
        if !embeddedFontAssets.isEmpty {
            var manifestItemsXML: [String] = []
            for asset in embeddedFontAssets {
                let itemId = "font-custom-\(asset.font.rawValue)"
                if !opfContent.contains("id=\"\(itemId)\"") {
                    let href = HTMLProcessor.relativePath(from: opfRelativePath, to: asset.epubRelativePath)
                    let mediaType = FontManager.epubMediaType(forExtension: asset.fileExtension)
                    manifestItemsXML.append("    <item id=\"\(itemId)\" href=\"\(href)\" media-type=\"\(mediaType)\"/>")
                }
            }
            if !manifestItemsXML.isEmpty,
               let closeRange = opfContent.range(of: "</manifest>", options: .caseInsensitive) {
                let insertion = manifestItemsXML.joined(separator: "\n") + "\n"
                opfContent.insert(contentsOf: insertion, at: closeRange.lowerBound)
            }
        }

        try? opfContent.write(to: opfURL, atomically: true, encoding: .utf8)
        logger.info("Updated OPF metadata - language: '\(targetLanguageCode)', title: '\(trimmedTitle)', author: '\(trimmedAuthor)', embeddedFonts: \(embeddedFontAssets.count)")
    }
}
