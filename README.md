# EPUB Intelligence Translator

<p align="center">
  <b>Apple Silicon Neural Engine 기반 온디바이스 전자책(EPUB) AI 번역기</b><br>
  비용 0원 • 100% 오프라인 프라이버시 • 원본 구조 100% 보존 • 언어별 맞춤 폰트 임베딩
</p>

---

## 📖 깃북(GitBook) 공식 문서
전체 기능 명세 및 아키텍처, 튜토리얼은 `docs/` 디렉터리의 [GitBook 문서](docs/README.md)에서 확인하실 수 있습니다:
- [목차 (SUMMARY.md)](docs/SUMMARY.md)
- [글꼴 및 타이포그래피 설정 가이드](docs/features/typography.md)
- [3가지 번역 모드 (이중 언어 / 대체 / 주석 토글)](docs/features/translation-modes.md)
- [시스템 아키텍처 및 데이터 흐름](docs/architecture/system-design.md)
- [Apple 도서(Books) 연동 가이드](docs/guide/apple-books.md)
- [자주 묻는 질문 (FAQ)](docs/guide/faq.md)

---

## ✨ 핵심 기능
1. **100% 온디바이스 프라이버시 & 비용 0원**:
   - 외부 클라우드 API(OpenAI, DeepL 등 유료 토큰) 없이 Mac의 Apple Silicon Neural Engine을 활용해 안전하고 빠르게 번역합니다.
2. **원본 서식 완벽 보존 (Zero-Destruction)**:
   - 본문 텍스트만 정교하게 번역하며, 기존 EPUB의 내부 구조(`META-INF`, `OEBPS`), 챕터 CSS 서식, 이미지, 목차(TOC)를 100% 보존합니다.
3. **글꼴(폰트) 커스터마이징 & EPUB 임베딩**:
   - 기본적으로 원본 서체를 유지하며, 필요 시 원문(언어별)과 번역문 글꼴을 각각 독립적으로 커스터마이징할 수 있습니다.
   - **Pretendard(고딕)**, **KoPubWorld 바탕(명조)**, **Noto Sans 다국어 패밀리**를 앱 최초 선택 시 온디맨드로 자동 다운로드하여 EPUB 내부에 표준 규격으로 직접 임베딩합니다.
   - macOS 시스템 설치 서체(`NSFontManager`)도 자유롭게 선택 가능합니다.
4. **유연한 3가지 번역 모드**:
   - **이중 언어 (Bilingual)**: 원문 아래 번역문 나란히 삽입 (원서 대조용)
   - **번역문 대체 (Replace)**: 원문을 번역문으로 치환 (일반 번역서용)
   - **주석/토글형 (Annotated)**: 번역문 표시 + `▶ 원문 보기` 클릭 펼침 버튼
5. **Apple 도서(Books) 서재 원클릭 직행**:
   - 번역 완료와 동시에 macOS 기본 도서 앱 서재로 전송하여 즉시 독서를 시작할 수 있습니다.

---

## 🛠️ 개발 및 빌드 환경
- **요구 사양**: macOS 15.0+ (Sequoia) 이상, Apple Silicon (M1/M2/M3/M4/M5)
- **개발 도구**: Xcode 16.0+, Swift 6.0+, xcodegen
- **의존성**:
  - `SwiftSoup`: XHTML/HTML DOM 조작 및 엔티티 정규화
  - `ZIPFoundation`: EPUB 표준 규격(비압축 mimetype 선두 배치) ZIP 패키징

---

## 📝 변경 이력
자세한 버전별 업데이트 내역은 [CHANGELOG.md](CHANGELOG.md)를 참고하세요.
