import SwiftUI
import UniformTypeIdentifiers

/// File drop zone view with drag & drop and file picker support
@available(macOS 15.0, *)
struct FileDropView: View {
    @Bindable var viewModel: TranslatorViewModel
    @State private var isDragOver = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Drop zone
            ZStack {
                // Outer glow when dragging
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        isDragOver
                            ? Color.cyan.opacity(0.08)
                            : Color.white.opacity(0.02)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(
                                isDragOver
                                    ? LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: isDragOver ? 2 : 1, dash: [8, 6])
                            )
                    )
                    .shadow(color: isDragOver ? .cyan.opacity(0.3) : .clear, radius: 20)

                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.2), .blue.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: isDragOver ? "arrow.down.doc.fill" : "doc.badge.plus")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.bounce, value: isDragOver)
                    }

                    VStack(spacing: 8) {
                        Text(isDragOver ? "여기에 놓으세요" : "EPUB 파일을 드래그하세요")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))

                        Text("또는 아래 버튼을 클릭하여 파일을 선택하세요")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    // Browse button
                    Button(action: { viewModel.showFileImporter = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                            Text("파일 선택")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: NSColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1.0)),
                                    Color(nsColor: NSColor(red: 0.10, green: 0.35, blue: 0.75, alpha: 1.0))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .scaleEffect(isHovering ? 1.03 : 1.0)
                    .animation(.spring(response: 0.3), value: isHovering)
                }
            }
            .frame(maxWidth: 520, maxHeight: 320)
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
            }
            .animation(.easeInOut(duration: 0.2), value: isDragOver)

            // Supported format info
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text("지원 형식: EPUB (.epub)")
                    .font(.system(size: 11))
            }
            .foregroundColor(.white.opacity(0.3))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Handle dropped files
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
            guard let urlData = data as? Data,
                  let urlString = String(data: urlData, encoding: .utf8),
                  let url = URL(string: urlString),
                  url.pathExtension.lowercased() == "epub" else {
                Task { @MainActor in
                    viewModel.appPhase = .error("EPUB 파일만 지원됩니다.")
                }
                return
            }

            Task { @MainActor in
                await viewModel.importEPUB(url: url)
            }
        }
        return true
    }
}
