import Foundation
import SwiftSoup

/// Service responsible for processing HTML content with translations
struct HTMLProcessor: Sendable {

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
        let htmlString = String(data: data, encoding: .utf8) ?? ""
        let isXHTML = htmlString.contains("xmlns") || fileURL.pathExtension.lowercased() == "xhtml"

        let document: Document
        if isXHTML {
            document = try SwiftSoup.parse(htmlString, "", Parser.xmlParser())
        } else {
            document = try SwiftSoup.parse(htmlString)
        }

        let elements = try document.select("p, h1, h2, h3, h4, h5, h6")
        var paragraphs: [ParagraphInfo] = []

        for (index, element) in elements.array().enumerated() {
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

    /// Apply translations to the HTML document based on the selected mode
    func applyTranslations(
        fileURL: URL,
        translations: [(original: String, translated: String, skipped: Bool)],
        mode: TranslationMode
    ) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let htmlString = String(data: data, encoding: .utf8) ?? ""
        let isXHTML = htmlString.contains("xmlns") || fileURL.pathExtension.lowercased() == "xhtml"

        let document: Document
        if isXHTML {
            document = try SwiftSoup.parse(htmlString, "", Parser.xmlParser())
        } else {
            document = try SwiftSoup.parse(htmlString)
        }

        // Inject translation CSS styles into <head>
        try injectStyles(into: document, mode: mode)

        let elements = try document.select("p, h1, h2, h3, h4, h5, h6")
        let textElements = elements.array().filter { element in
            (try? element.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?? false
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
                try applyBilingualMode(element: element, translated: entry.translated, isXHTML: isXHTML)
            case .replace:
                try applyReplaceMode(element: element, translated: entry.translated)
            case .annotated:
                try applyAnnotatedMode(element: element, original: entry.original, translated: entry.translated, isXHTML: isXHTML)
            }
        }

        if isXHTML {
            return try document.outerHtml()
        } else {
            return try document.html()
        }
    }

    // MARK: - Mode Implementations

    /// Bilingual Mode: Insert translated paragraph after original
    private func applyBilingualMode(element: Element, translated: String, isXHTML: Bool) throws {
        let translatedElement = Element(Tag("p"), "")
        try translatedElement.attr("class", "epub-translated")
        try translatedElement.attr("lang", "translated")
        try translatedElement.text(translated)

        // Add a subtle separator
        try element.after(translatedElement.outerHtml())
    }

    /// Replace Mode: Replace original text with translation
    private func applyReplaceMode(element: Element, translated: String) throws {
        // Preserve child element structure but replace text
        try element.text(translated)
        try element.attr("class",
            ((try? element.attr("class")) ?? "") + " epub-replaced"
        )
    }

    /// Annotated Mode: Use HTML5 <details>/<summary> for expandable original text
    private func applyAnnotatedMode(element: Element, original: String, translated: String, isXHTML: Bool) throws {
        let tagName = element.tagName()

        // Build the annotated HTML using <details>/<summary> for EPUB compatibility
        let annotatedHTML = """
        <div class="epub-annotated-block">
            <\(tagName) class="epub-translated-main">\(escapeHTML(translated))</\(tagName)>
            <details class="epub-original-details">
                <summary class="epub-show-original">▶ 원문 보기</summary>
                <\(tagName) class="epub-original-text">\(escapeHTML(original))</\(tagName)>
            </details>
        </div>
        """

        try element.before(annotatedHTML)
        try element.remove()
    }

    // MARK: - CSS Injection

    /// Inject CSS styles for translated content
    private func injectStyles(into document: Document, mode: TranslationMode) throws {
        let css: String

        switch mode {
        case .bilingual:
            css = """
            .epub-translated {
                color: #2c5f8a;
                border-left: 3px solid #2c5f8a;
                padding-left: 0.8em;
                margin-top: 0.3em;
                margin-bottom: 1em;
                font-style: italic;
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
