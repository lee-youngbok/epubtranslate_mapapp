# Changelog

이 프로젝트의 모든 주요 변경사항은 이 문서에 기록됩니다.
버전 표기는 [Semantic Versioning (유의적 버전 2.0.0)](https://semver.org/lang/ko/) 규칙을 따르며, 작성 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 준수합니다.

---

## [Unreleased]
### Added
- 

---

## [0.4.0] - 2026-10-27
### Added
- **글꼴(폰트) 커스터마이징 및 EPUB 표준 폰트 임베딩 (`FontManager`)**:
  - 기본값은 원본 EPUB 서체 유지(Zero-Override).
  - **언어별 원문(Source) & 번역문(Target) 독립 글꼴 지정**: 원문 문단과 번역문 문단의 글꼴을 서로 다르게 개별 설정할 수 있도록 확장.
  - **상업용 무료 추천 폰트 온디맨드 다운로드**:
    - 앱 번들 용량을 비대화하지 않고, 사용자가 폰트를 최초 선택하는 시점에 백그라운드 자동 다운로드 및 `Application Support/Fonts` 로컬 캐싱.
    - **한국어(`ko`)**: `Pretendard (프리텐다드 고딕)`, `KoPubWorld 바탕 (명조)` 제공.
    - **다국어(`en`, `ja`, `zh-Hans`, `zh-Hant`, `ar`, `th` 등)**: 언어별 특성에 맞춘 `Noto Sans` 패밀리(`Noto Sans`, `Noto Sans JP`, `Noto Sans SC`, `Noto Sans TC`, `Noto Sans Arabic`, `Noto Sans Thai`) 자동 매칭.
  - **EPUB 표준 패키징 임베딩**:
    - 선택된 상업 무료 폰트를 EPUB 내 `Fonts/` 디렉터리에 복사하고, `content.opf`의 `<manifest>`에 정식 등록(`media-type: font/otf, font/ttf, font/woff2`).
    - 챕터별 상대 경로를 정밀 계산하여 `@font-face` 규칙 및 클래스 스코프 CSS 주입. Apple Books, 크레마, 타 기기 어디서든 동일한 타이포그래피 유지.
  - **macOS 시스템 폰트 선택 지원**:
    - `NSFontManager`를 통해 사용자의 Mac에 설치된 시스템 서체 목록을 조회하고 CSS `font-family`로 즉시 연결.
  - **실시간 타이포그래피 미리보기**:
    - 다운로드된 폰트를 `CoreText`에 등록하여 설정 패널에서 원문/번역문 서체를 실시간 텍스트로 미리보기 제공.
  - **GitBook 공식 문서셋 신설 (`docs/`)**: 제품 소개, 시스템 아키텍처, 기능별 사용 가이드, 타이포그래피 및 FAQ 포함.

---

## [0.3.0] - 2026-10-27
### Added
- **문장 단위 지능형 분할 전처리**: 긴 문단 번역 시 번역 누락이나 길이 제한을 방지하기 위해 문장 단위로 분할하여 안전하게 번역한 후 결합하는 파이프라인 도입.
- **고유명사 및 용어 보호 (Placeholders)**: HTML 특수 태그, 코드, 인라인 용어 등이 번역 과정에서 왜곡되지 않도록 임시 토큰으로 치환 및 복원하는 보호 엔진 추가.
- **Apple 도서(Books) 앱 직접 열기**: 번역이 완료된 EPUB을 저장함과 동시에 macOS 기본 도서 앱에서 즉시 열어볼 수 있는 빠른 미리보기 액션 추가.
- **제품 및 아키텍처 정의서(`APP_DEFINITION.md`)**: 크로스 플랫폼(iOS/iPadOS) 확장 로드맵과 계층별 시스템 아키텍처 명세화.
- **버전 및 변경 이력 관리 체계 도입**: `CHANGELOG.md` 생성, `project.yml` 및 `Info.plist` 버전 동기화, UI 상단 버전 뱃지 표시.

---

## [0.2.0] - 2026-10-26
### Added
- **xcodegen 기반 프로젝트 빌드 환경**: `project.yml` 명세를 통한 빌드 설정 일원화 및 버전 관리 편의성 증대.
- **동적 번역 언어 목록 지원**: Apple Translation 프레임워크가 런타임에 지원하는 최신 언어 페어를 동적으로 가져오도록 개선.

### Fixed
- **번역 오류(Error Code 11 및 팝업) 방지**: 소스 언어(Source Language)를 명시적으로 전달하여 번역 실패 현상 해결.
- **EPUB XML 파싱 에러 수정**: Apple Books 등 엄격한 EPUB 리더에서 파싱 에러를 유발하는 정의되지 않은 HTML 엔티티(예: `&nbsp;`)를 XML 안전 엔티티로 정규화.
- **EPUB 재패키징 경로 버그 수정**: ZIP 아카이브 압축 시 절대 경로가 포함되어 뷰어가 파일을 인식하지 못하던 문제 해결.
- **샌드박스 보안 스코프 강화**: 사용자 파일 접근 시 보안 스코프 북마크 유효성 검사 및 안전한 접근 처리.
- **SwiftSoup 파싱 가드 및 CSS 셀렉터 오류 제거**: 빈 문서 파싱 시 크래시 방지 및 잘못된 CSS 셀렉터 정비.

### Changed
- 이중 언어(Bilingual) 번역 모드의 인용 스타일을 정돈하여 원서 대조 가독성 향상.

---

## [0.1.0] - 2026-04-24
### Added
- **EPUB Intelligence Translator 최초 프로토타입 구현**:
  - Apple Silicon Neural Engine(ANE) 온디바이스 번역 연동 (`Translation` 프레임워크).
  - EPUB 압축 해제, OPF 스파인 분석 및 챕터별 XHTML 텍스트 추출 (`EPUBParser`).
  - 3가지 번역 모드(이중 언어 대조, 번역문 대체, 주석 토글형) 지원 (`HTMLProcessor`).
  - EPUB 표준 규격(비압축 mimetype 선두 배치)에 맞춘 재패키징 (`EPUBPackager`).
  - 기본 SwiftUI macOS 인터페이스 및 진행률 대시보드.
