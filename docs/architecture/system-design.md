# 시스템 설계 및 데이터 파이프라인 (System Design)

EPUB Intelligence Translator는 표준 EPUB 2/3 규격을 준수하며, 원본 구조를 훼손하지 않는 비파괴적(Zero-Destruction) 데이터 파이프라인으로 설계되었습니다.

---

## 데이터 파이프라인 흐름도

```mermaid
flowchart TD
    subgraph Import ["1. 추출 및 분석"]
        A["사용자 EPUB"] -->|ZIPFoundation| B["임시 작업 디렉토리"]
        B --> C["META-INF/container.xml 파싱"]
        C --> D[".opf 매니페스트 및 Spine 추출"]
        D --> E["LanguageDetector 병렬 분석"]
    end

    subgraph Prepare ["2. 폰트 및 리소스 준비"]
        E --> F["FontManager 폰트 검증"]
        F -->|온디맨드 다운로드| G["Fonts/ 디렉토리 복사"]
        G --> H[".opf <manifest> 폰트 항목 등록"]
    end

    subgraph Translation ["3. 온디바이스 번역 & DOM 가공"]
        H --> I["HTMLProcessor XHTML DOM 추출"]
        I --> J["고유명사 마스킹 및 문장 분할"]
        J --> K["Apple TranslationSession 배치 번역"]
        K --> L["용어 언마스킹 및 문맥 윤문"]
        L --> M["모드별 DOM 변환 및 @font-face CSS 주입"]
    end

    subgraph Packaging ["4. EPUB 표준 재패키징"]
        M --> N[".opf 메타데이터(제목, 저자, 언어) 갱신"]
        N --> O["mimetype 비압축(Stored) 제1엔트리 생성"]
        O --> P["전체 디렉토리 Deflate 압축 아카이브"]
        P --> Q["최종 번역 EPUB 출력 / Apple 도서 전달"]
    end
```

---

## 주요 엔지니어링 세부사항

### 1. 엄격한 EPUB 규격 준수 (`EPUBPackager`)
- EPUB 파일은 ZIP 규격 기반이지만, 표준 사양에 따라 **`mimetype` 파일이 아카이브의 반드시 첫 번째 엔트리(Entry 0)**여야 하며, **어떠한 압축도 되지 않은 비압축(Stored / Compression Method: None)** 상태여야 합니다.
- `EPUBPackager`는 `ZIPFoundation`을 직접 제어하여 이 엄격한 규격을 100% 준수합니다.

### 2. 챕터별 폰트 상대 경로 정밀 산출
- EPUB 도서마다 내부 폴더 구조가 상이합니다 (예: `OEBPS/Text/ch01.xhtml` vs `OPS/ch01.html`).
- `HTMLProcessor.relativePath(from:to:)` 알고리즘이 챕터 파일의 디렉터리 경로와 `Fonts/` 디렉터리의 상대적 깊이를 자동 계산하여, `@font-face { src: url(...) }`이 어떤 구조에서도 정확히 폰트를 참조하도록 합니다.

### 3. XML 파서 호환성 보장
- 많은 EPUB 리더(특히 Apple Books)는 엄격한 XML 파서를 사용합니다.
- HTML 전용 특수 엔티티(예: `&nbsp;`, `&copy;`, `&mdash;` 등)가 XML DTD 없이 포함되면 파싱 크래시가 발생하므로, 모든 엔티티를 정규 수치 문자 참조(예: `&#160;`, `&#169;`, `&#8212;`)로 안전하게 치환합니다.
