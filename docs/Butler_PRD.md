# Butler PRD — 임대인 건물관리 앱 (PoC)

> 본 문서는 기획서 + 와이어프레임(v20)을 기준으로 작성된 PoC 구현용 PRD다.
> **문서는 하나로 통합되어 있으나, 4장 각 플로우 섹션은 self-contained하게 작성되어
> Claude Code에 플로우 단위로 떼어 줄 수 있다.** (투입 방법은 8장 참조)

- **버전:** PoC v1.0
- **프론트엔드:** Vue.js
- **백엔드:** FastAPI (Python) + Supabase (Postgres / Auth / Storage / Auto REST)
- **목표 마감:** 다음 주 목요일 (PoC 시연 가능 수준)

---

## 1. 개요 · 목표 · 범위

### 1.1 한 줄 정의
임대인이 건물·세입자·수납·지출을 한 화면에서 관리하고, 반복 안내 업무와 수선비 분쟁을 줄이도록 돕는 모바일 앱.

### 1.2 PoC가 증명할 4개 핵심 플로우
| 플로우 | 한 줄 |
| --- | --- |
| ① 온보딩·건물 등록 | 빈 상태 → 모달 → (에러 분기) → 건물 등록 → 목록 자동 진입 |
| ② 건물 목록 + 상세 4개 탭 | 목록 → 카드 선택 → 정보·세입자·수납·지출 탭 스와이프 |
| ③ AI 수선비 분담 | 지출 탭 수리비 항목 → 수선 정보 입력 → LH·판례 기반 비율·근거 산출 |
| ④ 자동 알림톡 | 정보 탭 알림 아이콘 → 히스토리 → 미리보기·발송 스케줄 |

### 1.3 목표
- **관리 효율화** — 건물·세입자·수납·지출 단일 앱 관리
- **분쟁 감소** — 수선비 분담을 LH·판례 근거로 제시
- **정보 비대칭 해소** — 분담 비율·금액·근거 출처를 함께 노출
- **데이터 축적** — 수납 이력·미납 패턴·지출·메모 기록
- **PoC 검증** — 4개 플로우를 시연 가능 수준으로 구현

### 1.4 범위
**In Scope**
- 온보딩 및 건물 등록(에러 처리 포함)
- 건물 목록 + 상세 4개 탭(정보·세입자·수납·지출)
- AI 수선비 분담(LLM + 프롬프트, RAG-lite)
- 자동 알림톡 **UI** (히스토리·미리보기·발송 스케줄)
- 증빙 유형 분류(세금계산서·현금영수증·간이영수증) 표시

**Out of Scope** (6장 가정 참조)
- 실결제 / PG · 자동 수납 연동
- **카카오 알림톡 실제 발송 연동 → mock 처리** (6.1 필독)
- 세입자용 별도 앱
- 학습형 AI 모델 자체 학습
- 서울시 외 다지역 운영, 회계·세무 시스템 연동

---

## 2. 기술 스택 & 아키텍처

### 2.1 스택
| 레이어 | 기술 | 역할 |
| --- | --- | --- |
| Frontend | Vue.js (Vue 3 + Vite 권장) | 화면·탭 스와이프·상태 관리 |
| BaaS | Supabase | Postgres DB, Auth, Storage(PDF), 자동 REST API |
| Backend | FastAPI (Python) | AI 수선비 분담, 알림톡 발송 로직(mock), 비즈니스 로직 |
| AI | LLM API(OpenAI/Anthropic) + 프롬프트(RAG-lite) | 분담 비율·근거 문장 생성 |

### 2.2 책임 분담 원칙
> **CRUD성 작업은 Supabase에, 진짜 로직만 FastAPI에.** PoC 기간 단축의 핵심.

- **Supabase 직결 (Vue → Supabase client):**
  건물·세입자·계약·수납·지출의 조회/등록/수정, 집계(입주율·미납·임대수익 등은 View 또는 RPC)
- **FastAPI 경유 (Vue → FastAPI → LLM/외부):**
  AI 수선비 분담 계산, 알림톡 미리보기 생성·발송(mock)·스케줄 계산

### 2.3 아키텍처 다이어그램
```
┌───────────┐    Supabase JS client     ┌──────────────────────┐
│           │  (CRUD · 집계 · Auth)      │  Supabase            │
│  Vue.js   │ ────────────────────────▶ │  - Postgres (테이블) │
│  (모바일  │                            │  - Auth              │
│   웹/앱)  │                            │  - Storage (PDF)     │
│           │     REST (custom logic)    └──────────────────────┘
│           │ ────────────┐                         ▲
└───────────┘             ▼                         │ (service role)
                   ┌──────────────┐                 │
                   │   FastAPI    │ ────────────────┘
                   │  - /repair-allocation (AI)
                   │  - /notifications/* (mock)
                   └──────┬───────┘
                          ▼
                   ┌──────────────┐
                   │  LLM API     │  (RAG-lite: 가이드·판례 10~20개 프롬프트 주입)
                   └──────────────┘
```

---

## 3. 데이터 모델

> Supabase(Postgres) 기준. 집계 지표(입주율·미납·임대수익 등)는 **테이블 컬럼이 아니라 View/RPC로 계산**한다.
> 화면에 보이는 수치는 와이어프레임 실제 값을 시드 데이터로 사용한다.

```sql
-- 건물
create table buildings (
  id              uuid primary key default gen_random_uuid(),
  business_reg_no text,                       -- 사업자등록번호(등록 기준)
  name            text not null,              -- "Butler 03호점(건대)"
  address         text not null,              -- "서울 마포구 신촌로 12"
  unit_count      int  not null,              -- 세대/호수 (예: 16)
  building_type   text not null,              -- "다세대주택"
  account_info    text not null,              -- 입금계좌
  is_favorite     boolean default false,      -- 즐겨찾기(★)
  created_at      timestamptz default now()
);

-- 세입자
create table tenants (
  id          uuid primary key default gen_random_uuid(),
  building_id uuid references buildings(id) on delete cascade,
  name        text not null,                  -- "김동락"
  memo        text,                           -- "반려견 키우면서 월세·관리비 밀림"
  created_at  timestamptz default now()
);

-- 계약 (세입자당 다중 계약서 지원: "다른 계약서 총 2건")
create table contracts (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid references tenants(id) on delete cascade,
  building_id     uuid references buildings(id) on delete cascade,
  unit_no         text not null,              -- "101호"
  contract_start  date not null,              -- 2020-12-12
  contract_end    date not null,              -- 2022-12-11
  deposit         bigint not null,            -- 보증금 10,000,000
  monthly_rent    bigint not null,            -- 월세 550,000 (부가세 포함)
  maintenance_fee bigint not null,            -- 관리비 94,500 (부가세 포함)
  lease_type      text not null,              -- '월세' | '전세'
  status          text not null,              -- '계약중' | '만료' | '종료'
  is_primary      boolean default true,       -- 대표 계약 여부
  created_at      timestamptz default now()
);

-- 수납 (회차별)
create table payments (
  id          uuid primary key default gen_random_uuid(),
  contract_id uuid references contracts(id) on delete cascade,
  round_no    int not null,                   -- 회차 (6,7,8,9 ...)
  amount      bigint not null,                -- 650,000
  due_date    date not null,                  -- 입금 예정일
  status      text not null,                  -- '대기' | '미납' | '완납'
  paid_date   date,                           -- 완납 시점
  is_postpaid boolean default false           -- 후불 표시
);

-- 지출
create table expenses (
  id          uuid primary key default gen_random_uuid(),
  building_id uuid references buildings(id) on delete cascade,
  expense_date date not null,                 -- 22.10.10
  title       text not null,                  -- "201호 냉장고 수리비"
  amount      bigint not null,                -- 165,000
  proof_type  text,                           -- '세금계산서'|'현금영수증(개인)'|'간이영수증'
  is_repair   boolean default false           -- true면 AI 분담 진입 가능 항목
);

-- AI 수선비 분담 결과
create table repair_allocations (
  id              uuid primary key default gen_random_uuid(),
  expense_id      uuid references expenses(id) on delete cascade,
  item            text not null,              -- "201호 냉장고 수리"
  cost            bigint not null,            -- 165,000
  cause           text not null,              -- '노후·자연마모' | '사용 부주의'
  usage_years     int,                        -- 설치 후 7년
  landlord_ratio  int not null,               -- 70
  tenant_ratio    int not null,               -- 30
  landlord_amount bigint not null,            -- 115,500
  tenant_amount   bigint not null,            -- 49,500
  basis_lh        text,                       -- LH 가이드라인 근거 문장
  basis_court     text,                       -- 대법원 판례 근거 문장
  created_at      timestamptz default now()
);

-- 알림톡 (발송은 mock — sent_at/status로 시뮬레이션)
create table notifications (
  id           uuid primary key default gen_random_uuid(),
  contract_id  uuid references contracts(id) on delete cascade,
  type         text not null,                 -- '납부'|'미납'|'연장'|'종료'
  title        text not null,                 -- "납부 1일전 알림톡 발송"
  body         text,                          -- 템플릿 치환된 메시지 본문
  pdf_url      text,                          -- Supabase Storage PDF 경로
  scheduled_at timestamptz,                   -- 발송 예정 시점
  sent_at      timestamptz,                   -- (mock) 발송 처리 시점
  status       text default 'mock_sent'       -- 'scheduled'|'mock_sent'
);
```

**집계 지표 (View 또는 RPC로 계산, 컬럼 아님)**
- 입주율 = 계약중 세대 / 전체 세대 (예: 15/16 = 93.7%)
- 월세/전세/공실 세대 수, 이달 신규·만료 계약 수
- 총 보증금 합계, 임대수익(월세 합계)
- 미납 건수·금액

---

## 4. 기능 요구사항 — 플로우별 ★본문★

> 각 4.x 섹션은 **Claude Code 한 세션의 작업 지시서**로 그대로 사용 가능하다.
> 구성: `관련 화면·상태` / `분기·예외` / `데이터·API` / `완료 기준`

---

### 4.1 [Flow A] 온보딩 · 건물 등록

**관련 화면·상태**
- **빈 상태(화면 1):** 등록 건물 없음. "등록된 건물이 없습니다 😅 / 건물과 세입자 정보를 등록해 주세요". 우하단 FAB(+) (펄스 애니메이션). 상단 정보/세입자/수납 탭, 하단 네비(건물관리·더보기), 프로모션 배너.
- **건물 관리 모달(화면 2):** FAB(+) 탭 시 바텀시트. 제목 "건물 관리 / 편리하고 효율적인 건물 관리를 위해". 분기 2개 — 🏢 **건물등록** / 👥 **세입자 등록**.
- **건물 등록 폼(화면 3):** 사업자등록번호 기준. 입력 필드 — 건물 주소, 건물명, 세대/호수, 건물 유형, 계좌 정보. **모두 필수(●)**. 하단 [등록하기] 버튼.

**분기·예외**
- 모달에서 **🏢 건물등록 선택 → 정상 흐름** → 등록 폼(화면 3)
- 모달에서 **👥 세입자 등록 선택(건물 미등록 상태) → 차단** → 빨간 토스트(화면 2a):
  `❗ 등록된 건물이 없습니다. 건물을 등록해주세요`
  → 세입자는 반드시 건물 소속이므로, 건물이 없으면 막고 건물 등록으로 유도.
- 등록 폼에서 **필수 필드 누락 시 [등록하기] 비활성/검증 에러**.
- 등록 성공 → **자동으로 건물 목록(화면 5, Flow B)로 이동**.

**데이터·API**
- `buildings` insert (Supabase 직결). business_reg_no, name, address, unit_count, building_type, account_info.
- 세입자 등록 차단은 **프론트 가드 로직** (건물 count == 0 체크) — 별도 API 불필요.

**완료 기준**
- [ ] 빈 상태에서 FAB(+) → 모달 노출
- [ ] 건물 미등록 상태에서 세입자 등록 시도 → 빨간 토스트로 차단 + 건물 등록 유도
- [ ] 필수 5개 필드 입력 후 등록 → 성공 → 목록 화면 자동 진입

---

### 4.2 [Flow B] 건물 목록 + 상세 4개 탭

> ⚠ **이 플로우는 가장 무겁다.** Claude Code 투입 시 `목록+정보 탭` / `세입자·수납·지출 탭` 2회로 쪼갤 것 (8장 참조).

**관련 화면·상태**

**(B-1) 건물 목록 (화면 5)**
- 상단 토글: 전체 / 건물별, 건물 검색, 즐겨찾기(★)
- 건물 카드 (와이어프레임 시드 데이터):
  - Butler 01호점(서울역) — 신규 1 / 만료 2, 임대현황 100%(30/30), 1,850,000원
  - Butler 02호점(신촌) — 만료 1 / 미납 2, 85.7%(12/14), 1,925,000 / 2,200,000원
  - Butler 03호점(건대) — 93.7%(15/16), 8,500,000원
- 카드 탭 → 단일 건물 상세(정보 탭, 화면 4)

**(B-2) 정보 탭 (화면 4)** — 상단 우측 **알림 아이콘**(→ Flow D 진입점)
- 임대 현황 (15/16) 93.7% 입주율
- 월세 세대 14 / 전세 세대 1 / 공실 1
- 이달의 신규 1 / 이달의 만료 0
- 총 보증금 1.6억 원 / 임대수익 8,500,000원

**(B-3) 세입자 탭 (화면 6)**
- 김동락 (계약중), 📄 다른 계약서 총 2건
- 메모(✎): "반려견 키우면서 월세·관리비를 조금 밀리는 경향 😤"
- 계약정보: Butler 03호점 / 101호, 2020.12.12 ~ 2022.12.11
- 액션: 계약 연장 / 계약 종료
- 보증금 10,000,000 / 월세 550,000(부가세 포함) / 관리비 94,500(부가세 포함)

**(B-4) 수납 탭 (화면 7)**
- 김동락(101호), 매월 납부액 650,000, 미납 1건 650,000, 월세 후불, 입금 예정일 12일
- 회차 리스트: 9회차 **대기** 650,000 / 8회차 **미납** 650,000 D+12 / 7회차 **완납** 💳650,000 / 6회차 **완납** 💳650,000

**(B-5) 지출 탭 (화면 8)**
- 이번 달 지출 1,221,000원 4건
  - 99,000 에어컨 청소 — 세금계산서
  - **165,000 201호 냉장고 수리비 — `AI 분담 ▸` (탭하면 Flow C 진입)**
  - 880,000 옥상 방수공사 — 현금영수증(개인)
  - 77,000 도어록 교환 — 간이영수증

**분기·예외**
- 4개 탭은 **좌우 스와이프**로 이동(정보 ↔ 세입자 ↔ 수납 ↔ 지출).
- 정보 탭 우측 상단 **알림 아이콘 탭 → Flow D(알림톡 히스토리)**.
- 지출 탭에서 **`is_repair=true`(수리비) 항목만 `AI 분담 ▸` 노출**, 탭 시 Flow C 진입.

**데이터·API**
- 건물 목록·카드 지표: `buildings` + 집계 View/RPC (Supabase 직결)
- 정보 탭 지표: 집계 RPC (입주율·세대구성·보증금·임대수익)
- 세입자/계약/수납/지출: 각 테이블 조회 (Supabase 직결)

**완료 기준**
- [ ] 목록 카드 탭 → 단일 건물 정보 탭 진입
- [ ] 정보·세입자·수납·지출 4개 탭 스와이프 정상 동작
- [ ] 수납 탭 회차별 대기·미납·완납 상태 구분 표시
- [ ] 지출 탭 수리비 항목에 `AI 분담 ▸` 노출, 탭 시 Flow C 진입
- [ ] 정보 탭 알림 아이콘 탭 시 Flow D 진입

---

### 4.3 [Flow C] AI 수선비 분담

**관련 화면·상태**

**(C-1) 수선 정보 입력 (화면 13)**
- 안내문: "수선 정보를 입력하면 LH 가이드라인·대법원 판례를 학습한 AI가 분담 비율을 계산합니다."
- 입력 필드:
  - 수선 항목 (예: "201호 냉장고 수리") — 지출 항목에서 prefill
  - 수선 비용 (예: 165,000) — prefill
  - **발생 원인** (선택: 노후·자연마모 / 사용 부주의) ← 비율 산출 핵심 변수
  - **사용 연수 / 설치** (예: 설치 후 7년 경과) ← 핵심 변수
- [AI 분담 비율 계산하기] 버튼 → 분석 1~2초 (로딩 표시)

**(C-2) AI 분담 결과 · 근거 (화면 14)**
- AI 산출 분담 비율: **임대인 70% / 임차인 30%**
- 총 수선비 165,000 / 임대인 부담 115,500 / 임차인 부담 49,500
- 📑 산출 근거:
  - **LH 가이드라인:** 빌트인 가전의 노후·자연마모 고장은 임대인 부담 원칙. 사용 7년 경과분 감가 반영.
  - **대법원 판례:** 통상적 사용에 따른 손모는 특약 없는 한 임대인 부담. 임차인 과실분만 일부 분담.
- 면책 문구(필수 노출): "본 분담 비율은 참고용 산출 결과이며, 최종 판단 및 법적 책임은 이용자 본인에게 있습니다."

**분기·예외**
- 진입점: Flow B 지출 탭의 수리비 항목 `AI 분담 ▸`.
- **PoC 안정성:** LLM 실시간 호출 + **데모용 고정 시나리오 병행**. 어떤 입력이 실시간이고 어떤 입력이 고정 응답인지 명시 필요. (대표 시나리오: 냉장고 / 노후·자연마모 / 7년 → 70:30 고정)
- LLM 응답 실패/타임아웃 → 고정 시나리오 fallback.

**데이터·API**
- `POST /api/repair-allocation` (FastAPI)
  - req: `{ item, cost, cause, usage_years }`
  - res: `{ landlord_ratio, tenant_ratio, landlord_amount, tenant_amount, basis_lh, basis_court }`
- **RAG-lite:** LH 가이드라인 핵심 규칙 + 대법원 판례 요약 **10~20개를 프롬프트(system)에 텍스트로 주입**. 벡터 DB 불필요.
- 결과를 `repair_allocations`에 저장(Supabase).

**LLM 구현 — Anthropic Claude (확정)**
- **SDK:** Python `anthropic` 패키지 (`pip install anthropic`)
- **인증:** 환경변수 `ANTHROPIC_API_KEY` (Console에서 발급, 구독과 별개로 사용량 과금)
- **모델:** PoC 기본값 `claude-haiku-4-5-20251001` (저렴·빠름, 분담 판단에 충분). 근거 문장 품질을 더 높이려면 `claude-sonnet-4-6`로 교체.
- **구조화 출력:** system에 "JSON만 출력(서두·코드펜스 없이)" 명시 → 응답을 `json.loads`로 파싱. 파싱 실패/타임아웃 → 고정 시나리오 fallback.

```python
# app/services/repair_allocation.py
import json, os
from anthropic import Anthropic

client = Anthropic()  # ANTHROPIC_API_KEY 환경변수 자동 사용

# RAG-lite: LH 가이드라인 + 대법원 판례 요약 10~20개를 여기에 주입
GUIDELINES = """
[LH 가이드라인]
- 빌트인 가전의 노후·자연마모 고장은 임대인 부담 원칙. 사용 연수에 따라 감가 반영.
- ... (핵심 규칙 10~20개)
[대법원 판례 요약]
- 통상적 사용에 따른 손모는 특약이 없는 한 임대인 부담. 임차인 과실분만 일부 분담.
- ... (판례 요약)
"""

SYSTEM = f"""너는 임대차 수선비 분담 비율 산출기다.
아래 기준만 근거로 임대인/임차인 분담 비율을 정한다.
{GUIDELINES}
반드시 아래 JSON 스키마로만 응답한다(서두·설명·코드펜스 금지):
{{"landlord_ratio": int, "tenant_ratio": int,
  "basis_lh": "LH 근거 한 문장", "basis_court": "판례 근거 한 문장"}}
비율 합은 100. 노후·자연마모는 임대인 비중↑, 사용 부주의는 임차인 비중↑,
사용 연수가 길수록 임대인 비중↑."""

# 데모 안정성: 대표 시나리오는 고정 (LLM 미호출)
FIXED = {("냉장고", "노후·자연마모", 7): {"landlord_ratio": 70, "tenant_ratio": 30,
    "basis_lh": "빌트인 가전의 노후·자연마모 고장은 임대인 부담 원칙. 사용 7년 경과분 감가 반영.",
    "basis_court": "통상적 사용에 따른 손모는 특약 없는 한 임대인 부담. 임차인 과실분만 일부 분담."}}

def allocate(item: str, cost: int, cause: str, usage_years: int) -> dict:
    key = next((k for k in FIXED if k[0] in item and k[1] == cause and k[2] == usage_years), None)
    if key:
        r = FIXED[key]
    else:
        try:
            msg = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=512,
                system=SYSTEM,
                messages=[{"role": "user",
                    "content": f"항목:{item}, 비용:{cost}, 원인:{cause}, 사용연수:{usage_years}"}],
            )
            r = json.loads(msg.content[0].text)
        except Exception:
            r = {"landlord_ratio": 50, "tenant_ratio": 50,
                 "basis_lh": "기준 적용 곤란 시 균등 분담(임시).", "basis_court": ""}
    r["landlord_amount"] = round(cost * r["landlord_ratio"] / 100)
    r["tenant_amount"] = cost - r["landlord_amount"]
    return r
```
> ⚠ 백엔드 실행 셸에 `ANTHROPIC_API_KEY`가 설정돼 있으면, 그 셸에서 Claude Code를 함께 돌릴 때 키가 구독 인증보다 우선 적용되어 API 과금될 수 있다. 빌드용 터미널과 앱 실행용 키 환경을 분리할 것.

**완료 기준**
- [ ] 지출 수리비 항목 → 수선 정보 입력 화면 진입(항목·비용 prefill)
- [ ] 원인/연수 입력 후 계산 → 비율·금액 산출
- [ ] 결과에 LH 가이드라인·대법원 판례 **근거 출처** 노출
- [ ] 면책 문구 노출
- [ ] 대표 시나리오(냉장고/노후/7년 → 70:30) 시연 안정 동작

---

### 4.4 [Flow D] 자동 알림톡 (★실제 발송은 mock — 6.1 필독)

**관련 화면·상태**

**(D-1) 알림톡 히스토리 (화면 11)**
- 안내: "세입자에게 발송되는 알림톡 내역입니다"
- **종류별 색상 태그 + 발송일 타임라인** (종류: 납부 / 미납 / 연장 / 종료):
  - 종료 · 22.12.11 · 계약종료 알림톡 발송
  - 납부 · 22.11.11 · 납부 1일전 알림톡 발송
  - 미납 · 22.09.18 · 미납 7일차 알림톡 발송
  - 납부 · 22.09.11 · 납부 1일전 알림톡 발송
  - 연장 · 22.09.11 · 연장 여부 알림톡 발송
  - 납부 · 22.08.11 · 납부 1일전 알림톡 발송
  - 미납 · 22.06.14 · 미납 2일차 알림톡 발송

**(D-2) 알림톡 미리보기 · 발송 시점 (화면 12)**
- 카카오톡 메시지 미리보기 (발신: "Butler 알리미"):
  - `[임대료 납부 안내] 김동락님`
  - 세대정보 / 납부총액(예: 700,000) / 납부기한(예: 12월 31일) / 입금계좌
  - [카드로 결제하기] (UI only)
- 📋 알림톡 전송 시점 스케줄:
  - **D-1 · D-day** — 납부 안내 — 18:00 자동발송
  - **D+2 · 4 · 7** — 미납 안내 — 13:00 자동발송
  - **D-60** — 연장 여부 안내 — AM 10:00 발송
  - **D-3** — 계약 종료 안내 — AM 10:00 발송

**분기·예외**
- 진입점: Flow B 정보 탭 우측 상단 알림 아이콘 → 히스토리(D-1) → 항목 탭 → 미리보기(D-2).
- **🚨 실제 카카오 알림톡 발송은 PoC 범위 외(mock).** 발송 스케줄 계산 + 미리보기 + 히스토리 표시까지만 진짜로 구현. (이유·근거는 6.1)

**데이터·API**
- 히스토리 조회: `notifications` 조회 (Supabase 직결) 또는 `GET /api/notifications?contract_id=`
- 미리보기 생성: `POST /api/notifications/preview` (FastAPI) — 템플릿 + 계약 데이터 치환
- 발송: `POST /api/notifications/send` → **실제 발송 대신 `status='mock_sent'`, `sent_at=now()` 기록만** (실제 카카오 API 미연동)
- 스케줄 계산: 계약 due_date 기준 D-1/D+2,4,7/D-60/D-3 시점 계산 로직(FastAPI)

**완료 기준**
- [ ] 정보 탭 알림 아이콘 → 히스토리 진입
- [ ] 종류별(납부·미납·연장·종료) 색상 태그 + 발송 타임라인 표시
- [ ] 항목 탭 → 카카오톡 미리보기 노출
- [ ] D-1 / D+n / D-60 / D-3 발송 스케줄 표시
- [ ] 발송은 mock 처리(실제 카카오 연동 없이 히스토리 기록)

---

## 5. 화면 카탈로그 (13종 · 부록)

| No. | 화면명 | 플로우 | 주요 구성요소 |
| --- | --- | --- | --- |
| 1 | 빈 상태 | A | 건물 없음 안내, FAB(+), 상단 탭, 프로모션 배너 |
| 2 | 건물 관리 모달 | A | 건물등록 / 세입자 등록 분기 바텀시트 |
| 2a | 에러 처리 | A | 세입자 먼저 시도 시 빨간 토스트 |
| 3 | 건물 등록 | A | 주소·건물명·세대/호수·유형·계좌 폼(모두 필수), 등록하기 |
| 5 | 건물 목록 | B | 카드 리스트, 임대현황·입주율·미납, 검색·즐겨찾기 |
| 4 | 정보 탭 | B | 임대현황·입주율·세대구성·신규/만료·보증금·임대수익, 알림 아이콘 |
| 6 | 세입자 탭 | B | 계약정보·보증금/월세/관리비·메모·연장/종료 |
| 7 | 수납 탭 | B | 회차별 대기·미납·완납, 미납 요약, 입금 예정일, 후불 |
| 8 | 지출 탭 | B | 지출 내역·증빙 유형, 수리비 → AI 분담 진입 |
| 13 | 수선 정보 입력 | C | 항목·비용·원인·연수 입력, 계산 버튼 |
| 14 | AI 분담 결과 | C | 임대인/임차인 비율·금액, LH·판례 근거, 면책 문구 |
| 11 | 알림톡 히스토리 | D | 종류별 색상 태그 + 발송 타임라인 |
| 12 | 알림톡 미리보기 | D | 카카오톡 미리보기, D-1/D+n/D-60/D-3 스케줄 |

---

## 6. 범위 외 · 가정 (★중요)

### 6.1 🚨 카카오 알림톡 — 실제 발송은 mock 처리
> **반드시 PRD에 명시된 전제.** 카카오 알림톡 실제 발송은 다음이 선행돼야 한다:
> 카카오 비즈니스 채널 개설 → 발신 프로필 등록 → **템플릿 심사(영업일 며칠 소요)**.
>
> 목요일 마감 PoC 기간 내에는 심사 통과가 불가능하다. 따라서 **실제 발송은 mock 처리**하고,
> **히스토리 · 미리보기 · 발송 스케줄 UI까지만 진짜로 구현**한다.
> 발송 인프라 연동은 차기 범위로 분리한다. (실결제 연동을 제외한 것과 동일한 기조)

### 6.2 기타 가정
- 실결제 / PG / 자동 수납 연동 없음 — 수납 상태는 시드 데이터/수동 변경.
- AI 수선비 분담은 학습형 모델이 아닌 **LLM + 프롬프트(RAG-lite)**, 데모 안정성을 위해 일부 시나리오 고정.
- 데이터는 와이어프레임 기준 **시드 데이터**로 시연(서울 지역, 단일 임대인 기준).
- 인증은 Supabase Auth 단일 임대인 계정 수준(다중 임대인·위탁사 범위 외).

---

## 7. 일정 (WBS)

| 구간 | 작업 | 산출물 |
| --- | --- | --- |
| Day 1 | 프로젝트 셋업 · 데이터 모델 · 시드 | Vue+FastAPI 스캐폴드, Supabase 테이블, CLAUDE.md |
| Day 2 | Flow A (온보딩·건물 등록·에러) | 화면 1·2·2a·3 |
| Day 3 | Flow B-1 (목록 + 정보 탭) | 화면 5·4 |
| Day 4 | Flow B-2 (세입자·수납·지출 탭 + 스와이프) | 화면 6·7·8 |
| Day 5 | Flow C (AI 수선비 분담 · RAG-lite) | 화면 13·14, /api/repair-allocation |
| Day 6 | Flow D (알림톡 UI · mock) | 화면 11·12, /api/notifications/* |
| Day 7 (목) | 통합·시나리오 고정·데모 안정화 | PoC 시연 |

---

## 8. Claude Code 투입 가이드 (★마지막)

> **PRD 통째로 던지지 말 것.** 컨텍스트가 길면 디테일을 놓치고 에러가 누적된다.
> 공유 기반은 `CLAUDE.md`(자동 로드)에 두고, **4장 플로우를 1세션 1플로우로 투입**한다.

### 8.1 사전 준비
1. 본 PRD를 레포 `/docs/Butler_PRD.md`에 둔다.
2. 함께 제공한 `CLAUDE.md`를 레포 루트에 둔다 — 스택·아키텍처·컨벤션·데이터 모델·범위(특히 알림톡 mock)가 **매 세션 자동 로드**된다.

### 8.2 투입 순서 (세션 단위)
```
① [기반] 스캐폴드 + 데이터 모델
   "CLAUDE.md 기준으로 Vue+Vite, FastAPI, Supabase 연결을 세팅하고
    3장 데이터 모델 DDL로 테이블 + 시드 데이터를 만들어줘."

② [Flow A] "PRD 4.1만 구현해. 기반은 CLAUDE.md 참조."
   → 동작 확인 → 커밋

③ [Flow B-1] "PRD 4.2의 B-1·B-2(목록 + 정보 탭)만 구현."   ← B는 무거워서 분할
   → 확인 → 커밋
④ [Flow B-2] "PRD 4.2의 B-3·B-4·B-5(세입자·수납·지출) + 탭 스와이프."
   → 확인 → 커밋

⑤ [Flow C] "PRD 4.3만 구현. /api/repair-allocation + RAG-lite 프롬프트.
            대표 시나리오(냉장고/노후/7년→70:30)는 고정."
   → 확인 → 커밋
⑥ [Flow D] "PRD 4.4만 구현. 발송은 mock(6.1). 미리보기·히스토리·스케줄 UI까지만."
   → 확인 → 커밋

⑦ [통합] 시나리오 고정 · 데모 안정화
```

### 8.3 각 세션 프롬프트 원칙
- **범위를 한 플로우로 못박기:** "PRD 4.x만. 다른 플로우는 건드리지 마."
- **완료 기준을 검증 지시로:** 각 플로우 끝의 체크리스트를 그대로 "이 항목들 만족하는지 확인해"로 전달.
- **플로우 끝나면 커밋 후 새 세션** — 컨텍스트를 깨끗이 유지.
- **공유 변경(테이블·컨벤션)은 CLAUDE.md를 먼저 갱신**한 뒤 다음 세션 진행.
