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

    /// Apply translations to an already-parsed HTML document (or from fileURL) based on the selected mode
    func applyTranslations(
        document: Document,
        isXHTML: Bool,
        translations: [(original: String, translated: String, skipped: Bool)],
        mode: TranslationMode,
        targetLanguageCode: String = "ko"
    ) throws -> String {
        // Inject translation CSS styles into <head>
        try injectStyles(into: document, mode: mode)

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

            if entry.skipped {
                // Smart Skipping: keep original, no modification needed
                continue
            }

            switch mode {
            case .bilingual:
                try applyBilingualMode(element: element, translated: entry.translated, targetLanguageCode: targetLanguageCode)
            case .replace:
                try applyReplaceMode(element: element, translated: entry.translated, targetLanguageCode: targetLanguageCode)
            case .annotated:
                try applyAnnotatedMode(element: element, original: entry.original, translated: entry.translated, targetLanguageCode: targetLanguageCode)
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

    /// Bilingual Mode: Insert translated paragraph after original
    private func applyBilingualMode(element: Element, translated: String, targetLanguageCode: String) throws {
        let tagName = element.tagName()
        let translatedElement = Element(Tag(tagName), "")
        let existingClass = (try? element.attr("class")) ?? ""
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
    private func applyAnnotatedMode(element: Element, original: String, translated: String, targetLanguageCode: String) throws {
        let tagName = element.tagName()
        // Inside <ul>/<ol>, wrapping <li> in a <div> is invalid HTML; keep content inside the <li> if tag is li
        if tagName.lowercased() == "li" {
            let innerHTML = """
            <span class="epub-translated-main" lang="\(escapeHTML(targetLanguageCode))">\(escapeHTML(translated))</span>
            <details class="epub-original-details">
                <summary class="epub-show-original">▶ 원문 보기</summary>
                <span class="epub-original-text">\(escapeHTML(original))</span>
            </details>
            """
            try element.html(innerHTML)
        } else {
            let annotatedHTML = """
            <div class="epub-annotated-block">
                <\(tagName) class="epub-translated-main" lang="\(escapeHTML(targetLanguageCode))">\(escapeHTML(translated))</\(tagName)>
                <details class="epub-original-details">
                    <summary class="epub-show-original">▶ 원문 보기</summary>
                    <\(tagName) class="epub-original-text">\(escapeHTML(original))</\(tagName)>
                </details>
            </div>
            """
            try element.before(annotatedHTML)
            try element.remove()
        }
    }

    // MARK: - CSS Injection

    /// Inject CSS styles for translated content
    private func injectStyles(into document: Document, mode: TranslationMode) throws {
        let css: String

        switch mode {
        case .bilingual:
            css = """
            .epub-translated {
                /* 본문과 동일한 양식을 위해 기존 인용문 스타일 제거 */
            }
            """
        case .replace:
            css = """
            .epub-replaced {
                /* Replaced text, no special styling needed */
            }
            """
        case .annotated:
            css = """
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
            """
        }

        // Find or create <head> and append <style>
        if let head = try document.select("head").first() {
            let styleElement = Element(Tag("style"), "")
            try styleElement.attr("type", "text/css")
            try styleElement.append(css)
            try head.appendChild(styleElement)
        }
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
