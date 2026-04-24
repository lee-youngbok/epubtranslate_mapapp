import Foundation
import ZIPFoundation

/// Service responsible for repackaging translated content back into a valid EPUB file
struct EPUBPackager: Sendable {

    /// Repackage the translated EPUB content into a valid EPUB file
    /// Follows EPUB specification requirements:
    /// - mimetype must be the first entry, uncompressed
    /// - META-INF/container.xml must be present
    /// - All original structure must be preserved
    func packageEPUB(from sourceDirectory: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default

        // Remove existing file if present
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        // Create the archive
        let archive = try Archive(url: outputURL, accessMode: .create)

        // 1. Add mimetype first (MUST be first entry, uncompressed, no extra field)
        let mimetypePath = sourceDirectory.appendingPathComponent("mimetype")
        if fileManager.fileExists(atPath: mimetypePath.path) {
            try archive.addEntry(
                with: "mimetype",
                fileURL: mimetypePath,
                compressionMethod: .none
            )
        } else {
            // Create mimetype if it doesn't exist
            let mimetypeData = "application/epub+zip".data(using: .utf8)!
            try archive.addEntry(
                with: "mimetype",
                type: .file,
                uncompressedSize: Int64(mimetypeData.count),
                compressionMethod: .none,
                provider: { position, size in
                    let start = Data.Index(position)
                    let end = start + size
                    return mimetypeData.subdata(in: start..<end)
                }
            )
        }

        // 2. Add all other files
        guard let enumerator = fileManager.enumerator(atPath: sourceDirectory.path) else {
            return
        }

        while let relativePath = enumerator.nextObject() as? String {
            // Skip mimetype as it was already added first
            if relativePath == "mimetype" {
                continue
            }
            
            // Skip macOS system files
            if relativePath.hasSuffix(".DS_Store") || relativePath.contains("__MACOSX") {
                continue
            }

            let fileURL = sourceDirectory.appendingPathComponent(relativePath)
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir)

            if !isDir.boolValue {
                try archive.addEntry(
                    with: relativePath,
                    fileURL: fileURL,
                    compressionMethod: .deflate
                )
            }
        }
    }
}

/// Errors during EPUB packaging
enum EPUBPackagerError: LocalizedError {
    case archiveCreationFailed
    case mimetypeCreationFailed

    var errorDescription: String? {
        switch self {
        case .archiveCreationFailed:
            return "EPUB 아카이브를 생성할 수 없습니다."
        case .mimetypeCreationFailed:
            return "mimetype 파일을 생성할 수 없습니다."
        }
    }
}

