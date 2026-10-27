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
        let fallbackBookTitle = fileURL.deletingPathExtension().lastPathComponent
        var title = fallbackBookTitle
        if let titleTag = try? opfXML.getElementsByTag("dc:title").first(),
           let rawTitle = try? titleTag.text().trimmingCharacters(in: .whitespacesAndNewlines),
           Self.isMeaningfulTitle(rawTitle, bookTitle: nil, fileName: fallbackBookTitle, allowTOCKeywords: false) {
            title = rawTitle
        } else if let titleTag = try? opfXML.getElementsByTag("title").first(),
                  let rawTitle = try? titleTag.text().trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.isMeaningfulTitle(rawTitle, bookTitle: nil, fileName: fallbackBookTitle, allowTOCKeywords: false) {
            title = rawTitle
        }

        var author = "Unknown Author"
        if let creatorTag = try? opfXML.getElementsByTag("dc:creator").first() {
            let text = (try? creatorTag.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if !text.isEmpty { author = text }
        } else if let creatorTag = try? opfXML.getElementsByTag("creator").first() {
            let text = (try? creatorTag.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if !text.isEmpty { author = text }
        }
        Self.logger.info("Parsed book metadata - Title: \(title), Author: \(author)")

        // Get the OPF directory for resolving relative paths safely
        let opfDir = (opfRelativePath as NSString).deletingLastPathComponent

        // Parse manifest to get id -> (href, mediaType, properties) mapping
        var manifestItems: [String: (href: String, mediaType: String, properties: String)] = [:]
        var ncxRelativePath: String?
        var navRelativePath: String?
        var htmlTocSet = Set<String>()

        let spineTocId = (try? opfXML.select("spine").first()?.attr("toc")) ?? ""

        let manifestElements = try opfXML.select("manifest item")
        for item in manifestElements {
            let id = try item.attr("id")
            let href = try item.attr("href")
            let mediaType = try item.attr("media-type")
            let properties = (try? item.attr("properties")) ?? ""
            manifestItems[id] = (href: href, mediaType: mediaType, properties: properties)

            let resolvedPath = Self.resolveRelativePath(baseDir: opfDir, href: href).path
            let lowerMedia = mediaType.lowercased()
            let lowerHref = resolvedPath.lowercased()
            let propTokens = properties.lowercased().split(separator: " ").map(String.init)

            // Detect EPUB 2 NCX
            if id == spineTocId || lowerMedia.contains("dtbncx") || lowerHref.hasSuffix(".ncx") {
                if ncxRelativePath == nil || id == spineTocId {
                    ncxRelativePath = resolvedPath
                }
            }

            // Detect EPUB 3 Navigation Document
            if propTokens.contains("nav") {
                navRelativePath = resolvedPath
                htmlTocSet.insert(resolvedPath)
            }

            // Detect HTML TOC candidates by id or filename
            if lowerMedia.contains("html") || lowerMedia.contains("xml") {
                let stem = ((resolvedPath as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
                let lowerId = id.lowercased()
                if stem == "toc" || stem == "contents" || stem == "nav" || lowerId == "toc" || lowerId == "nav" {
                    htmlTocSet.insert(resolvedPath)
                }
            }
        }

        // Also check OPF <guide><reference type="toc" href="..."/>
        if let guideRefs = try? opfXML.select("guide reference") {
            for ref in guideRefs.array() {
                let type = (try? ref.attr("type").lowercased()) ?? ""
                let href = (try? ref.attr("href")) ?? ""
                if type == "toc", !href.isEmpty {
                    let resolved = Self.resolveRelativePath(baseDir: opfDir, href: href).path
                    if !resolved.isEmpty {
                        htmlTocSet.insert(resolved)
                    }
                }
            }
        }

        // Extract chapter titles from TOC files (EPUB 3 nav, EPUB 2 toc.ncx, and HTML TOC pages)
        var tocTitlesByPath: [String: String] = [:]
        if let navPath = navRelativePath {
            let navURL = tempDir.appendingPathComponent(navPath)
            parseHTMLTOCTitles(at: navURL, tocRelativePath: navPath, into: &tocTitlesByPath)
        }
        if let ncxPath = ncxRelativePath {
            let ncxURL = tempDir.appendingPathComponent(ncxPath)
            parseNCXTOCTitles(at: ncxURL, ncxRelativePath: ncxPath, into: &tocTitlesByPath)
        }
        for htmlTocPath in htmlTocSet where htmlTocPath != navRelativePath {
            let tocURL = tempDir.appendingPathComponent(htmlTocPath)
            parseHTMLTOCTitles(at: tocURL, tocRelativePath: htmlTocPath, into: &tocTitlesByPath)
        }

        // Parse spine to get ordered chapter list
        let spineElements = try opfXML.select("spine itemref")
        var chapters: [Chapter] = []
        var seenPaths = Set<String>()

        for itemRef in spineElements {
            let idref = try itemRef.attr("idref")
            guard let manifestItem = manifestItems[idref] else { continue }

            // Only process XHTML/HTML content
            let mediaType = manifestItem.mediaType.lowercased()
            guard mediaType.contains("xhtml") || mediaType.contains("html") || mediaType.contains("xml") else {
                continue
            }

            let chapterRelativePath = Self.resolveRelativePath(baseDir: opfDir, href: manifestItem.href).path
            guard !chapterRelativePath.isEmpty else { continue }

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

                // Check if this document contains an EPUB 3 <nav epub:type="toc"> or is a registered HTML TOC
                let hasNavTOC = Self.documentContainsTOCNav(chapterHTML)
                if hasNavTOC {
                    htmlTocSet.insert(chapterRelativePath)
                    if navRelativePath == nil {
                        navRelativePath = chapterRelativePath
                    }
                    // Also harvest TOC links if any were missed
                    extractTOCTitlesFromHTMLDocument(chapterHTML, tocRelativePath: chapterRelativePath, into: &tocTitlesByPath)
                }
                let isTOCChapter = htmlTocSet.contains(chapterRelativePath)

                // Count translatable block elements (p, h1-h6, li, blockquote) and collect samples
                let elements = try chapterHTML.select(HTMLProcessor.translatableSelector)
                var validTexts: [String] = []
                for element in elements.array() {
                    if HTMLProcessor.hasNestedTranslatableBlock(element) { continue }
                    if let text = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        validTexts.append(text)
                    }
                }

                // Extract a meaningful chapter title using TOC map, body headings, title classes, validated <title>, and opening text
                let chapterTitle = try extractChapterTitle(
                    from: chapterHTML,
                    chapterRelativePath: chapterRelativePath,
                    bookTitle: title,
                    tocTitle: tocTitlesByPath[chapterRelativePath],
                    validTexts: validTexts,
                    isTableOfContents: isTOCChapter
                )

                let chapter = Chapter(
                    title: chapterTitle,
                    relativePath: chapterRelativePath,
                    paragraphCount: validTexts.count,
                    sampleTexts: Array(validTexts.prefix(15)),
                    isTableOfContents: isTOCChapter
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
            allFiles: allFiles,
            ncxRelativePath: ncxRelativePath,
            navRelativePath: navRelativePath,
            htmlTocRelativePaths: Array(htmlTocSet).sorted()
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

    // MARK: - TOC Parsing & Chapter Title Extraction

    /// Parse EPUB 2 NCX (`toc.ncx`) to map chapter relative paths to their TOC titles
    private func parseNCXTOCTitles(
        at ncxURL: URL,
        ncxRelativePath: String,
        into tocTitlesByPath: inout [String: String]
    ) {
        guard FileManager.default.fileExists(atPath: ncxURL.path),
              let ncxDoc = try? safeParse(fileURL: ncxURL, isXML: true) else {
            return
        }

        let baseDir = (ncxRelativePath as NSString).deletingLastPathComponent
        guard let allElements = try? ncxDoc.getAllElements() else { return }

        for element in allElements.array() {
            let tag = element.tagName().lowercased()
            guard tag == "navpoint" || tag.hasSuffix(":navpoint") else { continue }

            // Extract direct child navLabel -> text and direct child content[src]
            var labelText = ""
            var contentSrc = ""

            for child in element.children().array() {
                let childTag = child.tagName().lowercased()
                if (childTag == "navlabel" || childTag.hasSuffix(":navlabel")) && labelText.isEmpty {
                    let raw = (try? child.text()) ?? ""
                    labelText = Self.normalizeWhitespace(raw)
                } else if (childTag == "content" || childTag.hasSuffix(":content")) && contentSrc.isEmpty {
                    contentSrc = (try? child.attr("src")) ?? ""
                }
            }

            guard !labelText.isEmpty, !contentSrc.isEmpty else { continue }
            let resolved = Self.resolveRelativePath(baseDir: baseDir, href: contentSrc)
            guard !resolved.path.isEmpty else { continue }

            let fileName = (resolved.path as NSString).lastPathComponent
            guard Self.isMeaningfulTitle(labelText, bookTitle: nil, fileName: fileName, allowTOCKeywords: true) else {
                continue
            }

            // Prefer the first (or anchorless top-level) TOC entry for a file path
            if tocTitlesByPath[resolved.path] == nil {
                tocTitlesByPath[resolved.path] = labelText
            }
        }
    }

    /// Parse EPUB 3 Navigation Document (`nav.xhtml`) or HTML TOC page to map chapter relative paths to their TOC titles
    private func parseHTMLTOCTitles(
        at tocURL: URL,
        tocRelativePath: String,
        into tocTitlesByPath: inout [String: String]
    ) {
        guard FileManager.default.fileExists(atPath: tocURL.path),
              let doc = try? safeParse(fileURL: tocURL, isXML: false) else {
            return
        }
        extractTOCTitlesFromHTMLDocument(doc, tocRelativePath: tocRelativePath, into: &tocTitlesByPath)
    }

    /// Extract `<a href="...">` labels from a parsed HTML/XHTML TOC document
    private func extractTOCTitlesFromHTMLDocument(
        _ doc: Document,
        tocRelativePath: String,
        into tocTitlesByPath: inout [String: String]
    ) {
        let baseDir = (tocRelativePath as NSString).deletingLastPathComponent

        // Prioritize <nav epub:type="toc"> / <nav role="doc-toc"> / <nav id="toc">, falling back to all <a> links in the TOC document
        var links: [Element] = []
        if let navElements = try? doc.select("nav") {
            for nav in navElements.array() {
                let epubType = (try? nav.attr("epub:type").lowercased()) ?? ""
                let role = (try? nav.attr("role").lowercased()) ?? ""
                let id = (try? nav.attr("id").lowercased()) ?? ""
                if epubType.contains("toc") || role.contains("toc") || id.contains("toc") {
                    if let navLinks = try? nav.select("a[href]") {
                        links.append(contentsOf: navLinks.array())
                    }
                }
            }
            if links.isEmpty, let firstNav = navElements.first(), let navLinks = try? firstNav.select("a[href]") {
                links.append(contentsOf: navLinks.array())
            }
        }
        if links.isEmpty, let allLinks = try? doc.select("a[href]") {
            links.append(contentsOf: allLinks.array())
        }

        for link in links {
            let href = (try? link.attr("href")) ?? ""
            guard !href.isEmpty, !href.hasPrefix("http://"), !href.hasPrefix("https://"), !href.hasPrefix("mailto:") else {
                continue
            }
            let rawText = (try? link.text()) ?? ""
            let labelText = Self.normalizeWhitespace(rawText)
            guard !labelText.isEmpty else { continue }

            let resolved = Self.resolveRelativePath(baseDir: baseDir, href: href)
            guard !resolved.path.isEmpty, resolved.path != tocRelativePath else { continue }

            let fileName = (resolved.path as NSString).lastPathComponent
            guard Self.isMeaningfulTitle(labelText, bookTitle: nil, fileName: fileName, allowTOCKeywords: true) else {
                continue
            }

            if tocTitlesByPath[resolved.path] == nil {
                tocTitlesByPath[resolved.path] = labelText
            }
        }
    }

    /// Check if an HTML document contains an EPUB 3 TOC `<nav>` element
    static func documentContainsTOCNav(_ doc: Document) -> Bool {
        guard let navs = try? doc.select("nav") else { return false }
        for nav in navs.array() {
            let epubType = (try? nav.attr("epub:type").lowercased()) ?? ""
            let role = (try? nav.attr("role").lowercased()) ?? ""
            let id = (try? nav.attr("id").lowercased()) ?? ""
            let cls = (try? nav.attr("class").lowercased()) ?? ""
            if epubType.contains("toc") || role.contains("doc-toc") || id == "toc" || cls.contains("toc") {
                return true
            }
        }
        return false
    }

    /// Extract a meaningful title from chapter HTML using multi-stage resolution:
    /// 1. TOC entry (`toc.ncx` / `nav.xhtml` / HTML TOC)
    /// 2. Document body headings (`h1`..`h6`) & subtitle combination
    /// 3. Document body title-classed / semantic elements (`.title`, `.chapter-title`, `[epub:type*=title]`, etc.)
    /// 4. Validated `<head><title>` (filtering out "알 수 없음", "Unknown", "Untitled", book title repeat, or raw file slugs)
    /// 5. First paragraph / title line in body (`validTexts.first` or `body` text)
    /// 6. Cover / TOC / Filename fallback
    private func extractChapterTitle(
        from doc: Document,
        chapterRelativePath: String,
        bookTitle: String,
        tocTitle: String?,
        validTexts: [String],
        isTableOfContents: Bool
    ) throws -> String {
        let fileName = (chapterRelativePath as NSString).lastPathComponent
        let fileStem = (fileName as NSString).deletingPathExtension

        // Extract candidate heading from the document body (h1..h6 or title-styled element)
        let bodyHeading = extractHeadingFromBody(from: doc, bookTitle: bookTitle, fileName: fileName, allowTOCKeywords: isTableOfContents)

        // 1. Official TOC entry for this chapter file
        if let tocTitle = tocTitle.map(Self.normalizeWhitespace),
           Self.isMeaningfulTitle(tocTitle, bookTitle: nil, fileName: fileName, allowTOCKeywords: true) {
            // If TOC entry is just a bare number (e.g. "1" or "01") and body has a fuller heading (e.g. "1. 서문"), prefer the fuller body heading
            if Self.isBareNumberTitle(tocTitle), let bodyHeading, bodyHeading.count > tocTitle.count {
                return bodyHeading
            }
            return tocTitle
        }

        // 2 & 3. Heading (h1-h6) or semantic title element inside the chapter body
        if let bodyHeading {
            return bodyHeading
        }

        // 4. Validated <head><title> (only if not placeholder, not file slug, and not simply repeating book title)
        if let titleTag = try? doc.select("head title, title").first() {
            let headTitle = Self.normalizeWhitespace((try? titleTag.text()) ?? "")
            if Self.isMeaningfulTitle(headTitle, bookTitle: bookTitle, fileName: fileName, allowTOCKeywords: isTableOfContents),
               headTitle.caseInsensitiveCompare(bookTitle) != .orderedSame {
                return headTitle
            }
        }

        // 5. First meaningful paragraph or opening line in the chapter body
        for text in validTexts {
            let cleaned = Self.normalizeWhitespace(text)
            if Self.isMeaningfulTitle(cleaned, bookTitle: nil, fileName: fileName, allowTOCKeywords: isTableOfContents) {
                return Self.formatOpeningTextAsTitle(cleaned)
            }
        }

        // Also check raw body text in case the chapter uses <div> or <span> instead of <p>/<h1>..<h6>
        if let bodyText = try? doc.body()?.text() {
            let cleanedBody = Self.normalizeWhitespace(bodyText)
            if Self.isMeaningfulTitle(cleanedBody, bookTitle: nil, fileName: fileName, allowTOCKeywords: isTableOfContents) {
                return Self.formatOpeningTextAsTitle(cleanedBody)
            }
        }

        // 6. Special page detection (TOC / Cover) & fallback
        if isTableOfContents {
            return "목차 (Table of Contents)"
        }

        let lowerPath = chapterRelativePath.lowercased()
        let hasImage = ((try? doc.select("img, svg, image").size()) ?? 0) > 0
        if lowerPath.contains("cover") || (validTexts.isEmpty && hasImage) {
            if let imgAlt = try? doc.select("img[alt]").first()?.attr("alt") {
                let cleanedAlt = Self.normalizeWhitespace(imgAlt)
                if Self.isMeaningfulTitle(cleanedAlt, bookTitle: bookTitle, fileName: fileName, allowTOCKeywords: false) {
                    return cleanedAlt
                }
            }
            if lowerPath.contains("cover") {
                return "표지 (Cover)"
            }
        }

        return fileStem.isEmpty ? chapterRelativePath : fileStem
    }

    /// Extract a chapter title from body headings (`h1`..`h6`) or title-styled elements
    private func extractHeadingFromBody(
        from doc: Document,
        bookTitle: String,
        fileName: String,
        allowTOCKeywords: Bool
    ) -> String? {
        // 1. Check standard headings h1..h6 in document order
        if let headings = try? doc.select("h1, h2, h3, h4, h5, h6") {
            var meaningfulHeadings: [String] = []
            for h in headings.array() {
                let text = Self.normalizeWhitespace((try? h.text()) ?? "")
                if Self.isMeaningfulTitle(text, bookTitle: bookTitle, fileName: fileName, allowTOCKeywords: allowTOCKeywords) {
                    if !meaningfulHeadings.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                        meaningfulHeadings.append(text)
                    }
                    if meaningfulHeadings.count >= 2 { break }
                }
            }

            if let first = meaningfulHeadings.first {
                // If the first heading is a short chapter/part prefix (e.g., "Chapter 1", "제1장", "01")
                // and there is a second heading immediately following (e.g., subtitle), combine them
                if meaningfulHeadings.count >= 2,
                   Self.isChapterPrefixHeading(first),
                   let second = meaningfulHeadings.dropFirst().first,
                   second.count <= 80,
                   !first.localizedCaseInsensitiveContains(second) {
                    return "\(first) · \(second)"
                }
                return first
            }
        }

        // 2. Check elements with semantic title attributes or CSS classes
        let titleSelectors = [
            "[epub\\:type*=title]",
            "[role=heading]",
            ".chapter-title",
            ".chap-title",
            ".ch-title",
            ".title",
            ".ct",
            "[class*=chapter-title]",
            "[class*=chaptitle]",
            "[class*=ch-title]",
            "[class*=heading]",
            "[class*=title]"
        ].joined(separator: ", ")

        if let candidates = try? doc.select(titleSelectors) {
            for candidate in candidates.array().prefix(8) {
                let text = Self.normalizeWhitespace((try? candidate.text()) ?? "")
                if text.count <= 120,
                   Self.isMeaningfulTitle(text, bookTitle: bookTitle, fileName: fileName, allowTOCKeywords: allowTOCKeywords),
                   text.caseInsensitiveCompare(bookTitle) != .orderedSame {
                    return text
                }
            }
        }

        return nil
    }

    // MARK: - Title Validation & Path Helpers

    /// Normalize consecutive whitespace and newlines into single spaces
    static func normalizeWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Format a paragraph or opening line into a clean chapter title (truncating cleanly if long)
    static func formatOpeningTextAsTitle(_ text: String, maxLength: Int = 52) -> String {
        let cleaned = normalizeWhitespace(text)
        guard cleaned.count > maxLength else { return cleaned }

        // Try to cut at the first sentence boundary if within reasonable length
        let sentenceDelimiters = CharacterSet(charactersIn: ".!?。！？")
        if let range = cleaned.rangeOfCharacter(from: sentenceDelimiters) {
            let distance = cleaned.distance(from: cleaned.startIndex, to: range.upperBound)
            if distance >= 6 && distance <= maxLength {
                return String(cleaned[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let index = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
        return String(cleaned[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Determine whether a candidate title is meaningful (i.e. NOT "알 수 없음", "Unknown", "Untitled", or a raw file slug)
    static func isMeaningfulTitle(
        _ rawText: String,
        bookTitle: String?,
        fileName: String,
        allowTOCKeywords: Bool
    ) -> Bool {
        let trimmed = normalizeWhitespace(rawText)
        guard !trimmed.isEmpty else { return false }

        let lowered = trimmed.lowercased()
        let compact = lowered.replacingOccurrences(of: " ", with: "")

        // Reject common "Unknown" / "Untitled" placeholders across languages
        let invalidPlaceholders: Set<String> = [
            "알수없음", "알 수 없음", "제목없음", "제목 없음", "무제", "미상", "미정", "없음",
            "unknown", "untitled", "untitleddocument", "untitled document",
            "notitle", "no title", "noname", "no name", "none", "null", "nil", "n/a",
            "default", "document", "chapter", "section", "page", "body", "xhtml", "html", "text", "index", "temp", "tmp",
            "不明", "無題", "タイトルなし", "未知", "未命名", "无标题"
        ]
        if invalidPlaceholders.contains(lowered) || invalidPlaceholders.contains(compact) {
            return false
        }

        if !allowTOCKeywords {
            let tocOnlyPlaceholders: Set<String> = ["차례", "목차", "contents", "table of contents", "toc"]
            if tocOnlyPlaceholders.contains(lowered) {
                return false
            }
        }

        // Reject if identical to raw filename or file stem (e.g. "Section0001.xhtml" or "index_split_000")
        let fileStem = (fileName as NSString).deletingPathExtension.lowercased()
        if !fileStem.isEmpty && (lowered == fileName.lowercased() || lowered == fileStem) {
            // Allow only if the file stem itself is a clean human-readable title with spaces, not a slug
            let slugPattern = #"^[a-z0-9_-]+$"#
            if fileStem.range(of: slugPattern, options: .regularExpression) != nil {
                return false
            }
        }

        // Reject Calibre / Sigil / InDesign auto-generated file slugs (e.g. "index_split_001", "part0001", "Section0002", "page_1")
        let autoSlugPattern = #"^(part|section|split|index_split|page|doc|item|file|xhtml|html|text|ch|chap|sec)[-_]*\d+(\.[a-z0-9]+)?$"#
        if lowered.range(of: autoSlugPattern, options: .regularExpression) != nil {
            return false
        }

        // Reject strings consisting solely of punctuation/symbols
        let strippedSymbols = trimmed.replacingOccurrences(of: "[\\p{P}\\p{S}\\s]", with: "", options: .regularExpression)
        if strippedSymbols.isEmpty {
            return false
        }

        return true
    }

    /// Check if a title is just a bare number (e.g. "1", "01", "I", "II")
    private static func isBareNumberTitle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4 else { return false }
        let pattern = #"^(\d+|[IVXLCDMivxlcdm]+)\.?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Check if a heading looks like a short chapter/part number prefix (e.g., "Chapter 1", "제1장", "Part I", "01")
    private static func isChapterPrefixHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 16 else { return false }
        if isBareNumberTitle(trimmed) { return true }
        let pattern = #"^(chapter|part|section|book|act|scene|제?\s*\d+\s*[장편부절화회]|프롤로그|에필로그|prologue|epilogue)\b[\s\dIVXLCDMivxlcdm.:-]*$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Resolve a relative href (possibly containing `#anchor` and `%20` encoding) against a base directory inside the EPUB
    static func resolveRelativePath(baseDir: String, href: String) -> (path: String, anchor: String?) {
        let parts = href.components(separatedBy: "#")
        let rawPath = parts.first ?? href
        let anchor: String? = parts.count > 1 ? parts.dropFirst().joined(separator: "#") : nil

        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        guard !decodedPath.isEmpty else {
            return ("", anchor)
        }

        let combined: String
        if baseDir.isEmpty {
            combined = decodedPath
        } else {
            combined = (baseDir as NSString).appendingPathComponent(decodedPath)
        }

        return (normalizeEPUBPath(combined), anchor)
    }

    /// Normalize an EPUB internal relative path by resolving `.` and `..` segments
    static func normalizeEPUBPath(_ path: String) -> String {
        var stack: [String] = []
        let unified = path.replacingOccurrences(of: "\\", with: "/")
        for component in unified.split(separator: "/") {
            let part = String(component)
            if part.isEmpty || part == "." { continue }
            if part == ".." {
                if !stack.isEmpty { stack.removeLast() }
            } else {
                stack.append(part)
            }
        }
        return stack.joined(separator: "/")
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
