import Foundation
import SwiftUI
import CoreText
import os
#if os(macOS)
import AppKit
#endif

// MARK: - Downloadable Commercial-Free Fonts

/// Commercial-free fonts that can be downloaded on demand and embedded into EPUB files
enum DownloadableFont: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    // Korean (한국어 대상)
    case pretendard = "pretendard"
    case kopubBatang = "kopub_batang"

    // Other Languages (다국어 대상 Noto Sans 계열)
    case notoSans = "noto_sans"
    case notoSansJP = "noto_sans_jp"
    case notoSansSC = "noto_sans_sc"
    case notoSansTC = "noto_sans_tc"
    case notoSansArabic = "noto_sans_arabic"
    case notoSansThai = "noto_sans_thai"

    var id: String { rawValue }

    /// Display name shown in the UI picker
    var displayName: String {
        switch self {
        case .pretendard:
            return "Pretendard (프리텐다드 고딕)"
        case .kopubBatang:
            return "KoPubWorld 바탕 (명조)"
        case .notoSans:
            return "Noto Sans (다국어 표준 고딕)"
        case .notoSansJP:
            return "Noto Sans JP (일본어 고딕)"
        case .notoSansSC:
            return "Noto Sans SC (중국어 간체 고딕)"
        case .notoSansTC:
            return "Noto Sans TC (중국어 번체 고딕)"
        case .notoSansArabic:
            return "Noto Sans Arabic (아랍어 고딕)"
        case .notoSansThai:
            return "Noto Sans Thai (태국어 고딕)"
        }
    }

    /// Short license & style description
    var licenseDescription: String {
        switch self {
        case .pretendard:
            return "SIL OFL • 상업 무료 • 깔끔한 현대 본문 고딕"
        case .kopubBatang:
            return "KOPUB 라이선스 • 상업/전자책 임베딩 무료 • 정통 본문 명조"
        case .notoSans:
            return "SIL OFL • 상업 무료 • 영문/유럽어/키릴/베트남어 본문 고딕"
        case .notoSansJP:
            return "SIL OFL • 상업 무료 • 일본어 표준 본문 고딕"
        case .notoSansSC:
            return "SIL OFL • 상업 무료 • 중국어(간체) 표준 본문 고딕"
        case .notoSansTC:
            return "SIL OFL • 상업 무료 • 중국어(번체) 표준 본문 고딕"
        case .notoSansArabic:
            return "SIL OFL • 상업 무료 • 아랍어 표준 본문 고딕"
        case .notoSansThai:
            return "SIL OFL • 상업 무료 • 태국어 표준 본문 고딕"
        }
    }

    /// CSS `font-family` name used in `@font-face` and style rules
    var cssFamilyName: String {
        switch self {
        case .pretendard:
            return "Pretendard"
        case .kopubBatang:
            return "KoPubWorldBatang"
        case .notoSans:
            return "Noto Sans"
        case .notoSansJP:
            return "Noto Sans JP"
        case .notoSansSC:
            return "Noto Sans SC"
        case .notoSansTC:
            return "Noto Sans TC"
        case .notoSansArabic:
            return "Noto Sans Arabic"
        case .notoSansThai:
            return "Noto Sans Thai"
        }
    }

    /// CSS fallback generic font family (`sans-serif` or `serif`)
    var cssFallbackGeneric: String {
        switch self {
        case .kopubBatang:
            return "serif"
        default:
            return "sans-serif"
        }
    }

    /// Base file stem used for local storage
    var baseFileStem: String {
        switch self {
        case .pretendard:
            return "Pretendard-Regular"
        case .kopubBatang:
            return "KoPubWorldBatang-Medium"
        case .notoSans:
            return "NotoSans-Regular"
        case .notoSansJP:
            return "NotoSansJP-Regular"
        case .notoSansSC:
            return "NotoSansSC-Regular"
        case .notoSansTC:
            return "NotoSansTC-Regular"
        case .notoSansArabic:
            return "NotoSansArabic-Regular"
        case .notoSansThai:
            return "NotoSansThai-Regular"
        }
    }

    /// Google Fonts CSS API family query (used as dynamic fallback resolver for Noto fonts)
    var googleFontsQueryName: String? {
        switch self {
        case .pretendard, .kopubBatang:
            return nil
        case .notoSans:
            return "Noto+Sans"
        case .notoSansJP:
            return "Noto+Sans+JP"
        case .notoSansSC:
            return "Noto+Sans+SC"
        case .notoSansTC:
            return "Noto+Sans+TC"
        case .notoSansArabic:
            return "Noto+Sans+Arabic"
        case .notoSansThai:
            return "Noto+Sans+Thai"
        }
    }

    /// Candidate direct download URLs (tried in order)
    var candidateDownloadURLs: [String] {
        switch self {
        case .pretendard:
            return [
                "https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/packages/pretendard/dist/public/static/Pretendard-Regular.otf",
                "https://raw.githubusercontent.com/orioncactus/pretendard/v1.3.9/packages/pretendard/dist/public/static/Pretendard-Regular.otf",
                "https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/packages/pretendard/dist/web/static/woff2/Pretendard-Regular.woff2"
            ]
        case .kopubBatang:
            return [
                "https://cdn.jsdelivr.net/gh/webfontworld/kopub/KoPubWorldBatangMedium.ttf",
                "https://cdn.jsdelivr.net/gh/webfontworld/kopub/KoPubWorldBatangMedium.otf",
                "https://cdn.jsdelivr.net/gh/webfontworld/kopub/KoPubWorldBatangMedium.woff2",
                "https://cdn.jsdelivr.net/gh/projectnoonnu/noonfonts_two@1.0/KoPubWorldBatangMedium.woff"
            ]
        case .notoSans:
            return [
                "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSans/NotoSans-Regular.ttf",
                "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSans/NotoSans-Regular.ttf"
            ]
        case .notoSansJP:
            return [
                "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf",
                "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
            ]
        case .notoSansSC:
            return [
                "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
                "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
            ]
        case .notoSansTC:
            return [
                "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf",
                "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf"
            ]
        case .notoSansArabic:
            return [
                "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansArabic/NotoSansArabic-Regular.ttf",
                "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansArabic/NotoSansArabic-Regular.ttf"
            ]
        case .notoSansThai:
            return [
                "https://cdn.jsdelivr.net/gh/googlefonts/noto-fonts@main/hinted/ttf/NotoSansThai/NotoSansThai-Regular.ttf",
                "https://raw.githubusercontent.com/googlefonts/noto-fonts/main/hinted/ttf/NotoSansThai/NotoSansThai-Regular.ttf"
            ]
        }
    }

    /// Recommended downloadable commercial-free fonts for a given BCP 47 language code
    static func recommendedFonts(for languageCode: String) -> [DownloadableFont] {
        let normalized = languageCode.lowercased()
        if normalized.hasPrefix("ko") {
            return [.pretendard, .kopubBatang]
        } else if normalized.hasPrefix("ja") {
            return [.notoSansJP]
        } else if normalized == "zh-hant" || normalized == "zh-tw" || normalized == "zh-hk" {
            return [.notoSansTC]
        } else if normalized.hasPrefix("zh") {
            return [.notoSansSC]
        } else if normalized.hasPrefix("ar") {
            return [.notoSansArabic]
        } else if normalized.hasPrefix("th") {
            return [.notoSansThai]
        } else {
            return [.notoSans]
        }
    }
}

// MARK: - Font Selection Model

/// Represents a user's font choice for a specific language/scope
enum FontSelection: Hashable, Sendable, Codable {
    /// Preserve the original EPUB stylesheet font (Default)
    case original
    /// Use a downloadable commercial-free font (embedded into EPUB via @font-face)
    case downloadable(DownloadableFont)
    /// Use a macOS system-installed font family (injected via CSS font-family)
    case system(familyName: String)

    var isOriginal: Bool {
        if case .original = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .original:
            return "원본 폰트 유지 (기본)"
        case .downloadable(let font):
            return font.displayName
        case .system(let familyName):
            return "\(familyName) (시스템)"
        }
    }

    var cssFontFamilyRule: String? {
        switch self {
        case .original:
            return nil
        case .downloadable(let font):
            return "'\(font.cssFamilyName)', \(font.cssFallbackGeneric)"
        case .system(let familyName):
            let escaped = familyName.replacingOccurrences(of: "'", with: "\\'")
            return "'\(escaped)', sans-serif"
        }
    }
}

// MARK: - Download State

enum FontDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded(fileURL: URL, fileSizeBytes: Int64)
    case failed(String)

    var isDownloaded: Bool {
        if case .downloaded = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - Font Manager Service

/// Manages on-demand downloading, local caching, CoreText preview registration, and system font listing
@available(macOS 15.0, *)
@Observable
@MainActor
final class FontManager {

    static let shared = FontManager()

    private let logger = Logger(subsystem: "com.example.EPUBTranslator", category: "FontManager")

    /// Download states for each commercial-free font
    var downloadStates: [DownloadableFont: FontDownloadState] = [:]

    /// Registered PostScript / family names for live SwiftUI preview of downloaded fonts
    var registeredFontNames: [DownloadableFont: String] = [:]

    /// Cached list of macOS system font families
    private(set) var systemFontFamilies: [String] = []

    /// Directory where downloaded fonts are persisted
    let fontsDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fontsDirectory = appSupport
            .appendingPathComponent("EPUBTranslator", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)

        try? FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)

        loadSystemFonts()
        refreshCachedDownloadStates()
    }

    // MARK: - System Fonts

    func loadSystemFonts() {
        #if os(macOS)
        let families = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        self.systemFontFamilies = families
        #else
        self.systemFontFamilies = []
        #endif
    }

    // MARK: - Local Cache Inspection

    func refreshCachedDownloadStates() {
        for font in DownloadableFont.allCases {
            if let existingURL = findCachedFontFile(for: font) {
                let size = (try? FileManager.default.attributesOfItem(atPath: existingURL.path)[.size] as? Int64) ?? 0
                downloadStates[font] = .downloaded(fileURL: existingURL, fileSizeBytes: size)
                registerFontForPreview(font: font, url: existingURL)
            } else {
                if downloadStates[font]?.isDownloading != true {
                    downloadStates[font] = .notDownloaded
                }
            }
        }
    }

    /// Find cached font file on disk for the given font
    func findCachedFontFile(for font: DownloadableFont) -> URL? {
        let supportedExtensions = ["otf", "ttf", "woff2", "woff"]
        for ext in supportedExtensions {
            let candidate = fontsDirectory.appendingPathComponent("\(font.baseFileStem).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               let size = attrs[.size] as? Int64,
               size > 10_000 {
                return candidate
            }
        }
        return nil
    }

    func state(for font: DownloadableFont) -> FontDownloadState {
        downloadStates[font] ?? .notDownloaded
    }

    // MARK: - On-Demand Font Download

    /// Ensures the specified font is downloaded and returns its local file URL
    @discardableResult
    func ensureFontDownloaded(_ font: DownloadableFont) async throws -> URL {
        if let existingURL = findCachedFontFile(for: font) {
            let size = (try? FileManager.default.attributesOfItem(atPath: existingURL.path)[.size] as? Int64) ?? 0
            downloadStates[font] = .downloaded(fileURL: existingURL, fileSizeBytes: size)
            registerFontForPreview(font: font, url: existingURL)
            return existingURL
        }

        downloadStates[font] = .downloading(progress: 0.1)
        logger.info("Starting on-demand download for font: \(font.displayName)")

        var urlsToTry: [URL] = font.candidateDownloadURLs.compactMap { URL(string: $0) }

        // If Google Fonts query is available, also resolve live gstatic URL as fallback
        if let queryName = font.googleFontsQueryName,
           let resolvedURL = await resolveGoogleFontDownloadURL(queryFamily: queryName) {
            urlsToTry.insert(resolvedURL, at: 0)
        }

        var lastErrorMessage = "다운로드 서버에 연결할 수 없습니다."

        for (index, candidateURL) in urlsToTry.enumerated() {
            do {
                let progressBase = 0.15 + (Double(index) / Double(max(urlsToTry.count, 1))) * 0.3
                downloadStates[font] = .downloading(progress: progressBase)

                var request = URLRequest(url: candidateURL)
                request.timeoutInterval = 30
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    lastErrorMessage = "HTTP 응답 오류"
                    continue
                }

                guard let detectedExt = Self.detectFontExtension(from: data, fallbackURL: candidateURL) else {
                    lastErrorMessage = "유효한 폰트 파일 형식이 아닙니다."
                    continue
                }

                downloadStates[font] = .downloading(progress: 0.9)

                try FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
                let destinationURL = fontsDirectory.appendingPathComponent("\(font.baseFileStem).\(detectedExt)")

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try data.write(to: destinationURL, options: .atomic)

                let fileSize = Int64(data.count)
                downloadStates[font] = .downloaded(fileURL: destinationURL, fileSizeBytes: fileSize)
                registerFontForPreview(font: font, url: destinationURL)

                logger.info("Successfully downloaded font '\(font.displayName)' to \(destinationURL.lastPathComponent) (\(fileSize) bytes)")
                return destinationURL

            } catch {
                lastErrorMessage = error.localizedDescription
                logger.warning("Candidate URL failed for \(font.rawValue) (\(candidateURL.absoluteString)): \(error.localizedDescription)")
            }
        }

        downloadStates[font] = .failed(lastErrorMessage)
        throw FontDownloadError.downloadFailed(fontName: font.displayName, reason: lastErrorMessage)
    }

    /// Delete a downloaded font from local cache
    func removeDownloadedFont(_ font: DownloadableFont) {
        let supportedExtensions = ["otf", "ttf", "woff2", "woff"]
        for ext in supportedExtensions {
            let fileURL = fontsDirectory.appendingPathComponent("\(font.baseFileStem).\(ext)")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        downloadStates[font] = .notDownloaded
    }

    // MARK: - Google Fonts Dynamic URL Resolver

    private func resolveGoogleFontDownloadURL(queryFamily: String) async -> URL? {
        guard let cssURL = URL(string: "https://fonts.googleapis.com/css?family=\(queryFamily):400") else {
            return nil
        }
        var request = URLRequest(url: cssURL)
        request.timeoutInterval = 10
        // Using a classic user-agent instructs Google Fonts to return a direct TrueType (.ttf) / OpenType (.otf) URL
        request.setValue("Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_8; en-us) AppleWebKit/534.50 (KHTML, like Gecko) Version/5.1 Safari/534.50", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let cssText = String(data: data, encoding: .utf8) else {
            return nil
        }

        let pattern = #"url\((https://fonts\.gstatic\.com/[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cssText, range: NSRange(cssText.startIndex..., in: cssText)),
              let range = Range(match.range(at: 1), in: cssText) else {
            return nil
        }

        let urlString = String(cssText[range])
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return URL(string: urlString)
    }

    // MARK: - Font Binary Signature Validation & Helpers

    /// Verifies font magic bytes and returns the appropriate file extension ("otf", "ttf", "woff2", "woff")
    nonisolated static func detectFontExtension(from data: Data, fallbackURL: URL) -> String? {
        guard data.count > 10_000 else { return nil }
        let header = [UInt8](data.prefix(4))

        // OpenType ("OTTO")
        if header == [0x4F, 0x54, 0x54, 0x4F] {
            return "otf"
        }
        // TrueType (0x00010000 or "true")
        if header == [0x00, 0x01, 0x00, 0x00] || header == [0x74, 0x72, 0x75, 0x65] {
            return "ttf"
        }
        // WOFF2 ("wOF2")
        if header == [0x77, 0x4F, 0x46, 0x32] {
            return "woff2"
        }
        // WOFF ("wOFF")
        if header == [0x77, 0x4F, 0x46, 0x46] {
            return "woff"
        }

        return nil
    }

    /// Returns the CSS `@font-face` format string for a given font file extension
    nonisolated static func cssFormat(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "otf": return "opentype"
        case "ttf": return "truetype"
        case "woff2": return "woff2"
        case "woff": return "woff"
        default: return "opentype"
        }
    }

    /// Returns the EPUB OPF `<manifest>` `media-type` for a given font file extension
    nonisolated static func epubMediaType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "otf": return "font/otf"
        case "ttf": return "font/ttf"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        default: return "application/font-sfnt"
        }
    }

    // MARK: - CoreText Preview Registration

    private func registerFontForPreview(font: DownloadableFont, url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "otf" || ext == "ttf" else { return }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            if let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String {
                registeredFontNames[font] = familyName
            } else if let psName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
                registeredFontNames[font] = psName
            }
        }
    }

    /// Format byte count into human-readable string (e.g., "1.4 MB")
    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

enum FontDownloadError: LocalizedError {
    case downloadFailed(fontName: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let fontName, let reason):
            return "'\(fontName)' 폰트 다운로드 실패: \(reason)"
        }
    }
}
