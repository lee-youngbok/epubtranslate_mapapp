# 크로스 플랫폼 로드맵 (Cross-Platform)

EPUB Intelligence Translator는 macOS뿐만 아니라 향후 **iOS 및 iPadOS 유니버설 앱**으로 쉽게 확장될 수 있도록 아키텍처가 모듈화되어 있습니다.

---

## 코드 재사용 비율

- **공유 코어 로직 (90% 이상 재사용)**:
  - `Models/`: 도메인 모델 (`EPUBBook`, `Chapter`, `FontSelection` 등)은 순수 Swift Foundation 기반으로 작성되어 완전 플랫폼 독립적입니다.
  - `Services/`: `EPUBParser`, `HTMLProcessor`, `EPUBPackager`, `LanguageDetector`, `TranslationService`, `HybridIntelligenceService`는 Apple 플랫폼 공통 API 및 크로스 플랫폼 Swift 패키지만 사용합니다.
- **UI 및 플랫폼 분기 (10% 미만)**:
  - 시스템 서체 공급자: macOS의 `NSFontManager` ↔ iOS의 `UIFont.familyNames`
  - 스플릿 뷰 레이아웃: macOS의 `HSplitView` ↔ iPadOS의 `NavigationSplitView` / `ViewThatFits`
  - 뷰어 바로 열기: macOS의 `NSWorkspace.shared` ↔ iOS의 `UIDocumentInteractionController`
