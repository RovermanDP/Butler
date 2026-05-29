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
2. **SQL Editor** 에서 순서대로 실행:
   - `supabase/schema.sql` (테이블 + 집계 View)
   - `supabase/seed.sql` (와이어프레임 시드 데이터)
3. **Project Settings → API** 에서 키 복사:
   - `URL`, `anon public` → 프론트엔드
   - `service_role` → 백엔드

> ⚠ PoC 전용: 단일 임대인 기준이라 RLS 미사용(전체 허용). 실서비스 전환 시 RLS 정책 추가.

## 2. 프론트엔드 (Vue + Vite)
```bash
cd frontend
cp .env.example .env.local   # VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 채우기
npm install
npm run dev                  # http://localhost:5173
```

## 3. 백엔드 (FastAPI)
```bash
cd backend
python -m venv .venv
.venv\Scripts\activate       # (Windows PowerShell)
pip install -r requirements.txt
cp .env.example .env         # SUPABASE_* / (Flow C 단계에서 ANTHROPIC_API_KEY) 채우기
uvicorn app.main:app --reload --port 8000   # http://localhost:8000/api/health
```

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
