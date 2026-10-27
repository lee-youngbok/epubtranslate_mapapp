import Foundation
import SwiftSoup

/// Service responsible for processing HTML content with translations
struct HTMLProcessor: Sendable {

    /// CSS selector for block elements eligible for translation
    static let translatableSelector = "p, h1, h2, h3, h4, h5, h6, li, blockquote"

    /// Check if an element contains nested translatable block elements (e.g., <blockquote><p>...</p></blockquote>)
    /// to avoid translating both the container and its inner children.
    static func hasNestedTranslatableBlock(_ element: Element) -> Bool {
        let tag = element.tagName().lowercased()
        guard tag == "blockquote" || tag == "li" else { return false }
        if let children = try? element.select(translatableSelector) {
            // children includes `element` itself, so count > 1 means nested blocks exist
            return children.size() > 1
        }
        return false
    }

    /// Represents a paragraph to be translated
    struct ParagraphInfo: Sendable {
        let index: Int
        let text: String
        let tagName: String
        let shouldSkip: Bool
        let anchorIds: [String]

        var isHeading: Bool {
            let lower = tagName.lowercased()
            return ["h1", "h2", "h3", "h4", "h5", "h6"].contains(lower)
        }
    }

    /// Extract text paragraphs from an HTML file
    func extractParagraphs(from fileURL: URL) throws -> (document: Document, paragraphs: [ParagraphInfo], isXHTML: Bool) {
        let data = try Data(contentsOf: fileURL)
        let htmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) ?? ""
        let isXHTML = htmlString.contains("xmlns") || fileURL.pathExtension.lowercased() == "xhtml"

        let document: Document
        if isXHTML {
            document = try SwiftSoup.parse(htmlString, "", Parser.xmlParser())
        } else {
            document = try SwiftSoup.parse(htmlString)
        }

        let elements = try document.select(Self.translatableSelector)
        var paragraphs: [ParagraphInfo] = []

        for (index, element) in elements.array().enumerated() {
            if Self.hasNestedTranslatableBlock(element) { continue }
            let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let anchorIds = Self.collectAnchorIds(for: element)
                paragraphs.append(ParagraphInfo(
                    index: index,
                    text: text,
                    tagName: element.tagName(),
                    shouldSkip: false,
                    anchorIds: anchorIds
                ))
            }
        }

        return (document, paragraphs, isXHTML)
    }

    /// Collect any `id` attributes on the element itself, its immediate parent container, or child anchor tags
    private static func collectAnchorIds(for element: Element) -> [String] {
        var ids: [String] = []
        if let ownId = try? element.attr("id"), !ownId.isEmpty {
            ids.append(ownId)
        }
        if let parentId = try? element.parent()?.attr("id"), !parentId.isEmpty, !ids.contains(parentId) {
            ids.append(parentId)
        }
        if let childIds = try? element.select("[id]") {
            for child in childIds.array() {
                if let cid = try? child.attr("id"), !cid.isEmpty, !ids.contains(cid) {
                    ids.append(cid)
                }
            }
        }
        return ids
    }

    /// Metadata for an embedded font asset placed in the EPUB archive
    struct EmbeddedFontAsset: Sendable, Hashable {
        let font: DownloadableFont
        /// Path relative to the EPUB root directory (e.g., "OEBPS/Fonts/Pretendard-Regular.otf")
        let epubRelativePath: String
        /// File extension (e.g., "otf", "ttf", "woff2", "woff")
        let fileExtension: String
    }

    /// Font styling configuration for source (original) and target (translated) texts
    struct FontStyleConfiguration: Sendable {
        /// Per-language font choices for original (source) text
        var sourceFontByLanguage: [String: FontSelection] = [:]
        /// Dominant source language code of the book
        var dominantSourceLanguageCode: String = "en"
        /// Font choice for translated text
        var targetFont: FontSelection = .original
        /// Embedded font files available inside the EPUB working copy
        var embeddedAssets: [DownloadableFont: EmbeddedFontAsset] = [:]
    }

    /// Apply translations to an already-parsed HTML document (or from fileURL) based on the selected mode
    func applyTranslations(
        document: Document,
        isXHTML: Bool,
        translations: [(original: String, translated: String, skipped: Bool, sourceLang: String)],
        mode: TranslationMode,
        tocLanguageMode: TOCLanguageMode = .original,
        resolvedChapterTitle: String? = nil,
        targetLanguageCode: String = "ko",
        chapterRelativePath: String = "",
        fontConfig: FontStyleConfiguration = FontStyleConfiguration()
    ) throws -> String {
        // Inject translation and typography CSS styles into <head>
        try injectStyles(
            into: document,
            mode: mode,
            chapterRelativePath: chapterRelativePath,
            fontConfig: fontConfig
        )

        // Update <head><title> if resolvedChapterTitle is provided
        if let resolvedTitle = resolvedChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolvedTitle.isEmpty,
           let titleElement = try? document.select("head title, title").first() {
            _ = try? titleElement.text(resolvedTitle)
        }

        let elements = try document.select(Self.translatableSelector)
        let textElements = elements.array().filter { element in
            guard !Self.hasNestedTranslatableBlock(element) else { return false }
            return (try? element.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?? false
        }

        var translationIndex = 0

        for element in textElements {
            guard translationIndex < translations.count else { break }

            let entry = translations[translationIndex]
            translationIndex += 1

            let sourceLang = entry.sourceLang.isEmpty ? fontConfig.dominantSourceLanguageCode : entry.sourceLang

            // If this element sits inside a <nav> TOC block, never duplicate it with bilingual/annotated;
            // apply either original or single-language replace according to tocLanguageMode.
            if Self.isInsideTOCNav(element) {
                switch tocLanguageMode {
                case .original:
                    try markAsOriginalElement(element, sourceLanguageCode: sourceLang)
                case .translated:
                    if entry.skipped {
                        try markAsOriginalElement(element, sourceLanguageCode: sourceLang)
                    } else {
                        try applyReplaceMode(element: element, translated: entry.translated, targetLanguageCode: targetLanguageCode)
                    }
                }
                continue
            }

            if entry.skipped {
                // Smart Skipping: keep original text, tag with original class & language for font styling
                try markAsOriginalElement(element, sourceLanguageCode: sourceLang)
                continue
            }

            switch mode {
            case .bilingual:
                try applyBilingualMode(
                    element: element,
                    translated: entry.translated,
                    sourceLanguageCode: sourceLang,
                    targetLanguageCode: targetLanguageCode
                )
            case .replace:
                try applyReplaceMode(element: element, translated: entry.translated, targetLanguageCode: targetLanguageCode)
            case .annotated:
                try applyAnnotatedMode(
                    element: element,
                    original: entry.original,
                    translated: entry.translated,
                    sourceLanguageCode: sourceLang,
                    targetLanguageCode: targetLanguageCode
                )
            }
        }

        return try serializeDocument(document, isXHTML: isXHTML)
    }

    /// Serialize a SwiftSoup Document back to XHTML or HTML string safely
    func serializeDocument(_ document: Document, isXHTML: Bool) throws -> String {
        if isXHTML {
            var output = try document.outerHtml()
            // Fix XML parsing errors in EPUB readers caused by undefined HTML entities.
            // EPUB readers use strict XML parsers which do not recognize &nbsp; without a DTD.
            output = output
                .replacingOccurrences(of: "&nbsp;", with: "&#160;")
                .replacingOccurrences(of: "&copy;", with: "&#169;")
                .replacingOccurrences(of: "&mdash;", with: "&#8212;")
                .replacingOccurrences(of: "&ndash;", with: "&#8211;")
                .replacingOccurrences(of: "&ldquo;", with: "&#8220;")
                .replacingOccurrences(of: "&rdquo;", with: "&#8221;")
                .replacingOccurrences(of: "&lsquo;", with: "&#8216;")
                .replacingOccurrences(of: "&rsquo;", with: "&#8217;")
                .replacingOccurrences(of: "&hellip;", with: "&#8230;")
                .replacingOccurrences(of: "&middot;", with: "&#183;")
            return output
        } else {
            return try document.html()
        }
    }

    /// Check if an element has an ancestor `<nav>` element
    private static func isInsideTOCNav(_ element: Element) -> Bool {
        var current: Element? = element.parent()
        while let node = current {
            if node.tagName().lowercased() == "nav" {
                return true
            }
            current = node.parent()
        }
        return false
    }

    // MARK: - Mode Implementations

    private func markAsOriginalElement(_ element: Element, sourceLanguageCode: String) throws {
        let existingClass = (try? element.attr("class")) ?? ""
        let classes = existingClass.split(separator: " ").map(String.init)
        if !classes.contains("epub-original") {
            let combinedClass = existingClass.isEmpty ? "epub-original" : "\(existingClass) epub-original"
            try element.attr("class", combinedClass)
        }
        let existingLang = (try? element.attr("lang")) ?? ""
        if existingLang.isEmpty && !sourceLanguageCode.isEmpty {
            try element.attr("lang", sourceLanguageCode)
        }
    }

    /// Bilingual Mode: Insert translated paragraph after original
    private func applyBilingualMode(
        element: Element,
        translated: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) throws {
        let tagName = element.tagName()
        let existingClass = (try? element.attr("class")) ?? ""

        // Mark original element with .epub-original and source language
        try markAsOriginalElement(element, sourceLanguageCode: sourceLanguageCode)

        let translatedElement = Element(Tag(tagName), "")
        let combinedClass = existingClass.isEmpty ? "epub-translated" : "\(existingClass) epub-translated"
        try translatedElement.attr("class", combinedClass)
        try translatedElement.attr("lang", targetLanguageCode)
        try translatedElement.text(translated)

        try element.after(translatedElement.outerHtml())
    }

    /// Replace Mode: Replace original text with translation while preserving `<a href="...">` links and anchor IDs
    private func applyReplaceMode(element: Element, translated: String, targetLanguageCode: String) throws {
        // Preserve any child anchor IDs (e.g. <h1><a id="ch1"></a>Chapter 1</h1>)
        let ownId = (try? element.attr("id")) ?? ""
        var extraAnchorIds: [String] = []
        if let childWithIds = try? element.select("[id]") {
            for child in childWithIds.array() where child !== element {
                if let cid = try? child.attr("id"), !cid.isEmpty {
                    extraAnchorIds.append(cid)
                }
            }
        }

        // If the element wraps a single <a href="..."> link whose text matches the element's text,
        // update the <a> tag's text so the hyperlink stays intact.
        if let links = try? element.select("a[href]"), links.size() == 1, let singleLink = links.first() {
            let elemText = EPUBParser.normalizeWhitespace((try? element.text()) ?? "")
            let linkText = EPUBParser.normalizeWhitespace((try? singleLink.text()) ?? "")
            if !elemText.isEmpty && elemText == linkText {
                try singleLink.text(translated)
                let existingClass = (try? element.attr("class")) ?? ""
                let combinedClass = existingClass.isEmpty ? "epub-replaced" : "\(existingClass) epub-replaced"
                try element.attr("class", combinedClass)
                try element.attr("lang", targetLanguageCode)
                return
            }
        }

        try element.text(translated)

        // Restore child anchor IDs if any were inside the replaced element
        if !extraAnchorIds.isEmpty {
            var remainingIds = extraAnchorIds
            if ownId.isEmpty, let firstId = remainingIds.first {
                try element.attr("id", firstId)
                remainingIds.removeFirst()
            }
            for anchorId in remainingIds {
                let escapedId = escapeHTML(anchorId)
                try element.prepend("<a id=\"\(escapedId)\"></a>")
            }
        }

        let existingClass = (try? element.attr("class")) ?? ""
        let combinedClass = existingClass.isEmpty ? "epub-replaced" : "\(existingClass) epub-replaced"
        try element.attr("class", combinedClass)
        try element.attr("lang", targetLanguageCode)
    }

    /// Annotated Mode: Use HTML5 <details>/<summary> for expandable original text while preserving anchor IDs
    private func applyAnnotatedMode(
        element: Element,
        original: String,
        translated: String,
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) throws {
        let tagName = element.tagName()
        let escapedSourceLang = escapeHTML(sourceLanguageCode)
        let escapedTargetLang = escapeHTML(targetLanguageCode)

        // Collect all IDs on this element and its children so TOC #anchor links remain valid
        var allIds: [String] = []
        if let ownId = try? element.attr("id"), !ownId.isEmpty {
            allIds.append(ownId)
        }
        if let childIds = try? element.select("[id]") {
            for child in childIds.array() {
                if let cid = try? child.attr("id"), !cid.isEmpty, !allIds.contains(cid) {
                    allIds.append(cid)
                }
            }
        }

        // Inside <ul>/<ol>, wrapping <li> in a <div> is invalid HTML; keep content inside the <li> if tag is li
        if tagName.lowercased() == "li" {
            let extraAnchorsHTML = allIds.dropFirst().map { "<a id=\"\(escapeHTML($0))\"></a>" }.joined()
            if let firstId = allIds.first {
                try element.attr("id", firstId)
            }
            let innerHTML = """
            \(extraAnchorsHTML)<span class="epub-translated-main" lang="\(escapedTargetLang)">\(escapeHTML(translated))</span>
            <details class="epub-original-details">
                <summary class="epub-show-original">▶ 원문 보기</summary>
                <span class="epub-original-text" lang="\(escapedSourceLang)">\(escapeHTML(original))</span>
            </details>
            """
            try element.html(innerHTML)
        } else {
            let primaryIdAttr = allIds.first.map { " id=\"\(escapeHTML($0))\"" } ?? ""
            let extraAnchorsHTML = allIds.dropFirst().map { "<a id=\"\(escapeHTML($0))\"></a>" }.joined()
            let annotatedHTML = """
            <div class="epub-annotated-block"\(primaryIdAttr)>
                \(extraAnchorsHTML)<\(tagName) class="epub-translated-main" lang="\(escapedTargetLang)">\(escapeHTML(translated))</\(tagName)>
                <details class="epub-original-details">
                    <summary class="epub-show-original">▶ 원문 보기</summary>
                    <\(tagName) class="epub-original-text" lang="\(escapedSourceLang)">\(escapeHTML(original))</\(tagName)>
                </details>
            </div>
            """
            try element.before(annotatedHTML)
            try element.remove()
        }
    }

    // MARK: - CSS Injection

    /// Inject CSS styles for translated content and custom typography
    private func injectStyles(
        into document: Document,
        mode: TranslationMode,
        chapterRelativePath: String,
        fontConfig: FontStyleConfiguration
    ) throws {
        var cssParts: [String] = []

        // 1. @font-face declarations for any embedded downloadable fonts
        var referencedFonts = Set<DownloadableFont>()
        for selection in fontConfig.sourceFontByLanguage.values {
            if case .downloadable(let font) = selection {
                referencedFonts.insert(font)
            }
        }
        if case .downloadable(let font) = fontConfig.targetFont {
            referencedFonts.insert(font)
        }

        for font in DownloadableFont.allCases where referencedFonts.contains(font) {
            if let asset = fontConfig.embeddedAssets[font] {
                let relativeFontURL = Self.relativePath(from: chapterRelativePath, to: asset.epubRelativePath)
                let format = FontManager.cssFormat(forExtension: asset.fileExtension)
                cssParts.append("""
                @font-face {
                    font-family: '\(font.cssFamilyName)';
                    src: url('\(relativeFontURL)') format('\(format)');
                    font-weight: normal;
                    font-style: normal;
                }
                """)
            }
        }

        // 2. Base mode styles
        switch mode {
        case .bilingual:
            cssParts.append("""
            .epub-translated {
                /* 본문과 동일한 양식을 위해 기존 인용문 스타일 제거 */
            }
            """)
        case .replace:
            cssParts.append("""
            .epub-replaced {
                /* Replaced text, no special styling needed */
            }
            """)
        case .annotated:
            cssParts.append("""
            .epub-annotated-block {
                margin-bottom: 1em;
            }
            .epub-translated-main {
                margin-bottom: 0.2em;
            }
            .epub-original-details {
                margin-top: 0.2em;
                margin-bottom: 0.5em;
            }
            .epub-show-original {
                cursor: pointer;
                color: #888;
                font-size: 0.85em;
                font-style: italic;
                list-style: none;
                padding: 0.2em 0;
            }
            .epub-show-original::-webkit-details-marker {
                display: none;
            }
            .epub-original-text {
                color: #666;
                font-size: 0.9em;
                border-left: 2px solid #ccc;
                padding-left: 0.8em;
                margin-top: 0.3em;
            }
            """)
        }

        // 3. Source (Original) Text Font Rules per Language
        let activeSourceFonts = fontConfig.sourceFontByLanguage.filter { !$0.value.isOriginal }
        for (langCode, selection) in activeSourceFonts.sorted(by: { $0.key < $1.key }) {
            guard let fontFamilyRule = selection.cssFontFamilyRule else { continue }
            if langCode == fontConfig.dominantSourceLanguageCode && activeSourceFonts.count == 1 {
                cssParts.append("""
                .epub-original, .epub-original *,
                .epub-original-text, .epub-original-text *,
                .epub-original[lang^=\"\(langCode)\"], .epub-original[lang^=\"\(langCode)\"] *,
                .epub-original-text[lang^=\"\(langCode)\"], .epub-original-text[lang^=\"\(langCode)\"] * {
                    font-family: \(fontFamilyRule) !important;
                }
                """)
            } else {
                cssParts.append("""
                .epub-original[lang^=\"\(langCode)\"], .epub-original[lang^=\"\(langCode)\"] *,
                .epub-original-text[lang^=\"\(langCode)\"], .epub-original-text[lang^=\"\(langCode)\"] * {
                    font-family: \(fontFamilyRule) !important;
                }
                """)
            }
        }

        // 4. Target (Translated) Text Font Rule
        if let targetFontFamilyRule = fontConfig.targetFont.cssFontFamilyRule {
            cssParts.append("""
            .epub-translated, .epub-translated *,
            .epub-replaced, .epub-replaced *,
            .epub-translated-main, .epub-translated-main * {
                font-family: \(targetFontFamilyRule) !important;
            }
            """)
        }

        let css = cssParts.joined(separator: "\n")

        // Find or create <head> and append <style>
        if let head = try document.select("head").first() {
            let styleElement = Element(Tag("style"), "")
            try styleElement.attr("type", "text/css")
            try styleElement.append(css)
            try head.appendChild(styleElement)
        }
    }

    /// Compute the relative path from a chapter file's directory to a target file inside the EPUB root
    static func relativePath(from chapterRelativePath: String, to targetRelativePath: String) -> String {
        let chapterDir = (chapterRelativePath as NSString).deletingLastPathComponent
        let fromComponents = chapterDir.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        let toComponents = targetRelativePath.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }

        var commonCount = 0
        while commonCount < fromComponents.count &&
              commonCount < toComponents.count &&
              fromComponents[commonCount] == toComponents[commonCount] {
            commonCount += 1
        }

        let upMoves = Array(repeating: "..", count: fromComponents.count - commonCount)
        let downMoves = Array(toComponents.dropFirst(commonCount))
        let result = (upMoves + downMoves).joined(separator: "/")
        return result.isEmpty ? targetRelativePath : result
    }

    // MARK: - Table of Contents (TOC) Extraction & Single-Language Translation

    /// Represents a single entry in the EPUB Table of Contents (NCX or HTML/Nav TOC)
    struct TOCSourceEntry: Sendable {
        let text: String
        let targetPath: String
        let targetAnchor: String?
    }

    /// Collect all translatable TOC entries from `toc.ncx`, `nav.xhtml`, and any HTML TOC pages
    func collectTOCEntries(workingDir: URL, book: EPUBBook) -> [TOCSourceEntry] {
        var entries: [TOCSourceEntry] = []

        // 1. Collect from EPUB 2 NCX (toc.ncx)
        if let ncxRelPath = book.ncxRelativePath {
            let ncxURL = workingDir.appendingPathComponent(ncxRelPath)
            if let data = try? Data(contentsOf: ncxURL),
               let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii),
               let ncxDoc = try? SwiftSoup.parse(content, "", Parser.xmlParser()) {
                let baseDir = (ncxRelPath as NSString).deletingLastPathComponent
                if let allElements = try? ncxDoc.getAllElements() {
                    for el in allElements.array() {
                        let tag = el.tagName().lowercased()
                        guard tag == "navpoint" || tag.hasSuffix(":navpoint") else { continue }
                        var labelText = ""
                        var contentSrc = ""
                        for child in el.children().array() {
                            let cTag = child.tagName().lowercased()
                            if (cTag == "navlabel" || cTag.hasSuffix(":navlabel")) && labelText.isEmpty {
                                labelText = EPUBParser.normalizeWhitespace((try? child.text()) ?? "")
                            } else if (cTag == "content" || cTag.hasSuffix(":content")) && contentSrc.isEmpty {
                                contentSrc = (try? child.attr("src")) ?? ""
                            }
                        }
                        if !labelText.isEmpty {
                            let resolved = EPUBParser.resolveRelativePath(baseDir: baseDir, href: contentSrc)
                            entries.append(TOCSourceEntry(
                                text: labelText,
                                targetPath: resolved.path,
                                targetAnchor: resolved.anchor
                            ))
                        }
                    }
                }
            }
        }

        // 2. Collect from EPUB 3 Nav and HTML TOC pages
        var htmlTocPaths = Set(book.htmlTocRelativePaths)
        if let navPath = book.navRelativePath {
            htmlTocPaths.insert(navPath)
        }
        for chapter in book.chapters where chapter.isTableOfContents {
            htmlTocPaths.insert(chapter.relativePath)
        }

        for tocRelPath in htmlTocPaths.sorted() {
            let tocURL = workingDir.appendingPathComponent(tocRelPath)
            guard let data = try? Data(contentsOf: tocURL) else { continue }
            let htmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) ?? ""
            let isXHTML = htmlString.contains("xmlns") || tocURL.pathExtension.lowercased() == "xhtml"
            guard let doc = try? (isXHTML ? SwiftSoup.parse(htmlString, "", Parser.xmlParser()) : SwiftSoup.parse(htmlString)) else {
                continue
            }

            let baseDir = (tocRelPath as NSString).deletingLastPathComponent

            // Head <title>
            if let headTitle = try? doc.select("head title, title").first()?.text() {
                let cleaned = EPUBParser.normalizeWhitespace(headTitle)
                if !cleaned.isEmpty {
                    entries.append(TOCSourceEntry(text: cleaned, targetPath: "", targetAnchor: nil))
                }
            }

            // All <a href="..."> links
            if let links = try? doc.select("a[href]") {
                for link in links.array() {
                    let href = (try? link.attr("href")) ?? ""
                    let text = EPUBParser.normalizeWhitespace((try? link.text()) ?? "")
                    guard !text.isEmpty else { continue }
                    let resolved = EPUBParser.resolveRelativePath(baseDir: baseDir, href: href)
                    entries.append(TOCSourceEntry(
                        text: text,
                        targetPath: resolved.path,
                        targetAnchor: resolved.anchor
                    ))
                }
            }

            // Non-link headings or labels on the TOC page (e.g., <h1>Table of Contents</h1>)
            if let blocks = try? doc.select(Self.translatableSelector) {
                for block in blocks.array() {
                    if Self.hasNestedTranslatableBlock(block) { continue }
                    let hasLink = ((try? block.select("a[href]").size()) ?? 0) > 0
                    guard !hasLink else { continue }
                    let text = EPUBParser.normalizeWhitespace((try? block.text()) ?? "")
                    if !text.isEmpty {
                        entries.append(TOCSourceEntry(text: text, targetPath: "", targetAnchor: nil))
                    }
                }
            }
        }

        return entries
    }

    /// Apply the selected `TOCLanguageMode` (`.original` or `.translated`) to `toc.ncx`, `nav.xhtml`, and HTML TOC pages.
    /// Ensures the TOC is strictly in a single language (never bilingual or annotated) and preserves all hyperlinks.
    func applyTableOfContents(
        workingDir: URL,
        book: EPUBBook,
        tocMode: TOCLanguageMode,
        targetLanguageCode: String,
        customBookTitle: String,
        fontConfig: FontStyleConfiguration,
        resolveTranslation: (_ originalText: String, _ targetPath: String, _ targetAnchor: String?) -> String?
    ) {
        // 1. Update EPUB 2 NCX (toc.ncx) when tocMode == .translated (or update docTitle if customBookTitle was set)
        if let ncxRelPath = book.ncxRelativePath {
            updateNCXFile(
                at: workingDir.appendingPathComponent(ncxRelPath),
                ncxRelativePath: ncxRelPath,
                tocMode: tocMode,
                customBookTitle: customBookTitle,
                resolveTranslation: resolveTranslation
            )
        }

        // 2. Update EPUB 3 Nav and HTML TOC pages
        var htmlTocPaths = Set(book.htmlTocRelativePaths)
        if let navPath = book.navRelativePath {
            htmlTocPaths.insert(navPath)
        }
        for chapter in book.chapters where chapter.isTableOfContents {
            htmlTocPaths.insert(chapter.relativePath)
        }

        for tocRelPath in htmlTocPaths.sorted() {
            updateHTMLTOCFile(
                at: workingDir.appendingPathComponent(tocRelPath),
                tocRelativePath: tocRelPath,
                tocMode: tocMode,
                targetLanguageCode: targetLanguageCode,
                fontConfig: fontConfig,
                resolveTranslation: resolveTranslation
            )
        }
    }

    /// Update `toc.ncx` in-place while preserving exact XML structure, DOCTYPE, and self-closing `<content>` tags
    private func updateNCXFile(
        at ncxURL: URL,
        ncxRelativePath: String,
        tocMode: TOCLanguageMode,
        customBookTitle: String,
        resolveTranslation: (_ originalText: String, _ targetPath: String, _ targetAnchor: String?) -> String?
    ) {
        guard var ncxContent = try? String(contentsOf: ncxURL, encoding: .utf8) else { return }

        // Update <docTitle><text>...</text></docTitle> if customBookTitle is provided
        let trimmedBookTitle = customBookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBookTitle.isEmpty {
            let docTitlePattern = #"(<(?:[a-zA-Z0-9_]+:)?docTitle[^>]*>\s*<(?:[a-zA-Z0-9_]+:)?text[^>]*>)([\s\S]*?)(</(?:[a-zA-Z0-9_]+:)?text>\s*</(?:[a-zA-Z0-9_]+:)?docTitle>)"#
            if let regex = try? NSRegularExpression(pattern: docTitlePattern, options: []) {
                let escapedTitle = NSRegularExpression.escapedTemplate(for: escapeHTML(trimmedBookTitle))
                let range = NSRange(ncxContent.startIndex..<ncxContent.endIndex, in: ncxContent)
                ncxContent = regex.stringByReplacingMatches(in: ncxContent, options: [], range: range, withTemplate: "$1\(escapedTitle)$3")
            }
        }

        guard tocMode == .translated else {
            try? ncxContent.write(to: ncxURL, atomically: true, encoding: .utf8)
            return
        }

        let baseDir = (ncxRelativePath as NSString).deletingLastPathComponent
        // Match each <navLabel><text>...</text></navLabel> along with its following <content src="..."/>
        let navLabelPattern = #"(<(?:[a-zA-Z0-9_]+:)?navLabel[^>]*>\s*<(?:[a-zA-Z0-9_]+:)?text[^>]*>)([\s\S]*?)(</(?:[a-zA-Z0-9_]+:)?text>\s*</(?:[a-zA-Z0-9_]+:)?navLabel>(?:[\s\S]*?<(?:[a-zA-Z0-9_]+:)?content[^>]*src=["']([^"']+)["'])?)"#
        guard let regex = try? NSRegularExpression(pattern: navLabelPattern, options: []) else { return }

        let matches = regex.matches(in: ncxContent, options: [], range: NSRange(ncxContent.startIndex..<ncxContent.endIndex, in: ncxContent))
        for match in matches.reversed() {
            guard match.numberOfRanges >= 4,
                  let textRange = Range(match.range(at: 2), in: ncxContent) else {
                continue
            }
            let rawXMLText = String(ncxContent[textRange])
            let unescapedText = (try? SwiftSoup.parse(rawXMLText).text()) ?? rawXMLText
            let normalizedText = EPUBParser.normalizeWhitespace(unescapedText)
            guard !normalizedText.isEmpty else { continue }

            var contentSrc = ""
            if match.numberOfRanges >= 5,
               match.range(at: 4).location != NSNotFound,
               let srcRange = Range(match.range(at: 4), in: ncxContent) {
                contentSrc = String(ncxContent[srcRange])
            }

            let resolved = EPUBParser.resolveRelativePath(baseDir: baseDir, href: contentSrc)
            if let translated = resolveTranslation(normalizedText, resolved.path, resolved.anchor),
               !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let escapedTranslated = escapeHTML(translated.trimmingCharacters(in: .whitespacesAndNewlines))
                ncxContent.replaceSubrange(textRange, with: escapedTranslated)
            }
        }

        try? ncxContent.write(to: ncxURL, atomically: true, encoding: .utf8)
    }

    /// Update an EPUB 3 Navigation Document (`nav.xhtml`) or HTML TOC page according to `tocMode`
    private func updateHTMLTOCFile(
        at tocURL: URL,
        tocRelativePath: String,
        tocMode: TOCLanguageMode,
        targetLanguageCode: String,
        fontConfig: FontStyleConfiguration,
        resolveTranslation: (_ originalText: String, _ targetPath: String, _ targetAnchor: String?) -> String?
    ) {
        guard let data = try? Data(contentsOf: tocURL) else { return }
        let htmlString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .macOSRoman) ?? ""
        let isXHTML = htmlString.contains("xmlns") || tocURL.pathExtension.lowercased() == "xhtml"
        guard let doc = try? (isXHTML ? SwiftSoup.parse(htmlString, "", Parser.xmlParser()) : SwiftSoup.parse(htmlString)) else {
            return
        }

        try? injectStyles(
            into: doc,
            mode: .replace,
            chapterRelativePath: tocRelativePath,
            fontConfig: fontConfig
        )

        let baseDir = (tocRelativePath as NSString).deletingLastPathComponent

        switch tocMode {
        case .original:
            // Keep TOC in original language; tag elements with .epub-original for source font styling
            if let blocks = try? doc.select(Self.translatableSelector) {
                for block in blocks.array() {
                    if Self.hasNestedTranslatableBlock(block) { continue }
                    try? markAsOriginalElement(block, sourceLanguageCode: fontConfig.dominantSourceLanguageCode)
                }
            }

        case .translated:
            // Update <head><title>
            if let titleEl = try? doc.select("head title, title").first() {
                let rawTitle = EPUBParser.normalizeWhitespace((try? titleEl.text()) ?? "")
                if !rawTitle.isEmpty,
                   let translatedTitle = resolveTranslation(rawTitle, "", nil),
                   !translatedTitle.isEmpty {
                    _ = try? titleEl.text(translatedTitle)
                }
            }

            // Update all <a href="..."> links while preserving href and structure
            if let links = try? doc.select("a[href]") {
                for link in links.array() {
                    let href = (try? link.attr("href")) ?? ""
                    let rawText = EPUBParser.normalizeWhitespace((try? link.text()) ?? "")
                    guard !rawText.isEmpty else { continue }
                    let resolved = EPUBParser.resolveRelativePath(baseDir: baseDir, href: href)
                    if let translated = resolveTranslation(rawText, resolved.path, resolved.anchor),
                       !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? updateLinkText(link, with: translated, targetLanguageCode: targetLanguageCode)
                    }
                }
            }

            // Update non-link headings/blocks on the TOC page (e.g. <h1>Table of Contents</h1>)
            if let blocks = try? doc.select(Self.translatableSelector) {
                for block in blocks.array() {
                    if Self.hasNestedTranslatableBlock(block) { continue }
                    let hasLink = ((try? block.select("a[href]").size()) ?? 0) > 0
                    if hasLink {
                        let existingClass = (try? block.attr("class")) ?? ""
                        if !existingClass.contains("epub-replaced") {
                            let combined = existingClass.isEmpty ? "epub-replaced" : "\(existingClass) epub-replaced"
                            _ = try? block.attr("class", combined)
                        }
                        _ = try? block.attr("lang", targetLanguageCode)
                        continue
                    }

                    let rawText = EPUBParser.normalizeWhitespace((try? block.text()) ?? "")
                    guard !rawText.isEmpty else { continue }
                    if let translated = resolveTranslation(rawText, "", nil),
                       !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? applyReplaceMode(element: block, translated: translated, targetLanguageCode: targetLanguageCode)
                    }
                }
            }
        }

        if let output = try? serializeDocument(doc, isXHTML: isXHTML) {
            try? output.write(to: tocURL, atomically: true, encoding: .utf8)
        }
    }

    /// Update the text of an `<a href="...">` element while preserving its attributes and any single wrapper `<span>`
    private func updateLinkText(_ link: Element, with translated: String, targetLanguageCode: String) throws {
        if link.children().size() == 1,
           let singleChild = link.children().first(),
           singleChild.tagName().lowercased() == "span",
           EPUBParser.normalizeWhitespace((try? singleChild.text()) ?? "") == EPUBParser.normalizeWhitespace((try? link.text()) ?? "") {
            try singleChild.text(translated)
        } else {
            try link.text(translated)
        }
        let existingClass = (try? link.attr("class")) ?? ""
        if !existingClass.contains("epub-replaced") {
            let combined = existingClass.isEmpty ? "epub-replaced" : "\(existingClass) epub-replaced"
            try link.attr("class", combined)
        }
        try link.attr("lang", targetLanguageCode)
    }

    // MARK: - Helpers

    /// Escape HTML special characters
    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
