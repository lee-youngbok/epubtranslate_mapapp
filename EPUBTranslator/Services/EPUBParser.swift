import Foundation
import ZIPFoundation
import SwiftSoup

/// Service responsible for extracting and parsing EPUB files
actor EPUBParser {

    /// Extract an EPUB file to a temporary directory and parse its contents
    func parseEPUB(at fileURL: URL) async throws -> EPUBBook {
        print("[DEBUG-EPUBParser] ----------------------------------------")
        print("[DEBUG-EPUBParser] 원본 EPUB 파싱 시작. 경로: \(fileURL.path)")
        
        // 1. 보안 권한 획득 (원본 EPUB 파일에 대해)
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        print("[DEBUG-EPUBParser] 원본 EPUB startAccessingSecurityScopedResource 성공 여부: \(hasAccess)")
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
                print("[DEBUG-EPUBParser] 원본 EPUB stopAccessingSecurityScopedResource 반납 완료")
            }
        }
        
        // 원본 파일 존재 여부 확인
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[DEBUG-EPUBParser] 오류: 원본 EPUB 파일이 존재하지 않습니다. (\(fileURL.path))")
            throw EPUBParserError.invalidEPUBStructure
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBTranslator_\(UUID().uuidString)")

        // Create temp directory
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        print("[DEBUG-EPUBParser] 임시 디렉토리 생성 완료: \(tempDir.path)")

        // Unzip EPUB
        print("[DEBUG-EPUBParser] EPUB 압축 해제 시작...")
        try FileManager.default.unzipItem(at: fileURL, to: tempDir)
        print("[DEBUG-EPUBParser] EPUB 압축 해제 완료")

        // Find and parse container.xml to locate OPF file
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        let containerXML = try safeParse(fileURL: containerPath, isXML: true)
        
        let rootfileElement = try containerXML.select("rootfile").first()
        guard let opfRelativePath = try rootfileElement?.attr("full-path") else {
            print("[DEBUG-EPUBParser] 오류: container.xml에서 rootfile(OPF 경로)을 찾을 수 없음")
            throw EPUBParserError.opfNotFound
        }
        print("[DEBUG-EPUBParser] OPF 상대 경로 찾음: \(opfRelativePath)")

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
        print("[DEBUG-EPUBParser] 도서 메타데이터 - 제목: \(title), 저자: \(author)")

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
        print("[DEBUG-EPUBParser] Manifest 아이템 개수: \(manifestItems.count)")

        // Parse spine to get ordered chapter list
        let spineElements = try opfXML.select("spine itemref")
        var chapters: [Chapter] = []

        print("[DEBUG-EPUBParser] Spine 분석 시작 (챕터 추출)")
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

            guard FileManager.default.fileExists(atPath: chapterURL.path) else {
                print("[DEBUG-EPUBParser] 경고: 챕터 파일 누락 - \(chapterURL.path)")
                continue
            }

            // Parse chapter to extract title and paragraph count
            print("[DEBUG-EPUBParser] 챕터 파싱 시도: \(chapterRelativePath)")
            do {
                let chapterHTML = try safeParse(fileURL: chapterURL, isXML: false)
                
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
                print("[DEBUG-EPUBParser] 챕터 추가 성공 - 제목: \(chapterTitle), 문단 수: \(paragraphCount)")
            } catch {
                print("[DEBUG-EPUBParser] 챕터 파싱 실패 건너뜀 - 경로: \(chapterRelativePath), 에러: \(error.localizedDescription)")
            }
        }

        print("[DEBUG-EPUBParser] 총 추출된 챕터 수: \(chapters.count)")

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
        print("[DEBUG-EPUBParser] ---> safeParse 접근 시도: \(fileURL.lastPathComponent)")
        
        // 1. 보안 권한 획득 (압축 해제된 내부 파일이더라도 안전하게 처리)
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        print("[DEBUG-EPUBParser]      startAccessingSecurityScopedResource: \(hasAccess)")
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
                print("[DEBUG-EPUBParser]      stopAccessingSecurityScopedResource 반납")
            }
        }
        
        // 2. 강력한 방어 로직: 파일 존재 여부 확인
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[DEBUG-EPUBParser]      오류: 파일이 존재하지 않음 (\(fileURL.path))")
            throw EPUBParserError.invalidEPUBStructure
        }
        
        // 3. 텍스트 메모리 로드
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // UTF-8로 읽기 실패 시 다른 인코딩 시도 (macOSRoman 등)
            print("[DEBUG-EPUBParser]      UTF-8 읽기 실패. 다른 인코딩으로 재시도합니다.")
            let data = try Data(contentsOf: fileURL)
            content = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .macOSRoman) ?? ""
        }
        
        print("[DEBUG-EPUBParser]      추출된 텍스트 길이: \(content.count) 글자")
        
        // 빈 값 검증
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[DEBUG-EPUBParser]      오류: 파일 내용이 완전히 비어 있습니다.")
            throw EPUBParserError.invalidEPUBStructure
        }
        
        // 4. SwiftSoup 파싱
        print("[DEBUG-EPUBParser]      SwiftSoup 파싱 시작 (isXML: \(isXML))")
        do {
            if isXML {
                return try SwiftSoup.parse(content, fileURL.absoluteString, Parser.xmlParser())
            } else {
                return try SwiftSoup.parse(content, fileURL.absoluteString)
            }
        } catch {
            print("[DEBUG-EPUBParser]      SwiftSoup 내부 예외 발생: \(error)")
            throw EPUBParserError.invalidEPUBStructure
        }
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
            return "EPUB 구조가 올바르지 않거나 파일이 비어 있습니다."
        case .chapterNotFound(let path):
            return "챕터 파일을 찾을 수 없습니다: \(path)"
        }
    }
}
