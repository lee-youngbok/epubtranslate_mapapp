import Foundation

/// Represents a parsed EPUB book
struct EPUBBook: Sendable {
    /// Title of the book from OPF metadata
    var title: String
    /// Author(s) of the book
    var author: String
    /// Chapters/articles extracted from the EPUB spine
    var chapters: [Chapter]
    /// Path to the extracted EPUB contents in temp directory
    var extractedPath: URL
    /// Original EPUB file name
    var originalFileName: String
    /// Languages detected across the entire document
    var detectedLanguages: [DetectedLanguageInfo]
    /// Path to the OPF file relative to extractedPath
    var opfRelativePath: String
    /// All files in the EPUB container (for repackaging)
    var allFiles: [String]
}

/// Information about a detected language in the document
struct DetectedLanguageInfo: Identifiable, Sendable, Hashable {
    let id = UUID()
    /// BCP 47 language code (e.g., "en", "ko", "ja")
    let languageCode: String
    /// Human-readable display name
    let displayName: String
    /// Approximate percentage of content in this language
    let percentage: Double
}
