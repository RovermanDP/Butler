# Butler — 임대인 건물관리 앱 (PoC)

> 스택·아키텍처·컨벤션·데이터 모델·범위는 `CLAUDE.md`, 기능 명세는 `docs/Butler_PRD.md` 참조.

## 구조
```
butler/
├── frontend/   Vue 3 + Vite  (Supabase 직결: CRUD·집계·Auth)
├── backend/    FastAPI       (AI 수선비 분담·알림톡 mock 등 커스텀 로직)
├── supabase/   schema.sql · seed.sql  (Postgres 데이터 모델 + 시드)
└── docs/       PRD · 와이어프레임
```

## 1. Supabase 준비
1. [supabase.com](https://supabase.com) 에서 프로젝트 생성.
2. **SQL Editor** 에서 상황에 맞는 경로 하나를 선택해 실행:

   **(A) 새로 시작 / 데모용 (기존 데이터 없음·날려도 됨)**
   - `supabase/schema.sql` — ⚠ **전체 drop 후 재생성(기존 데이터 삭제)**. 테이블·CHECK 제약·집계 View.
   - `supabase/seed.sql` — 와이어프레임 시드 데이터(비파괴·idempotent라 여러 번 실행해도 중복 없음).

   **(B) 이미 운영 중 / Flow A 건물 데이터 보존 (절대 삭제 금지)**
   - `supabase/migrate_tenant_fields.sql` **하나만** 실행 — drop/truncate 없이 세입자 등록 신규
     컬럼·`contractors`·CHECK 제약만 추가(재실행 안전).
   - ❌ 이 경우 `schema.sql`은 실행하지 말 것(전체 삭제됨).
   - (선택) 데모 데이터도 함께 보고 싶으면 `seed.sql`을 추가 실행 — 비파괴라 기존 건물을
     지우지 않고 데모 건물(01~03호점·김동락)만 덧입힌다.

3. **Project Settings → API** 에서 키 복사:
   - `URL`, `anon public` → 프론트엔드
   - `service_role` → 백엔드

> ⚠ PoC 전용: 단일 임대인 기준이라 RLS 미사용(전체 허용). 실서비스 전환 시 RLS 정책 추가.
> ⚠ enum/조건부 필수값은 DB CHECK 제약으로 방어한다(tenant_type·lease_type·proof_kind,
>    전세=보증금 필수·월세 없음, 사업자=휴대폰 필수 등). 잘못된 값 직결 insert는 거부된다.

## 2. 프론트엔드 (Vue + Vite)
```bash
cd frontend
cp .env.example .env.local   # VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 채우기
npm install
npm run dev                  # http://localhost:5173
```

## 3. 백엔드 (FastAPI)

> AI 수선비 분담(Flow C)·알림톡 mock(Flow D) 등 커스텀 로직 전용. CRUD·집계는 프론트가
> Supabase 직결로 처리하므로 백엔드 없이도 대부분 화면은 뜨지만, **AI 분담 화면(13·14)은
> 백엔드 서버가 떠 있어야 동작한다.**

Windows PowerShell 기준 단계별 실행:

**① 백엔드 폴더로 이동**
```powershell
cd C:\Butler\backend
```

**② 가상환경 생성 (최초 1회만)**
```powershell
python -m venv .venv
```

**③ 가상환경 활성화 (셸을 새로 열 때마다)**
```powershell
.\.venv\Scripts\Activate.ps1
```
- 실행 정책 오류(`...because running scripts is disabled...`)가 나면 한 번만:
  `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` 후 다시 ③.
- 프롬프트 앞에 `(.venv)` 가 보이면 활성화 성공.

**④ 의존성 설치 (최초 1회 · requirements 변경 시)**
```powershell
pip install -r requirements.txt
```

**⑤ 환경변수 파일 준비 (최초 1회)**
```powershell
Copy-Item .env.example .env
```
- `.env` 를 열어 채운다:
  - `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` — Supabase **Project Settings → API** 의 service_role 키.
  - `ANTHROPIC_API_KEY` — Console 발급 키. **비워둬도 대표 시나리오(냉장고/노후/7년 → 70:30)는
    동작**(서버측 고정값). 그 외 임의 입력의 실시간 산출이 필요할 때만 채운다.
  - `FRONTEND_ORIGIN` — 기본 `http://localhost:5173` (Vite). 그대로 두면 됨.

> ⚠ **키 환경 분리(과금 주의):** `ANTHROPIC_API_KEY` 는 이 백엔드 실행 셸의 `.env` 에만 둔다.
> 같은 셸에서 Claude Code 를 함께 돌리면 그 키가 구독 인증보다 우선 적용돼 API 가 과금될 수 있다.
> 빌드/코딩용 터미널과 앱 실행용 터미널을 분리할 것.

**⑥ 서버 실행**
```powershell
uvicorn app.main:app --reload --port 8000
```
- `--reload` 는 코드 저장 시 자동 재시작(개발용). 종료는 `Ctrl + C`.
- 이 창은 켜둔 채로 두고, 프론트(`npm run dev`)는 **다른 터미널**에서 실행한다.

**⑦ 실행 확인**
- 헬스체크: 브라우저로 <http://localhost:8000/api/health> →
  `{"status":"ok", "anthropic_configured": …, "model": "claude-haiku-4-5-20251001"}`.
- AI 분담 엔드포인트(대표 시나리오, 키 없이 동작):
  ```powershell
  curl.exe -X POST http://localhost:8000/api/repair-allocation `
    -H "Content-Type: application/json" `
    --data-raw '{\"item\":\"201호 냉장고 수리\",\"cost\":165000,\"cause\":\"노후·자연마모\",\"usage_years\":7}'
  ```
  → `landlord_ratio:70 / tenant_ratio:30 / landlord_amount:115500 / tenant_amount:49500` + 근거 2종.
- API 문서(Swagger): <http://localhost:8000/docs> 에서 직접 호출해 볼 수도 있다.

## 4. 연결 확인
프론트 첫 화면(연결 점검)에서 다음을 확인:
- **Supabase**: 건물 3곳 + 집계 View(입주율·임대수익) 정상 표시
- **FastAPI**: `/api/health` ok

## 시드 데이터 요약 (와이어프레임 기준)
| 건물 | 입주율 | 세대 구성 | 임대수익 | 비고 |
| --- | --- | --- | --- | --- |
| 01호점(서울역) | 100% (30/30) | — | 1,850,000 | 이달 신규 1 / 만료 2 |
| 02호점(신촌)   | 85.7% (12/14) | — | 1,925,000 | 미납 2건 |
| **03호점(건대)** | **93.7% (15/16)** | 월세 14 / 전세 1 / 공실 1 | **8,500,000** | 총 보증금 1.6억 · **데모 핵심** |

데모 핵심 세입자 **김동락**(03호점 101호): 계약 2건 · 수납 4회차(대기/미납/완납) · 지출 4건(냉장고 수리비 = AI 분담) · 알림톡 7건.
