# EPUB Intelligence Translator

> **Apple Silicon Neural Engine 기반 온디바이스 전자책(EPUB) AI 번역기**

**EPUB Intelligence Translator**는 전자책(EPUB) 파일의 **원본 구조, 스타일(CSS), 이미지, 목차(TOC)를 100% 보존**하면서, Apple Silicon의 온디바이스 AI를 활용해 안전하고 빠르게 본문을 번역해 주는 macOS 네이티브 애플리케이션입니다.

---

### 주요 핵심 특징
- **100% 온디바이스 프라이버시**: 외부 클라우드 API 호출 없이 기기 내부 Apple Neural Engine에서 처리되므로 저작권 및 개인정보 유출 걱정이 없습니다.
- **원본 레이아웃 무손상 (Zero-Destruction)**: 텍스트 노드만 정교하게 번역하며, 기존 EPUB의 내부 구조와 스타일시트를 완벽히 유지합니다.
- **3가지 번역 모드**: 이중 언어(Bilingual) 대조, 번역문 대체(Replace), 주석/토글형(Annotated)을 제공합니다.
- **자유로운 글꼴(폰트) 커스터마이징**:
  - 기본 원본 폰트 유지
  - 원문(언어별)과 번역문 글꼴 독립 분리 설정
  - 검증된 상업 무료 폰트(Pretendard, KoPubWorld 바탕, Noto Sans) 온디맨드 다운로드 및 EPUB 표준 임베딩
  - macOS 시스템 설치 폰트 선택 지원
- **문장 단위 정밀 분할 & 고유명사/용어 보호**: `NaturalLanguage` 토크나이저와 용어집 마스킹 엔진 탑재.
- **Apple 도서(Books) 즉시 내보내기**: 번역 완료와 동시에 Apple 도서 앱 서재로 바로 전송.

---

### 시작하기
앱의 설치 및 실행, 주요 기능에 대한 자세한 안내는 왼쪽 사이드바 목차를 통해 확인하실 수 있습니다:
- [제품 개요 (Overview)](overview.md)
- [글꼴 및 타이포그래피 설정 (Typography)](features/typography.md)
- [번역 모드 안내 (Translation Modes)](features/translation-modes.md)
- [빠른 시작하기 (Quickstart)](guide/quickstart.md)
