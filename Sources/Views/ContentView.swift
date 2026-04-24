import SwiftUI
import UniformTypeIdentifiers

/// Main content view that orchestrates the app layout
@available(macOS 15.0, *)
struct ContentView: View {
    @State private var viewModel = TranslatorViewModel()

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1.0)),
                    Color(nsColor: NSColor(red: 0.10, green: 0.11, blue: 0.18, alpha: 1.0)),
                    Color(nsColor: NSColor(red: 0.08, green: 0.09, blue: 0.15, alpha: 1.0))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Main Content Area
                mainContentArea
            }
        }
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await viewModel.importEPUB(url: url) }
                }
            case .failure(let error):
                viewModel.appPhase = .error("파일을 열 수 없습니다: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $viewModel.showFileExporter,
            document: EPUBDocument(data: viewModel.exportedEPUBData ?? Data()),
            contentType: UTType(filenameExtension: "epub") ?? .data,
            defaultFilename: viewModel.book.map { "\($0.originalFileName)_translated.epub" } ?? "translated.epub"
        ) { result in
            switch result {
            case .success(let url):
                viewModel.statusMessage = "저장 완료: \(url.lastPathComponent)"
            case .failure(let error):
                viewModel.appPhase = .error("저장 실패: \(error.localizedDescription)")
            }
        }
        .translationTask(viewModel.translationConfig) { session in
            await viewModel.executeTranslation(session: session)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "book.pages")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("EPUB Intelligence Translator")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Apple Intelligence 온디바이스 번역")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Status indicator
            if case .error(let msg) = viewModel.appPhase {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .frame(maxWidth: 300)
            }

            // Reset button
            if viewModel.book != nil {
                Button(action: { viewModel.reset() }) {
                    Label("새로 시작", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentArea: some View {
        switch viewModel.appPhase {
        case .idle:
            FileDropView(viewModel: viewModel)
                .transition(.opacity)

        case .importing, .analyzing:
            loadingView
                .transition(.opacity)

        case .ready:
            readyView
                .transition(.opacity)

        case .translating, .packaging:
            ProgressDashboard(viewModel: viewModel)
                .transition(.opacity)

        case .completed:
            completedView
                .transition(.opacity)

        case .error:
            errorView
                .transition(.opacity)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.cyan)

            Text(viewModel.statusMessage)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            if case .analyzing = viewModel.appPhase {
                Text("EPUB 구조를 분석하고 언어를 감지하고 있습니다...")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ready View (Chapters + Settings)

    private var readyView: some View {
        HSplitView {
            // Left: Chapter list
            ChapterListView(viewModel: viewModel)
                .frame(minWidth: 350)

            // Right: Settings panel
            SettingsPanel(viewModel: viewModel)
                .frame(minWidth: 300, maxWidth: 400)
        }
        .padding(16)
    }

    // MARK: - Completed View

    private var completedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("번역 완료!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(viewModel.statusMessage)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 16) {
                Button(action: { viewModel.showFileExporter = true }) {
                    Label("다른 위치에 저장", systemImage: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button(action: { viewModel.reset() }) {
                    Label("새 파일 번역", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            if case .error(let msg) = viewModel.appPhase {
                Text(msg)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: { viewModel.reset() }) {
                Label("다시 시도", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EPUB Document for FileExporter

struct EPUBDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "epub") ?? .data]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}
