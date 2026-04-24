import Foundation
import ZIPFoundation
import SwiftSoup

/// Service responsible for extracting and parsing EPUB files
actor EPUBParser {

    /// Extract an EPUB file to a temporary directory and parse its contents
    func parseEPUB(at fileURL: URL) async throws -> EPUBBook {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBTranslator_\(UUID().uuidString)")

        // Create temp directory
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Unzip EPUB
        try FileManager.default.unzipItem(at: fileURL, to: tempDir)

        // Find and parse container.xml to locate OPF file
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        let containerData = try Data(contentsOf: containerPath)
        let containerXML = try SwiftSoup.parse(String(data: containerData, encoding: .utf8) ?? "", "", Parser.xmlParser())
        let rootfileElement = try containerXML.select("rootfile").first()
        guard let opfRelativePath = try rootfileElement?.attr("full-path") else {
            throw EPUBParserError.opfNotFound
        }

        // Parse OPF file
        let opfURL = tempDir.appendingPathComponent(opfRelativePath)
        let opfData = try Data(contentsOf: opfURL)
        let opfXML = try SwiftSoup.parse(String(data: opfData, encoding: .utf8) ?? "", "", Parser.xmlParser())

        // Extract metadata
        let title = try opfXML.select("metadata dc\\:title, metadata title").first()?.text() ?? fileURL.deletingPathExtension().lastPathComponent
        let author = try opfXML.select("metadata dc\\:creator, metadata creator").first()?.text() ?? "Unknown Author"

        // Get the OPF directory for resolving relative paths
        let opfDir = opfRelativePath.contains("/")
            ? String(opfRelativePath[opfRelativePath.startIndex..<opfRelativePath.lastIndex(of: "/")!])
            : ""

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

        for itemRef in spineElements {
            let idref = try itemRef.attr("idref")
            guard let manifestItem = manifestItems[idref] else { continue }

            // Only process XHTML/HTML content
            let mediaType = manifestItem.mediaType
            guard mediaType.contains("xhtml") || mediaType.contains("html") || mediaType.contains("xml") else {
                continue
            }

            let chapterRelativePath: String
            if opfDir.isEmpty {
                chapterRelativePath = manifestItem.href
            } else {
                chapterRelativePath = opfDir + "/" + manifestItem.href
            }

            let chapterURL = tempDir.appendingPathComponent(chapterRelativePath)

            guard FileManager.default.fileExists(atPath: chapterURL.path) else { continue }

            // Parse chapter to extract title and paragraph count
            let chapterData = try Data(contentsOf: chapterURL)
            let chapterHTML = try SwiftSoup.parse(String(data: chapterData, encoding: .utf8) ?? "")

            // Try to find a meaningful title
            let chapterTitle = try extractChapterTitle(from: chapterHTML, fallback: manifestItem.href)

            // Count paragraphs (p, h1-h6 elements with text)
            let paragraphs = try chapterHTML.select("p, h1, h2, h3, h4, h5, h6")
            let paragraphCount = paragraphs.array().filter { element in
                (try? element.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?? false
            }.count

            let chapter = Chapter(
                title: chapterTitle,
                relativePath: chapterRelativePath,
                paragraphCount: paragraphCount
            )
            chapters.append(chapter)
        }

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

    /// Extract a meaningful title from chapter HTML
    private func extractChapterTitle(from doc: Document, fallback: String) throws -> String {
        // Try <title> tag first
        if let titleTag = try doc.select("title").first() {
            let text = try titleTag.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        // Try heading tags
        for heading in ["h1", "h2", "h3"] {
            if let h = try doc.select(heading).first() {
                let text = try h.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }

        // Use filename as fallback
        let fileName = URL(string: fallback)?.deletingPathExtension().lastPathComponent ?? fallback
        return fileName
    }

    /// Recursively collect all file paths relative to the base directory
    private func collectAllFiles(in directory: URL) -> [String] {
        var files: [String] = []
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            if !isDir.boolValue {
                let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
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
            return "EPUB 구조가 올바르지 않습니다."
        case .chapterNotFound(let path):
            return "챕터 파일을 찾을 수 없습니다: \(path)"
        }
    }
}
