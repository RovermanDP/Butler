-- ============================================================
-- Butler PoC — 세입자 등록(Flow E) 신규 필드 마이그레이션 (비파괴)
-- ============================================================
-- 용도: 이미 데이터가 들어있는 기존 DB(예: Flow A로 등록한 건물)를
--       삭제 없이 PRD 3장 스키마로 업그레이드한다.
--       → 새로 까는 경우엔 이 파일이 아니라 schema.sql 을 쓴다.
--
-- 특징:
--  · drop / truncate 없음 — 기존 buildings·tenants·contracts 등 데이터 보존.
--  · ADD COLUMN IF NOT EXISTS + 제약은 DO 블록(duplicate 무시)으로 재실행 안전(idempotent).
--  · CHECK 제약은 추가 시점에 기존 행을 즉시 검증한다. PoC 데이터(시드/Flow A 건물)는
--    모두 허용값이라 통과한다. 임의의 잘못된 기존 값이 있다면 그 값을 먼저 교정할 것.
-- 실행: Supabase SQL Editor에서 이 파일 1개만 실행.
-- ============================================================

-- ── tenants: 개인/사업자 구분·연락처·담당자 ──────────────────
alter table tenants add column if not exists tenant_type  text not null default '개인';
alter table tenants add column if not exists phone        text;
alter table tenants add column if not exists manager_name text;

-- ── contractors: 공동계약자 (없으면 생성) ────────────────────
create table if not exists contractors (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid references tenants(id) on delete cascade,
  name        text not null,
  phone       text,
  is_primary  boolean default true
);
create index if not exists idx_contractors_tenant on contractors(tenant_id);

-- ── contracts: 금액 컬럼 nullable화 + 신규 필드 ──────────────
-- 월세=월세 필수·보증금 선택 / 전세=보증금 필수·월세 null 을 허용하도록 NOT NULL 해제.
alter table contracts alter column deposit         drop not null;
alter table contracts alter column monthly_rent    drop not null;
alter table contracts alter column maintenance_fee drop not null;
alter table contracts alter column maintenance_fee set default 0;

alter table contracts add column if not exists etc_fee1              bigint default 0;
alter table contracts add column if not exists etc_fee2              bigint default 0;
alter table contracts add column if not exists rent_vat              boolean default false;
alter table contracts add column if not exists maintenance_vat       boolean default false;
alter table contracts add column if not exists etc1_vat              boolean default false;
alter table contracts add column if not exists etc2_vat              boolean default false;
alter table contracts add column if not exists payment_day           int;
alter table contracts add column if not exists payment_timing        text;
alter table contracts add column if not exists first_payment_date    date;
alter table contracts add column if not exists depositor_name        text;
alter table contracts add column if not exists proof_kind            text;
alter table contracts add column if not exists proof_phone           text;
alter table contracts add column if not exists proof_biz_reg_no      text;
alter table contracts add column if not exists proof_email           text;
alter table contracts add column if not exists proof_biz_license_url text;
alter table contracts add column if not exists contract_file_url     text;

-- ── enum/범위 CHECK 제약 (Supabase 직결 CRUD 방어) ──────────
-- ADD CONSTRAINT 에는 IF NOT EXISTS 가 없어 DO 블록으로 중복을 무시한다.
do $$ begin
  alter table tenants add constraint tenants_tenant_type_chk
    check (tenant_type in ('개인','사업자'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table contracts add constraint contracts_lease_type_chk
    check (lease_type in ('월세','전세'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table contracts add constraint contracts_status_chk
    check (status in ('계약중','만료','종료'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table contracts add constraint contracts_payment_day_chk
    check (payment_day between 1 and 31);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table contracts add constraint contracts_payment_timing_chk
    check (payment_timing in ('선불','후불'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table contracts add constraint contracts_proof_kind_chk
    check (proof_kind in
      ('해당없음','현금영수증(개인소득공제용)','현금영수증(사업자증빙용)','세금계산서','계산서'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table payments add constraint payments_status_chk
    check (status in ('대기','미납','완납'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table expenses add constraint expenses_proof_type_chk
    check (proof_type in ('세금계산서','현금영수증(개인)','간이영수증'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table repair_allocations add constraint repair_allocations_cause_chk
    check (cause in ('노후·자연마모','사용 부주의'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table notifications add constraint notifications_type_chk
    check (type in ('납부','미납','연장','종료'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table notifications add constraint notifications_status_chk
    check (status in ('scheduled','mock_sent'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table tenants add constraint tenants_biz_phone_chk
    check (tenant_type <> '사업자' or phone is not null);
exception when duplicate_object then null; end $$;

-- payments: 계약별 회차 유니크(중복 방지 + 비파괴 seed의 on conflict 키)
do $$ begin
  alter table payments add constraint payments_contract_round_uq
    unique (contract_id, round_no);
exception when duplicate_object or duplicate_table then null; end $$;

-- ── 조건부 필수 (PRD E-3): 기존 레거시 행에서 실패하지 않도록 NOT VALID ──
-- NOT VALID = 이미 들어있는 행은 검사하지 않고, 이후 INSERT/UPDATE만 강제한다.
-- (기존 데모 데이터에 '전세 monthly_rent=0' 같은 비정합 행이 있어도 마이그레이션이 통과)
-- 레거시 행까지 정합화한 뒤 강제하려면: alter table contracts validate constraint <이름>;
do $$ begin
  alter table contracts add constraint contracts_amount_by_lease_chk check (
    (lease_type = '월세' and monthly_rent is not null)
    or (lease_type = '전세' and deposit is not null and monthly_rent is null)
  ) not valid;
exception when duplicate_object then null; end $$;

do $$ begin
  alter table contracts add constraint contracts_payment_required_chk check (
    payment_day is not null
    and payment_timing is not null
    and first_payment_date is not null
    and depositor_name is not null
    and btrim(depositor_name) <> ''
  ) not valid;
exception when duplicate_object then null; end $$;

-- 이전 버전에서 더 느슨한 proof_subfield 제약이 이미 들어갔을 수 있어 교체한다.
alter table contracts drop constraint if exists contracts_proof_subfield_chk;

do $$ begin
  alter table contracts add constraint contracts_proof_subfield_chk check (
    proof_kind is null
    or proof_kind = '해당없음'
    or (proof_kind = '현금영수증(개인소득공제용)' and proof_phone     is not null)
    or (proof_kind = '현금영수증(사업자증빙용)' and proof_biz_reg_no is not null)
    or (proof_kind in ('세금계산서','계산서')
        and proof_email is not null
        and proof_biz_license_url is not null)
  ) not valid;
exception when duplicate_object then null; end $$;

-- ── 신규 테이블 권한 (PoC: anon/authenticated 직결 CRUD) ─────
grant all on contractors to anon, authenticated;
