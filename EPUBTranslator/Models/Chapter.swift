import Foundation

/// Represents a single chapter or article in an EPUB
struct Chapter: Identifiable, Sendable {
    let id = UUID()
    /// Display title of the chapter
    var title: String
    /// Relative path to the XHTML/HTML file within the EPUB
    var relativePath: String
    /// Whether the user has selected this chapter for translation
    var isSelected: Bool = true
    /// Number of paragraphs in this chapter
    var paragraphCount: Int = 0
    /// Primary language detected in this chapter
    var detectedLanguage: String?
    /// Sample texts extracted during initial parse for fast language detection
    var sampleTexts: [String] = []
    /// Whether this spine item is an in-book Table of Contents (목차) page
    var isTableOfContents: Bool = false
}
