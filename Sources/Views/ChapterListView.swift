import SwiftUI

@available(macOS 15.0, *)
struct ChapterListView: View {
    @Bindable var viewModel: TranslatorViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            ScrollView {
                LazyVStack(spacing: 2) {
                    if let book = viewModel.book {
                        ForEach(book.chapters) { chapter in
                            chapterRow(chapter)
                        }
                    }
                }
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.02)))
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle").font(.system(size: 16)).foregroundColor(.cyan)
                Text("챕터 목록").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                Spacer()
                if let book = viewModel.book {
                    Text("\(viewModel.selectedChaptersCount) / \(book.chapters.count) 선택")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                }
            }
            if let book = viewModel.book {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill").font(.system(size: 11)).foregroundColor(.cyan.opacity(0.7))
                    Text(book.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Image(systemName: "person.fill").font(.system(size: 11)).foregroundColor(.cyan.opacity(0.7))
                    Text(book.author).font(.system(size: 12)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                }
                if !book.detectedLanguages.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "globe").font(.system(size: 11)).foregroundColor(.cyan.opacity(0.7))
                        Text("감지된 언어:").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        ForEach(book.detectedLanguages.prefix(3)) { lang in
                            Text("\(lang.displayName) (\(String(format: "%.0f", lang.percentage))%)")
                                .font(.system(size: 11, weight: .medium)).foregroundColor(.cyan.opacity(0.9))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Color.cyan.opacity(0.12)))
                        }
                    }
                }
            }
            HStack {
                Toggle(isOn: Binding(get: { viewModel.allChaptersSelected }, set: { _ in viewModel.toggleAllChapters() })) {
                    Text("전체 선택").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7))
                }
                .toggleStyle(.checkbox)
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    @ViewBuilder
    private func chapterRow(_ chapter: Chapter) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { chapter.isSelected }, set: { _ in viewModel.toggleChapter(id: chapter.id) })) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(chapter.isSelected ? .white.opacity(0.9) : .white.opacity(0.4))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if chapter.paragraphCount > 0 {
                        Label("\(chapter.paragraphCount) 문단", systemImage: "text.alignleft")
                            .font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
                    }
                    if let lang = chapter.detectedLanguage {
                        let displayName = Locale.current.localizedString(forLanguageCode: lang) ?? lang
                        Text(displayName).font(.system(size: 10, weight: .medium)).foregroundColor(.cyan.opacity(0.7))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.cyan.opacity(0.08)))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(chapter.isSelected ? Color.cyan.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleChapter(id: chapter.id) }
    }
}
