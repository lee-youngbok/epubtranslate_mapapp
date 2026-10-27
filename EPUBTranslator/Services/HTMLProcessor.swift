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
                paragraphs.append(ParagraphInfo(
                    index: index,
                    text: text,
                    tagName: element.tagName(),
                    shouldSkip: false
                ))
            }
        }

        return (document, paragraphs, isXHTML)
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

    /// Replace Mode: Replace original text with translation
    private func applyReplaceMode(element: Element, translated: String, targetLanguageCode: String) throws {
        try element.text(translated)
        let existingClass = (try? element.attr("class")) ?? ""
        let combinedClass = existingClass.isEmpty ? "epub-replaced" : "\(existingClass) epub-replaced"
        try element.attr("class", combinedClass)
        try element.attr("lang", targetLanguageCode)
    }

    /// Annotated Mode: Use HTML5 <details>/<summary> for expandable original text
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

        // Inside <ul>/<ol>, wrapping <li> in a <div> is invalid HTML; keep content inside the <li> if tag is li
        if tagName.lowercased() == "li" {
            let innerHTML = """
            <span class="epub-translated-main" lang="\(escapedTargetLang)">\(escapeHTML(translated))</span>
            <details class="epub-original-details">
                <summary class="epub-show-original">▶ 원문 보기</summary>
                <span class="epub-original-text" lang="\(escapedSourceLang)">\(escapeHTML(original))</span>
            </details>
            """
            try element.html(innerHTML)
        } else {
            let annotatedHTML = """
            <div class="epub-annotated-block">
                <\(tagName) class="epub-translated-main" lang="\(escapedTargetLang)">\(escapeHTML(translated))</\(tagName)>
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
