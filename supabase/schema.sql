-- ============================================================
-- Butler PoC — 데이터 모델 (PRD 3장 기준)
-- Supabase SQL Editor에서 schema.sql → seed.sql 순서로 실행한다.
-- ⚠ PoC 전용: 단일 임대인 계정 기준이라 RLS는 비활성(전체 허용)이다.
--    실서비스 전환 시 RLS 정책을 반드시 추가할 것.
--
-- ⚠⚠ 이 파일은 "처음부터 새로 까는(fresh setup)" 용도다. 아래 drop 블록이
--    buildings 포함 모든 테이블을 삭제하므로, 이미 Flow A로 등록해 둔 건물 등
--    기존 데이터가 있으면 전부 사라진다.
--    → 기존 데이터를 보존하며 세입자 등록 신규 필드만 추가하려면 이 파일 대신
--      supabase/migrate_tenant_fields.sql (비파괴 ALTER 마이그레이션)을 실행할 것.
-- ============================================================

-- 재실행 가능하도록 기존 객체 제거 (의존 순서 역순) — ⚠ 데이터 전체 삭제됨
drop view if exists unpaid_stats cascade;
drop view if exists building_stats cascade;
drop table if exists notifications cascade;
drop table if exists repair_allocations cascade;
drop table if exists expenses cascade;
drop table if exists payments cascade;
drop table if exists contracts cascade;
drop table if exists contractors cascade;
drop table if exists tenants cascade;
drop table if exists buildings cascade;

-- ------------------------------------------------------------
-- 건물
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- 세입자 (개인/사업자 공통 엔티티)
-- ------------------------------------------------------------
create table tenants (
  id            uuid primary key default gen_random_uuid(),
  building_id   uuid references buildings(id) on delete cascade,
  tenant_type   text not null default '개인'
                  check (tenant_type in ('개인','사업자')),   -- (Step1 토글)
  name          text not null,                  -- 개인=대표 계약자명 / 사업자=사업자명
  phone         text,                           -- 대표 연락처
  manager_name  text,                           -- (사업자) 담당자명 — 선택
  memo          text,                           -- "반려견 키우면서 월세·관리비 밀림"
  created_at    timestamptz default now(),
  -- 사업자는 휴대폰 필수 (PRD E-2 §510). 개인은 선택.
  constraint tenants_biz_phone_chk check (tenant_type <> '사업자' or phone is not null)
);

-- ------------------------------------------------------------
-- 공동계약자 (개인 경로 '계약자1' + 추가 버튼) — PoC 선택
-- 데모는 계약자 1명 → 단일 행. 과하면 tenants.name/phone로 단일 처리.
-- ------------------------------------------------------------
create table contractors (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references tenants(id) on delete cascade,
  name        text not null,
  phone       text,
  is_primary  boolean default true
);

-- ------------------------------------------------------------
-- 계약 (세입자당 다중 계약서 지원 + 세입자 등록 위저드 결과 저장)
-- ------------------------------------------------------------
create table contracts (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid references tenants(id) on delete cascade,
  building_id     uuid references buildings(id) on delete cascade,
  unit_no         text not null,              -- "101호" / "107동 1105호"
  contract_start  date not null,              -- 시작일 (캘린더 선택)
  contract_end    date not null,              -- 종료일 (시작일 +1년 자동, 수정 가능)
  lease_type      text not null
                    check (lease_type in ('월세','전세')),   -- (Step2 계약형태 토글)
  -- 금액 (Step2). 월세 모드: 월세 필수·보증금 선택 / 전세 모드: 보증금 필수·월세 null
  deposit         bigint,                     -- 보증금 (전세 필수, 월세 선택)
  monthly_rent    bigint,                     -- 월세 (전세는 null)
  maintenance_fee bigint default 0,           -- 관리비
  etc_fee1        bigint default 0,           -- 기타비용1
  etc_fee2        bigint default 0,           -- 기타비용2
  -- 항목별 부가세 여부. ⚠ 위 금액(monthly_rent 등)은 '부가세 별도(net)' 기준값이며,
  -- 플래그가 true인 항목만 매월 총액 합산 시 ×1.1을 적용한다(PRD 3장 파생계산).
  -- 저장값을 '부가세 포함'으로 넣을 거면 플래그는 false여야 한다(이중 가산 방지).
  rent_vat        boolean default false,
  maintenance_vat boolean default false,
  etc1_vat        boolean default false,
  etc2_vat        boolean default false,
  -- 납부 정보 (Step3)
  payment_day     int  check (payment_day between 1 and 31),  -- 납부일 1~31 (월별 말일 보정)
  payment_timing  text check (payment_timing in ('선불','후불')),
  first_payment_date date,                    -- 첫 납부일 (선불=당월 / 후불=익월, 자동 계산)
  depositor_name  text,                       -- 입금자명 (기본=대표 계약자명)
  -- 증빙 발급 설정 (Step3 증빙 관리 — expenses.proof_type 와 별개 개념)
  proof_kind      text check (proof_kind in
                    ('해당없음','현금영수증(개인소득공제용)','현금영수증(사업자증빙용)','세금계산서','계산서')),
  proof_phone     text,                       -- 현금영수증(개인) 휴대폰
  proof_biz_reg_no text,                      -- 현금영수증(사업자) 사업자등록번호
  proof_email     text,                       -- 세금계산서/계산서 이메일
  proof_biz_license_url text,                 -- 세금계산서/계산서 사업자등록증 (Storage)
  -- 업로드
  contract_file_url text,                     -- 임대차 계약서 (Storage)
  status          text not null
                    check (status in ('계약중','만료','종료')),
  is_primary      boolean default true,       -- 대표 계약 여부
  created_at      timestamptz default now(),
  -- 조건부 필수 (PRD 3장 · E-3 §539): 월세=월세 필수(보증금 선택) / 전세=보증금 필수·월세 없음
  constraint contracts_amount_by_lease_chk check (
    (lease_type = '월세' and monthly_rent is not null)
    or (lease_type = '전세' and deposit is not null and monthly_rent is null)
  ),
  -- Flow E 등록 계약은 납부 정보가 필수다. 기존 과거 계약도 시드에서는 값을 채운다.
  constraint contracts_payment_required_chk check (
    payment_day is not null
    and payment_timing is not null
    and first_payment_date is not null
    and depositor_name is not null
    and btrim(depositor_name) <> ''
  ),
  -- 증빙 종류별 하위 필드 필수 (PRD E-3 §527~529).
  constraint contracts_proof_subfield_chk check (
    proof_kind is null
    or proof_kind = '해당없음'
    or (proof_kind = '현금영수증(개인소득공제용)' and proof_phone     is not null)
    or (proof_kind = '현금영수증(사업자증빙용)' and proof_biz_reg_no is not null)
    or (proof_kind in ('세금계산서','계산서')
        and proof_email is not null
        and proof_biz_license_url is not null)
  )
);

-- ------------------------------------------------------------
-- 수납 (회차별)
-- ------------------------------------------------------------
create table payments (
  id          uuid primary key default gen_random_uuid(),
  contract_id uuid references contracts(id) on delete cascade,
  round_no    int not null,                   -- 회차 (6,7,8,9 ...)
  amount      bigint not null,                -- 650,000
  due_date    date not null,                  -- 입금 예정일
  status      text not null
                check (status in ('대기','미납','완납')),
  paid_date   date,                           -- 완납 시점
  is_postpaid boolean default false,          -- 후불 표시
  unique (contract_id, round_no)              -- 계약별 회차 중복 방지(+ 시드 비파괴 idempotent 키)
);

-- ------------------------------------------------------------
-- 지출
-- ------------------------------------------------------------
create table expenses (
  id           uuid primary key default gen_random_uuid(),
  building_id  uuid references buildings(id) on delete cascade,
  expense_date date not null,                 -- 22.10.10
  title        text not null,                 -- "201호 냉장고 수리비"
  amount       bigint not null,               -- 165,000
  proof_type   text check (proof_type in ('세금계산서','현금영수증(개인)','간이영수증')),
  is_repair    boolean default false          -- true면 AI 분담 진입 가능 항목
);

-- ------------------------------------------------------------
-- AI 수선비 분담 결과
-- ------------------------------------------------------------
create table repair_allocations (
  id              uuid primary key default gen_random_uuid(),
  expense_id      uuid references expenses(id) on delete cascade,
  item            text not null,              -- "201호 냉장고 수리"
  cost            bigint not null,            -- 165,000
  cause           text not null
                    check (cause in ('노후·자연마모','사용 부주의')),
  usage_years     int,                        -- 설치 후 7년
  landlord_ratio  int not null,               -- 70
  tenant_ratio    int not null,               -- 30
  landlord_amount bigint not null,            -- 115,500
  tenant_amount   bigint not null,            -- 49,500
  basis_lh        text,                       -- LH 가이드라인 근거 문장
  basis_court     text,                       -- 대법원 판례 근거 문장
  created_at      timestamptz default now()
);

-- ------------------------------------------------------------
-- 알림톡 (발송은 mock — sent_at/status로 시뮬레이션)
-- ------------------------------------------------------------
create table notifications (
  id           uuid primary key default gen_random_uuid(),
  contract_id  uuid references contracts(id) on delete cascade,
  type         text not null
                 check (type in ('납부','미납','연장','종료')),
  title        text not null,                 -- "납부 1일전 알림톡 발송"
  body         text,                          -- 템플릿 치환된 메시지 본문
  pdf_url      text,                          -- Supabase Storage PDF 경로
  scheduled_at timestamptz,                   -- 발송 예정 시점
  sent_at      timestamptz,                   -- (mock) 발송 처리 시점
  status       text default 'mock_sent'
                 check (status in ('scheduled','mock_sent'))
);

-- 조회 성능용 인덱스
create index idx_tenants_building     on tenants(building_id);
create index idx_contractors_tenant   on contractors(tenant_id);
create index idx_contracts_building on contracts(building_id);
create index idx_contracts_tenant   on contracts(tenant_id);
create index idx_payments_contract  on payments(contract_id);
create index idx_expenses_building  on expenses(building_id);
create index idx_notifications_contract on notifications(contract_id);

-- ============================================================
-- 집계 지표 (PRD 3장: 컬럼이 아니라 View로 계산)
-- ============================================================

-- 건물별 집계: 입주율 · 세대구성(월세/전세/공실) · 보증금 · 임대수익 · 이달 신규/만료
create view building_stats as
select
  b.id                                                                              as building_id,
  b.name,
  b.unit_count,
  count(distinct c.unit_no) filter (where c.status = '계약중')                      as occupied_units,        -- 호실 기준(같은 호실 활성 계약 중복 방어)
  trunc(
    count(distinct c.unit_no) filter (where c.status = '계약중')::numeric
      / nullif(b.unit_count, 0) * 100, 1)                                           as occupancy_rate,        -- 입주율 % (와이어프레임 표기에 맞춰 1자리 절사: 15/16=93.7)
  count(distinct c.unit_no) filter (where c.status = '계약중' and c.lease_type = '월세') as wolse_count,       -- 월세 세대
  count(distinct c.unit_no) filter (where c.status = '계약중' and c.lease_type = '전세') as jeonse_count,      -- 전세 세대
  b.unit_count - count(distinct c.unit_no) filter (where c.status = '계약중')        as vacant_count,          -- 공실
  coalesce(sum(c.deposit) filter (where c.status = '계약중'), 0)                    as deposit_total,         -- 총 보증금
  coalesce(sum(c.monthly_rent) filter
    (where c.status = '계약중' and c.lease_type = '월세'), 0)                       as rental_income,         -- 임대수익(월세 합)
  count(*) filter (where c.status = '계약중'
    and date_trunc('month', c.contract_start) = date_trunc('month', current_date))  as new_this_month,        -- 이달 신규
  count(*) filter (where c.status = '계약중'
    and date_trunc('month', c.contract_end)   = date_trunc('month', current_date))  as expiring_this_month    -- 이달 만료
from buildings b
left join contracts c on c.building_id = b.id
group by b.id, b.name, b.unit_count;

-- 건물별 미납 집계: 건수 · 금액
create view unpaid_stats as
select
  c.building_id,
  count(*)                       as unpaid_count,
  coalesce(sum(p.amount), 0)     as unpaid_amount
from payments p
join contracts c on c.id = p.contract_id
where p.status = '미납'
group by c.building_id;

-- ============================================================
-- 권한 (PoC 전용 — Supabase anon/authenticated 직결 CRUD 허용)
-- ⚠ 데모 단순화를 위해 RLS 미사용. 실서비스에서는 RLS 정책으로 대체할 것.
-- ============================================================
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;
