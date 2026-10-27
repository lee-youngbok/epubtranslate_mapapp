import SwiftUI

@available(macOS 15.0, *)
struct SettingsPanel: View {
    @Bindable var viewModel: TranslatorViewModel
    @State private var newSourceTerm: String = ""
    @State private var newTargetTerm: String = ""

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    // Target Language
                    settingsCard(icon: "globe", title: "도착 언어") {
                        HStack {
                            Picker("", selection: $viewModel.targetLanguageCode) {
                                ForEach(viewModel.availableLanguages, id: \.id) { lang in
                                    Text(lang.displayName).tag(lang.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.large)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.cyan.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Translation Mode & TOC Language Option
                    settingsCard(icon: "text.badge.checkmark", title: "번역 모드") {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(spacing: 8) {
                                ForEach(TranslationMode.allCases) { mode in
                                    modeButton(mode)
                                }
                            }

                            Divider().overlay(Color.white.opacity(0.08))

                            // Table of Contents (목차) Language Selection
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet.indent")
                                        .font(.system(size: 11))
                                        .foregroundColor(.cyan)
                                    Text("목차 (TOC) 언어")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer()
                                    Text(viewModel.tocLanguageMode.description)
                                        .font(.system(size: 10))
                                        .foregroundColor(.cyan.opacity(0.85))
                                }

                                HStack(spacing: 8) {
                                    ForEach(TOCLanguageMode.allCases) { tocMode in
                                        tocModeButton(tocMode)
                                    }
                                }

                                Text("목차는 원문과 번역문이 함께 표시되지 않으며, 선택한 단일 언어로만 생성됩니다.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // Typography & Font Settings (언어별 원문 / 번역문 폰트 설정)
                    settingsCard(icon: "textformat.size", title: "글꼴 (폰트) 설정") {
                        fontSettingsContent
                    }

                    // Apple Books Export & Book Metadata Editing
                    settingsCard(icon: "books.vertical.fill", title: "도서 정보 및 내보내기 옵션") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $viewModel.exportDirectlyToAppleBooks) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("완료 시 Apple 도서 앱으로 바로 보내기")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                    Text("별도 폴더 저장 창을 띄우지 않고 도서 앱 서재에 즉시 추가합니다.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.45))
                                }
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif

                            Divider().overlay(Color.white.opacity(0.08))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("도서명 (Apple 도서 표시 제목)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                TextField("도서명을 입력하세요", text: $viewModel.customBookTitle)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("저자 (Author)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                TextField("저자명을 입력하세요", text: $viewModel.customBookAuthor)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                            }
                        }
                    }

                    // Preprocessing & Term Protection (Glossary)
                    settingsCard(icon: "character.book.closed.fill", title: "전처리 및 고유명사/용어 보호") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $viewModel.hybridService.enableSentenceSplitting) {
                                Text("문장 단위 정밀 분할 번역 (NLTokenizer)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif

                            Toggle(isOn: $viewModel.hybridService.enableEntityProtection) {
                                Text("고유명사/용어집 마스킹 보호 활성화")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif

                            if viewModel.hybridService.enableEntityProtection {
                                Divider().overlay(Color.white.opacity(0.08))

                                // Add Glossary Term Input
                                HStack(spacing: 6) {
                                    TextField("원문 용어 (예: Baker)", text: $newSourceTerm)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))

                                    TextField("고정 번역어 (비우면 원문 유지)", text: $newTargetTerm)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))

                                    Button(action: {
                                        viewModel.addGlossaryEntry(source: newSourceTerm, target: newTargetTerm)
                                        newSourceTerm = ""
                                        newTargetTerm = ""
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.cyan)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(newSourceTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }

                                // Suggested Entities from NLTagger
                                if !viewModel.suggestedEntities.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("감지된 주요 고유명사 (클릭하여 원문 보호 추가):")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.45))

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(viewModel.suggestedEntities, id: \.self) { entity in
                                                    let isAdded = viewModel.hybridService.glossaryEntries.contains {
                                                        $0.sourceTerm.caseInsensitiveCompare(entity) == .orderedSame
                                                    }
                                                    Button(action: {
                                                        viewModel.addGlossaryEntry(source: entity, target: "")
                                                    }) {
                                                        HStack(spacing: 3) {
                                                            Image(systemName: isAdded ? "checkmark" : "plus")
                                                                .font(.system(size: 8, weight: .bold))
                                                            Text(entity)
                                                                .font(.system(size: 10, weight: .medium))
                                                        }
                                                        .foregroundColor(isAdded ? .green : .cyan)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 3)
                                                        .background(
                                                            Capsule().fill((isAdded ? Color.green : Color.cyan).opacity(0.12))
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                    .disabled(isAdded)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Registered Glossary List
                                if !viewModel.hybridService.glossaryEntries.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(viewModel.hybridService.glossaryEntries) { entry in
                                            HStack(spacing: 6) {
                                                Text(entry.sourceTerm)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.9))
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white.opacity(0.4))
                                                Text(entry.targetTerm.isEmpty ? "(원문 유지)" : entry.targetTerm)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.cyan.opacity(0.9))
                                                Spacer()
                                                Button(action: { viewModel.removeGlossaryEntry(id: entry.id) }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.white.opacity(0.35))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Smart Skipping info
                    settingsCard(icon: "brain.head.profile", title: "Smart Skipping") {
                        Text("문단 단위로 언어를 감지하여 도착 언어와 동일한 문단은 자동으로 건너뜁니다.")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Apple Silicon Status
                    settingsCard(icon: "cpu", title: "Apple Silicon Architecture") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.cyan)
                                Text(AppleSiliconHardwareInfo.shared.chipName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Text("arm64 • Neural Engine 번역 가속 활성화됨")
                                .font(.system(size: 11))
                                .foregroundColor(.cyan.opacity(0.8))
                        }
                    }

                    // On-Device Intelligence & Privacy
                    settingsCard(icon: "lock.shield", title: "온디바이스 AI 및 보안") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(viewModel.networkMonitor.isConnected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.networkMonitor.statusDescription)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text("모든 번역과 처리는 외부 서버 전송 없이 100% 기기 내부 Apple Neural Engine에서 수행되어 프라이버시가 안전하게 보호됩니다.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)

                            Toggle(isOn: $viewModel.hybridService.enableLiteraryPolishing) {
                                Text("온디바이스 문맥 윤문 및 문장부호 정제")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .scrollIndicators(.automatic)

            // Start button (하단 고정)
            Button(action: { viewModel.requestTranslation() }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("번역 시작")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                )
                .opacity(viewModel.isReadyToTranslate ? 1 : 0.3)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .cyan.opacity(viewModel.isReadyToTranslate ? 0.4 : 0), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isReadyToTranslate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func settingsCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(.cyan)
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    // MARK: - Font Settings UI

    @ViewBuilder
    private var fontSettingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기본적으로 원본 EPUB 폰트를 유지합니다. 원문(언어별)과 번역문 폰트를 각각 상업 무료 폰트(최초 선택 시 자동 다운로드 및 EPUB 내장) 또는 시스템 폰트로 변경할 수 있습니다.")
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            // 1. 번역문 폰트 설정 (도착 언어 기준)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("번역문 폰트")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(viewModel.targetLanguageDisplayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                    Spacer()
                }

                fontSelectorMenu(
                    languageCode: viewModel.targetLanguageCode,
                    selection: viewModel.currentTargetFontSelection,
                    onSelect: { newSelection in
                        viewModel.currentTargetFontSelection = newSelection
                    }
                )

                if case .downloadable(let font) = viewModel.currentTargetFontSelection {
                    fontDownloadStatusRow(for: font)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))

            // 2. 원문 폰트 설정 (출발 언어별)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("원문 폰트 (언어별)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Picker("", selection: $viewModel.selectedSourceLanguageForFont) {
                        ForEach(viewModel.configurableSourceLanguages, id: \.id) { lang in
                            Text(lang.displayName).tag(lang.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 150)
                }

                fontSelectorMenu(
                    languageCode: viewModel.selectedSourceLanguageForFont,
                    selection: viewModel.currentSourceFontSelection,
                    onSelect: { newSelection in
                        viewModel.currentSourceFontSelection = newSelection
                    }
                )

                if case .downloadable(let font) = viewModel.currentSourceFontSelection {
                    fontDownloadStatusRow(for: font)
                }

                // Active per-language source font rules summary
                if !viewModel.sourceFontByLanguage.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("설정된 언어별 원문 폰트:")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))

                        ForEach(viewModel.sourceFontByLanguage.keys.sorted(), id: \.self) { langCode in
                            if let sel = viewModel.sourceFontByLanguage[langCode], !sel.isOriginal {
                                HStack(spacing: 6) {
                                    Text(viewModel.displayName(forLanguageCode: langCode))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(.white.opacity(0.35))
                                    Text(sel.displayName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.cyan.opacity(0.9))
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        viewModel.setSourceFont(.original, for: langCode)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04)))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))

            // 3. 실시간 글꼴 미리보기 (원문 / 번역문 폰트 변경 시 표시)
            if !viewModel.currentTargetFontSelection.isOriginal || !viewModel.currentSourceFontSelection.isOriginal {
                VStack(alignment: .leading, spacing: 6) {
                    Text("타이포그래피 미리보기")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))

                    if !viewModel.currentSourceFontSelection.isOriginal {
                        Text(samplePreviewText(for: viewModel.selectedSourceLanguageForFont))
                            .font(swiftUIFont(for: viewModel.currentSourceFontSelection, size: 12))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(2)
                    }

                    if !viewModel.currentTargetFontSelection.isOriginal {
                        Text(samplePreviewText(for: viewModel.targetLanguageCode))
                            .font(swiftUIFont(for: viewModel.currentTargetFontSelection, size: 12.5))
                            .foregroundColor(.cyan.opacity(0.95))
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func fontSelectorMenu(
        languageCode: String,
        selection: FontSelection,
        onSelect: @escaping (FontSelection) -> Void
    ) -> some View {
        let recommendedFonts = DownloadableFont.recommendedFonts(for: languageCode)

        Menu {
            Button(action: { onSelect(.original) }) {
                HStack {
                    Text("원본 폰트 유지 (기본)")
                    if selection.isOriginal {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            Section("상업 무료 추천 폰트 (EPUB 내장 • 최초 선택 시 다운로드)") {
                ForEach(recommendedFonts) { font in
                    let isDownloaded = viewModel.fontManager.state(for: font).isDownloaded
                    Button(action: { onSelect(.downloadable(font)) }) {
                        HStack {
                            Text(isDownloaded ? "\(font.displayName) [다운로드됨 ✓]" : "\(font.displayName) [선택 시 다운로드]")
                            if selection == .downloadable(font) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Menu("시스템 설치 폰트 선택 (\(viewModel.fontManager.systemFontFamilies.count)개)") {
                ForEach(viewModel.fontManager.systemFontFamilies, id: \.self) { family in
                    Button(action: { onSelect(.system(familyName: family)) }) {
                        HStack {
                            Text(family)
                            if selection == .system(familyName: family) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.isOriginal ? "doc.text" : "textformat")
                    .font(.system(size: 11))
                    .foregroundColor(.cyan)
                Text(selection.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func fontDownloadStatusRow(for font: DownloadableFont) -> some View {
        let state = viewModel.fontManager.state(for: font)

        VStack(alignment: .leading, spacing: 4) {
            Text(font.licenseDescription)
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.4))

            switch state {
            case .notDownloaded:
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.cyan)
                    Text("아직 다운로드되지 않음")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Button(action: {
                        Task {
                            try? await viewModel.fontManager.ensureFontDownloaded(font)
                        }
                    }) {
                        Text("지금 다운로드")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.cyan.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }

            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("폰트 다운로드 중... (\(Int(progress * 100))%)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.cyan)
                    Spacer()
                }

            case .downloaded(_, let bytes):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("다운로드됨 (\(FontManager.formatBytes(bytes))) • EPUB 임베딩 준비 완료")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.9))
                    Spacer()
                }

            case .failed(let reason):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(.orange.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Button(action: {
                        Task {
                            try? await viewModel.fontManager.ensureFontDownloaded(font)
                        }
                    }) {
                        Text("재시도")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.cyan.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 2)
    }

    private func swiftUIFont(for selection: FontSelection, size: CGFloat) -> Font {
        switch selection {
        case .original:
            return .system(size: size)
        case .downloadable(let font):
            if let registeredName = viewModel.fontManager.registeredFontNames[font] {
                return .custom(registeredName, size: size)
            }
            return .custom(font.cssFamilyName, size: size)
        case .system(let familyName):
            return .custom(familyName, size: size)
        }
    }

    private func samplePreviewText(for languageCode: String) -> String {
        let normalized = languageCode.lowercased()
        if normalized.hasPrefix("ko") {
            return "다람쥐 헌 쳇바퀴에 타고파. 별 헤는 밤과 전자책 타이포그래피."
        } else if normalized.hasPrefix("ja") {
            return "いろはにほへと ちりぬるを。美しい電子書籍のタイポグラフィ。"
        } else if normalized == "zh-hant" || normalized == "zh-tw" || normalized == "zh-hk" {
            return "天地玄黃，宇宙洪荒。清晰的電子書字體預覽。"
        } else if normalized.hasPrefix("zh") {
            return "天地玄黄，宇宙洪荒。清晰的电子书字体预览。"
        } else if normalized.hasPrefix("ar") {
            return "نص تجريبي لمعاينة الخط العربي في الكتاب الإلكتروني."
        } else if normalized.hasPrefix("th") {
            return "ตัวอย่างข้อความสำหรับแสดงตัวอย่างฟอนต์ภาษาไทย"
        } else {
            return "The quick brown fox jumps over the lazy dog. 1234567890"
        }
    }

    private func modeButton(_ mode: TranslationMode) -> some View {
        Button(action: { viewModel.translationMode = mode }) {
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14))
                    .foregroundColor(viewModel.translationMode == mode ? .cyan : .white.opacity(0.4))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(viewModel.translationMode == mode ? .white : .white.opacity(0.6))
                    Text(mode.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Spacer()
                if viewModel.translationMode == mode {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.cyan).font(.system(size: 14))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(
                    viewModel.translationMode == mode ? Color.cyan.opacity(0.1) : Color.clear
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    viewModel.translationMode == mode ? Color.cyan.opacity(0.3) : Color.clear, lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func tocModeButton(_ tocMode: TOCLanguageMode) -> some View {
        let isSelected = viewModel.tocLanguageMode == tocMode
        let isDefault = TOCLanguageMode.defaultMode(for: viewModel.translationMode) == tocMode

        return Button(action: { viewModel.tocLanguageMode = tocMode }) {
            HStack(spacing: 6) {
                Image(systemName: tocMode.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .cyan : .white.opacity(0.45))
                Text(tocMode.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                if isDefault {
                    Text("기본")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isSelected ? .cyan : .white.opacity(0.45))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill((isSelected ? Color.cyan : Color.white).opacity(0.15))
                        )
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(
                    isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.03)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    isSelected ? Color.cyan.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}
