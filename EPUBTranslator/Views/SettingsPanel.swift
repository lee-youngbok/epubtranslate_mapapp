import SwiftUI

@available(macOS 15.0, *)
struct SettingsPanel: View {
    @Bindable var viewModel: TranslatorViewModel

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

                    // Translation Mode
                    settingsCard(icon: "text.badge.checkmark", title: "번역 모드") {
                        VStack(spacing: 8) {
                            ForEach(TranslationMode.allCases) { mode in
                                modeButton(mode)
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
}
