-- ============================================================
-- Butler PoC — 시드 데이터 (와이어프레임 실제 값 기준)
-- ⚠ 비파괴 · idempotent: truncate/delete 없음. 고정 UUID + on conflict do nothing +
--    채움 루프 존재가드로, 기존 데이터(예: Flow A로 등록한 건물)를 지우지 않고
--    데모 데이터만 덧입힌다. 여러 번 실행해도 중복 INSERT 되지 않는다.
--    → 완전 초기화가 필요하면 schema.sql(전체 drop)을 먼저 실행한 뒤 이 파일을 실행한다.
--
-- 데모 핵심 건물 = Butler 03호점(건대). 모든 상세 탭이 이 건물을 사용.
-- 집계 수치는 building_stats / unpaid_stats View가 (건물별로) 계산하므로,
-- 기존 실데이터 건물과 공존해도 데모 건물 수치는 와이어프레임 값과 일치한다.
--   · 03호점: 입주율 93.7%(15/16), 월세 14 / 전세 1 / 공실 1,
--             총 보증금 1.6억, 임대수익 8,500,000, 이달 신규 1 / 만료 0
--   · 02호점: 85.7%(12/14), 미납 2건
--   · 01호점: 100%(30/30), 이달 신규 1 / 만료 2
-- ============================================================

-- ------------------------------------------------------------
-- 건물 3곳 (고정 UUID로 하위 데이터 연결)
-- ------------------------------------------------------------
insert into buildings (id, business_reg_no, name, address, unit_count, building_type, account_info, is_favorite) values
  ('11111111-1111-1111-1111-111111111111', '101-81-00001', 'Butler 01호점(서울역)', '서울 중구 한강대로 405',  30, '오피스텔',   '국민 123-45-678901', false),
  ('22222222-2222-2222-2222-222222222222', '201-81-00002', 'Butler 02호점(신촌)',   '서울 서대문구 신촌로 90', 14, '다세대주택', '신한 110-222-333444', false),
  ('33333333-3333-3333-3333-333333333333', '301-81-00003', 'Butler 03호점(건대)',   '서울 광진구 능동로 120',  16, '다세대주택', '우리 1002-555-666777', true)
on conflict (id) do nothing;

-- ============================================================
-- [데모 핵심] Butler 03호점(건대) — 김동락 + 상세 데이터
-- ============================================================

-- 세입자 김동락 (개인)
insert into tenants (id, building_id, tenant_type, name, phone, memo) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '33333333-3333-3333-3333-333333333333',
   '개인', '김동락', '010-1234-5678',
   '반려견 키우면서 월세·관리비를 조금 밀리는 경향 😤')
on conflict (id) do nothing;

-- 김동락 계약 2건 ("다른 계약서 총 2건"): 현재 계약중 101호 + 과거 종료 계약
-- 0001: 현재 계약중 (세입자 등록 위저드 결과 — 납부·증빙 신규 필드 포함).
--       월세 550,000·관리비 94,500은 '부가세 포함(최종 청구)' 금액이므로 VAT 플래그는 false.
--       (PRD 3장: 플래그 true면 ×1.1 가산 → 이미 포함값에 켜면 이중가산되어 회차 금액과 불일치)
--       12일 후불, 첫 납부 2021-01-12, 증빙=현금영수증(개인소득공제용).
--       0002: 과거 종료 계약 — 신규 필드 null.
insert into contracts (id, tenant_id, building_id, unit_no, contract_start, contract_end,
                       deposit, monthly_rent, maintenance_fee, lease_type,
                       rent_vat, maintenance_vat,
                       payment_day, payment_timing, first_payment_date, depositor_name,
                       proof_kind, proof_phone,
                       status, is_primary) values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
   '101호', '2020-12-12', '2022-12-11',
   10000000, 550000, 94500, '월세',
   false, false,
   12, '후불', '2021-01-12', '김동락',
   '현금영수증(개인소득공제용)', '010-1234-5678',
   '계약중', true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0002',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
   '101호', '2018-12-12', '2020-12-11',
   8000000, 500000, 80000, '월세',
   false, false,
   12, '후불', '2019-01-12', '김동락',
   '해당없음', null,
   '종료', false)
on conflict (id) do nothing;

-- 김동락 수납 회차 (101호, 회차 청구 650,000, 입금 예정일 12일, 월세 후불)
-- ⚠ 이 4건은 '수납 탭 와이어프레임'에 맞춘 데모 큐레이션(최근 회차 9 대기/8 미납/7·6 완납)이다.
--    PRD 3장 §"payments 회차 자동 생성"(첫 납부일~종료일 매월 일괄 insert)은
--    Flow E '등록 시점'의 결정적 계산(composable/RPC) 책임이며, 이 데모 계약은 그 산출물이 아니다.
--    회차 청구액 650,000은 와이어프레임 표기값(월세 550,000+관리비 94,500=644,500의 데모 반올림).
insert into payments (contract_id, round_no, amount, due_date, status, paid_date, is_postpaid) values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 9, 650000, '2022-12-12', '대기', null,         true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 8, 650000, '2022-11-12', '미납', null,         true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 7, 650000, '2022-10-12', '완납', '2022-10-12', true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 6, 650000, '2022-09-12', '완납', '2022-09-11', true)
on conflict (contract_id, round_no) do nothing;

-- 03호점 지출 (이번 달 합계 1,221,000 / 4건). 냉장고 수리비만 is_repair=true → AI 분담 진입.
insert into expenses (id, building_id, expense_date, title, amount, proof_type, is_repair) values
  ('e0000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', '2022-10-05', '에어컨 청소',          99000, '세금계산서',       false),
  ('e0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', '2022-10-10', '201호 냉장고 수리비',  165000, null,             true),
  ('e0000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', '2022-10-18', '옥상 방수공사',        880000, '현금영수증(개인)', false),
  ('e0000000-0000-0000-0000-000000000004', '33333333-3333-3333-3333-333333333333', '2022-10-25', '도어록 교환',           77000, '간이영수증',       false)
on conflict (id) do nothing;

-- 김동락 알림톡 히스토리 (모두 mock_sent — 종류별 태그/타임라인)
insert into notifications (id, contract_id, type, title, sent_at, status) values
  ('d0000000-0000-0000-0000-000000000001', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '종료', '계약종료 알림톡 발송',   '2022-12-11 10:00+09', 'mock_sent'),
  ('d0000000-0000-0000-0000-000000000002', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송', '2022-11-11 18:00+09', 'mock_sent'),
  ('d0000000-0000-0000-0000-000000000003', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '미납', '미납 7일차 알림톡 발송', '2022-09-18 13:00+09', 'mock_sent'),
  ('d0000000-0000-0000-0000-000000000004', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송', '2022-09-11 18:00+09', 'mock_sent'),
  ('d0000000-0000-0000-0000-000000000005', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '연장', '연장 여부 알림톡 발송',   '2022-09-11 10:00+09', 'mock_sent'),
  ('d0000000-0000-0000-0000-000000000006', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송', '2022-08-11 18:00+09', 'mock_sent'),
  ('d0000000-0000-0000-0000-000000000007', 'cccccccc-cccc-cccc-cccc-cccccccc0001', '미납', '미납 2일차 알림톡 발송', '2022-06-14 13:00+09', 'mock_sent')
on conflict (id) do nothing;

-- ============================================================
-- 집계 수치를 와이어프레임과 맞추기 위한 채움(filler) 계약
-- 상세 탭에는 노출되지 않으나 building_stats / unpaid_stats View가
-- 입주율·세대구성·보증금·임대수익·이달 신규/만료를 정확히 계산하도록 한다.
-- ============================================================

-- 03호점: 14 월세 + 1 전세 = 15 입주(+공실 1). 김동락 외 13 월세 + 1 전세 추가.
-- 임대수익 합 = 김동락 550,000 + 채움 7,950,000 = 8,500,000.
-- 총 보증금 = 김동락 10,000,000 + 채움(13×10,000,000 + 전세 20,000,000) = 160,000,000(1.6억).
-- 이달 신규 1 = 채움 1건의 contract_start를 이번 달로 설정. 이달 만료 0.
-- (idempotent) 채움 대표 호실(115호)이 이미 있으면 루프 생략.
do $$
declare t_id uuid; i int;
begin
  if exists (select 1 from contracts
             where building_id = '33333333-3333-3333-3333-333333333333' and unit_no = '115호') then
    return;
  end if;
  for i in 1..14 loop
    insert into tenants (building_id, name)
      values ('33333333-3333-3333-3333-333333333333', '03호점 세입자' || (i + 1))
      returning id into t_id;
    insert into contracts (tenant_id, building_id, unit_no, contract_start, contract_end,
                           deposit, monthly_rent, maintenance_fee, lease_type,
                           payment_day, payment_timing, first_payment_date, depositor_name, proof_kind,
                           status, is_primary)
    values (
      t_id, '33333333-3333-3333-3333-333333333333', (101 + i) || '호',
      case when i = 1 then date_trunc('month', current_date)::date else date '2021-03-01' end,  -- 신규 1건
      date '2026-12-31',                                                                        -- 이달 만료 0
      case when i = 14 then 20000000 else 10000000 end,
      case when i = 14 then null when i = 13 then 750000 else 600000 end,                       -- 전세=월세 null / 월세 합 7,950,000
      case when i = 14 then 0 else 50000 end,
      case when i = 14 then '전세' else '월세' end,
      12,
      '후불',
      case when i = 1 then (date_trunc('month', current_date) + interval '1 month 11 days')::date
           else date '2021-04-12' end,
      '03호점 세입자' || (i + 1),
      '해당없음',
      '계약중', true);
  end loop;
end $$;

-- 01호점: 30 입주(100%, 30/30). 월세 3건(합 1,850,000) + 전세 27건. 이달 신규 1 / 만료 2.
-- (idempotent) 채움 대표 호실(130호)이 이미 있으면 루프 생략.
do $$
declare t_id uuid; i int;
begin
  if exists (select 1 from contracts
             where building_id = '11111111-1111-1111-1111-111111111111' and unit_no = '130호') then
    return;
  end if;
  for i in 1..30 loop
    insert into tenants (building_id, name)
      values ('11111111-1111-1111-1111-111111111111', '01호점 세입자' || i)
      returning id into t_id;
    insert into contracts (tenant_id, building_id, unit_no, contract_start, contract_end,
                           deposit, monthly_rent, maintenance_fee, lease_type,
                           payment_day, payment_timing, first_payment_date, depositor_name, proof_kind,
                           status, is_primary)
    values (
      t_id, '11111111-1111-1111-1111-111111111111', (100 + i) || '호',
      case when i = 1 then date_trunc('month', current_date)::date else date '2021-06-01' end,           -- 신규 1
      case when i in (2, 3) then (date_trunc('month', current_date) + interval '20 day')::date
           else date '2026-12-31' end,                                                                   -- 만료 2
      case when i <= 3 then 10000000 else 80000000 end,
      case when i = 1 then 600000 when i = 2 then 600000 when i = 3 then 650000 else null end,           -- 전세=월세 null / 월세 합 1,850,000
      case when i <= 3 then 50000 else 0 end,
      case when i <= 3 then '월세' else '전세' end,
      12,
      '후불',
      case when i = 1 then (date_trunc('month', current_date) + interval '1 month 11 days')::date
           else date '2021-07-12' end,
      '01호점 세입자' || i,
      '해당없음',
      '계약중', true);
  end loop;
end $$;

-- 02호점: 14세대 중 12 입주(85.7%, 12/14), 공실 2. 월세 3건(합 1,925,000) + 전세 9건. 미납 2건.
-- (idempotent) 채움 대표 호실(112호)이 이미 있으면 루프 생략.
do $$
declare t_id uuid; c_id uuid; i int;
begin
  if exists (select 1 from contracts
             where building_id = '22222222-2222-2222-2222-222222222222' and unit_no = '112호') then
    return;
  end if;
  for i in 1..12 loop
    insert into tenants (building_id, name)
      values ('22222222-2222-2222-2222-222222222222', '02호점 세입자' || i)
      returning id into t_id;
    insert into contracts (tenant_id, building_id, unit_no, contract_start, contract_end,
                           deposit, monthly_rent, maintenance_fee, lease_type,
                           payment_day, payment_timing, first_payment_date, depositor_name, proof_kind,
                           status, is_primary)
    values (
      t_id, '22222222-2222-2222-2222-222222222222', (100 + i) || '호',
      date '2021-09-01', date '2026-12-31',
      case when i <= 3 then 10000000 else 60000000 end,
      case when i = 1 then 650000 when i = 2 then 625000 when i = 3 then 650000 else null end,  -- 전세=월세 null / 월세 합 1,925,000
      case when i <= 3 then 50000 else 0 end,
      case when i <= 3 then '월세' else '전세' end,
      12,
      '후불',
      date '2021-10-12',
      '02호점 세입자' || i,
      '해당없음',
      '계약중', true)
    returning id into c_id;
    -- 미납 2건 (월세 계약 2건에 미납 회차 부여)
    if i <= 2 then
      insert into payments (contract_id, round_no, amount, due_date, status, is_postpaid)
        values (c_id, 5, 650000, date '2022-11-12', '미납', false);
    end if;
  end loop;
end $$;
