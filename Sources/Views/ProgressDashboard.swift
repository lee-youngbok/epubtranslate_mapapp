import SwiftUI

@available(macOS 15.0, *)
struct ProgressDashboard: View {
    @Bindable var viewModel: TranslatorViewModel

    private var isPackaging: Bool {
        if case .packaging = viewModel.appPhase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            VStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.pulse, isActive: true)
                Text(isPackaging ? "패키징 중..." : "번역 진행 중")
                    .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
            }

            // Dashboard cards
            VStack(spacing: 16) {
                // Current chapter
                dashboardCard(icon: "doc.text", title: "현재 챕터", value: viewModel.currentChapterTitle.isEmpty ? "준비 중..." : viewModel.currentChapterTitle)

                // Chapter progress
                HStack(spacing: 16) {
                    dashboardMetric(title: "전체 진행", value: "\(viewModel.completedChapters) / \(viewModel.totalChaptersToTranslate)", icon: "books.vertical")
                    dashboardMetric(title: "현재 챕터", value: "\(Int(viewModel.currentChapterProgress * 100))%", icon: "percent")
                }

                // Overall progress bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("전체 진행률").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(viewModel.progressFraction * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.cyan)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)).frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, geo.size.width * viewModel.progressFraction), height: 12)
                                .animation(.easeInOut(duration: 0.3), value: viewModel.progressFraction)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))

                // Chapter progress bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("현재 챕터 진행률").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(viewModel.currentChapterProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.green)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)).frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [.green, .cyan], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, geo.size.width * viewModel.currentChapterProgress), height: 12)
                                .animation(.easeInOut(duration: 0.3), value: viewModel.currentChapterProgress)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
            .frame(maxWidth: 500)

            // Status
            Text(viewModel.statusMessage)
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.4))

            // Cancel button
            Button(action: { viewModel.cancelTranslation() }) {
                Label("번역 취소", systemImage: "xmark.circle")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.bordered).tint(.red)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dashboardCard(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(.cyan).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.4))
                Text(value).font(.system(size: 14, weight: .semibold)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private func dashboardMetric(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(.cyan)
            Text(value).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(.white)
            Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }
}
