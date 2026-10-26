import Foundation
import ZIPFoundation
import SwiftSoup
import os

/// Service responsible for extracting and parsing EPUB files
actor EPUBParser {

    private static let logger = Logger(subsystem: "com.example.EPUBTranslator", category: "EPUBParser")

    /// Extract an EPUB file to a temporary directory and parse its contents
    func parseEPUB(at fileURL: URL) async throws -> EPUBBook {
        Self.logger.info("Starting EPUB extraction & parsing for: \(fileURL.path)")

        // 1. 보안 권한 획득 (사용자가 선택한 원본 EPUB 파일에 대해)
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        // 원본 파일 존재 여부 확인
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Self.logger.error("Source EPUB file does not exist at path: \(fileURL.path)")
            throw EPUBParserError.invalidEPUBStructure
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBTranslator_\(UUID().uuidString)")

        // Create temp directory
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        Self.logger.debug("Created temporary working directory: \(tempDir.path)")

        // Unzip EPUB
        try FileManager.default.unzipItem(at: fileURL, to: tempDir)
        Self.logger.debug("Successfully unzipped EPUB archive")

        // Find and parse container.xml to locate OPF file
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        let containerXML = try safeParse(fileURL: containerPath, isXML: true)

        let rootfileElement = try containerXML.select("rootfile").first()
        guard let opfRelativePath = try rootfileElement?.attr("full-path") else {
            Self.logger.error("Failed to find rootfile (OPF path) in container.xml")
            throw EPUBParserError.opfNotFound
        }
        Self.logger.debug("Located OPF relative path: \(opfRelativePath)")

        // Parse OPF file
        let opfURL = tempDir.appendingPathComponent(opfRelativePath)
        let opfXML = try safeParse(fileURL: opfURL, isXML: true)

        // Extract metadata safely without using complex CSS selectors
        var title = fileURL.deletingPathExtension().lastPathComponent
        if let titleTag = try? opfXML.getElementsByTag("dc:title").first() {
            title = (try? titleTag.text()) ?? title
        } else if let titleTag = try? opfXML.getElementsByTag("title").first() {
            title = (try? titleTag.text()) ?? title
        }

        var author = "Unknown Author"
        if let creatorTag = try? opfXML.getElementsByTag("dc:creator").first() {
            author = (try? creatorTag.text()) ?? author
        } else if let creatorTag = try? opfXML.getElementsByTag("creator").first() {
            author = (try? creatorTag.text()) ?? author
        }
        Self.logger.info("Parsed book metadata - Title: \(title), Author: \(author)")

        // Get the OPF directory for resolving relative paths safely
        let opfDir = (opfRelativePath as NSString).deletingLastPathComponent

        // Parse manifest to get id -> href mapping
        var manifestItems: [String: (href: String, mediaType: String)] = [:]
        let manifestElements = try opfXML.select("manifest item")
        for item in manifestElements {
            let id = try item.attr("id")
            let href = try item.attr("href")
            let mediaType = try item.attr("media-type")
            manifestItems[id] = (href: href, mediaType: mediaType)
        }

        // Parse spine to get ordered chapter list
        let spineElements = try opfXML.select("spine itemref")
        var chapters: [Chapter] = []
        var seenPaths = Set<String>()

        for itemRef in spineElements {
            let idref = try itemRef.attr("idref")
            guard let manifestItem = manifestItems[idref] else { continue }

            // Only process XHTML/HTML content
            let mediaType = manifestItem.mediaType
            guard mediaType.contains("xhtml") || mediaType.contains("html") || mediaType.contains("xml") else {
                continue
            }

            // Strip fragment identifier (#anchor) and decode percent-encoding (%20 -> space, etc.)
            let rawHref = manifestItem.href.components(separatedBy: "#").first ?? manifestItem.href
            let decodedHref = rawHref.removingPercentEncoding ?? rawHref

            let chapterRelativePath: String
            if opfDir.isEmpty {
                chapterRelativePath = decodedHref
            } else {
                chapterRelativePath = (opfDir as NSString).appendingPathComponent(decodedHref)
            }

            // Avoid duplicate processing if multiple spine itemrefs point to anchors in the same file
            guard !seenPaths.contains(chapterRelativePath) else { continue }
            seenPaths.insert(chapterRelativePath)

            let chapterURL = tempDir.appendingPathComponent(chapterRelativePath)

            guard FileManager.default.fileExists(atPath: chapterURL.path) else {
                Self.logger.warning("Chapter file missing: \(chapterURL.path)")
                continue
            }

            // Parse chapter to extract title, paragraph count, and sample texts
            do {
                let chapterHTML = try safeParse(fileURL: chapterURL, isXML: false)

                // Try to find a meaningful title
                let chapterTitle = try extractChapterTitle(from: chapterHTML, fallback: decodedHref)

                // Count translatable block elements (p, h1-h6, li, blockquote) and collect samples
                let elements = try chapterHTML.select(HTMLProcessor.translatableSelector)
                var validTexts: [String] = []
                for element in elements.array() {
                    if HTMLProcessor.hasNestedTranslatableBlock(element) { continue }
                    if let text = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        validTexts.append(text)
                    }
                }

                let chapter = Chapter(
                    title: chapterTitle,
                    relativePath: chapterRelativePath,
                    paragraphCount: validTexts.count,
                    sampleTexts: Array(validTexts.prefix(15))
                )
                chapters.append(chapter)
            } catch {
                Self.logger.warning("Skipping unparseable chapter at \(chapterRelativePath): \(error.localizedDescription)")
            }
        }

        Self.logger.info("Successfully extracted \(chapters.count) chapters")

        // Collect all files for repackaging
        let allFiles = collectAllFiles(in: tempDir)

        return EPUBBook(
            title: title,
            author: author,
            chapters: chapters,
            extractedPath: tempDir,
            originalFileName: fileURL.deletingPathExtension().lastPathComponent,
            detectedLanguages: [],
            opfRelativePath: opfRelativePath,
            allFiles: allFiles
        )
    }

    // MARK: - Safe Parsing Helper

    /// 파일을 안전하게 읽어 빈 내용인지 검증한 후 SwiftSoup으로 파싱합니다.
    private func safeParse(fileURL: URL, isXML: Bool) throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Self.logger.error("File does not exist: \(fileURL.path)")
            throw EPUBParserError.invalidEPUBStructure
        }

        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            let data = try Data(contentsOf: fileURL)
            content = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .macOSRoman) ?? ""
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.error("File content is empty: \(fileURL.lastPathComponent)")
            throw EPUBParserError.invalidEPUBStructure
        }

        do {
            if isXML {
                return try SwiftSoup.parse(content, fileURL.absoluteString, Parser.xmlParser())
            } else {
                return try SwiftSoup.parse(content, fileURL.absoluteString)
            }
        } catch {
            Self.logger.error("SwiftSoup parsing failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            throw EPUBParserError.invalidEPUBStructure
        }
    }

    /// Extract a meaningful title from chapter HTML
    private func extractChapterTitle(from doc: Document, fallback: String) throws -> String {
        if let titleTag = try doc.select("title").first() {
            let text = try titleTag.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        for heading in ["h1", "h2", "h3"] {
            if let h = try doc.select(heading).first() {
                let text = try h.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }

        let fileName = URL(string: fallback)?.deletingPathExtension().lastPathComponent ?? fallback
        return fileName
    }

    /// Recursively collect all file paths relative to the base directory
    private func collectAllFiles(in directory: URL) -> [String] {
        var files: [String] = []
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            return files
        }
        while let relativePath = enumerator.nextObject() as? String {
            let fileURL = directory.appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if !isDir.boolValue {
                files.append(relativePath)
            }
        }
        return files
    }
}

/// Errors that can occur during EPUB parsing
enum EPUBParserError: LocalizedError {
    case opfNotFound
    case invalidEPUBStructure
    case chapterNotFound(String)

    var errorDescription: String? {
        switch self {
        case .opfNotFound:
            return "OPF 파일을 찾을 수 없습니다. 유효한 EPUB 파일인지 확인하세요."
        case .invalidEPUBStructure:
            return "EPUB 구조가 올바르지 않거나 파일이 비어 있습니다."
        case .chapterNotFound(let path):
            return "챕터 파일을 찾을 수 없습니다: \(path)"
        }
    }
}
