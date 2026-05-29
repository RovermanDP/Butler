-- ============================================================
-- Butler PoC — 시드 데이터 (와이어프레임 실제 값 기준)
-- schema.sql 실행 후 이 파일을 실행한다. (재실행 가능)
--
-- 데모 핵심 건물 = Butler 03호점(건대). 모든 상세 탭이 이 건물을 사용.
-- 집계 수치는 building_stats / unpaid_stats View가 계산하며,
-- 아래 시드가 와이어프레임 값과 일치하도록 구성돼 있다.
--   · 03호점: 입주율 93.7%(15/16), 월세 14 / 전세 1 / 공실 1,
--             총 보증금 1.6억, 임대수익 8,500,000, 이달 신규 1 / 만료 0
--   · 02호점: 85.7%(12/14), 미납 2건
--   · 01호점: 100%(30/30), 이달 신규 1 / 만료 2
-- ============================================================

-- 재실행 시 초기화 (FK cascade로 하위 데이터 함께 삭제)
truncate table notifications, repair_allocations, expenses,
               payments, contracts, tenants, buildings restart identity cascade;

-- ------------------------------------------------------------
-- 건물 3곳 (고정 UUID로 하위 데이터 연결)
-- ------------------------------------------------------------
insert into buildings (id, business_reg_no, name, address, unit_count, building_type, account_info, is_favorite) values
  ('11111111-1111-1111-1111-111111111111', '101-81-00001', 'Butler 01호점(서울역)', '서울 중구 한강대로 405',  30, '오피스텔',   '국민 123-45-678901', false),
  ('22222222-2222-2222-2222-222222222222', '201-81-00002', 'Butler 02호점(신촌)',   '서울 서대문구 신촌로 90', 14, '다세대주택', '신한 110-222-333444', false),
  ('33333333-3333-3333-3333-333333333333', '301-81-00003', 'Butler 03호점(건대)',   '서울 광진구 능동로 120',  16, '다세대주택', '우리 1002-555-666777', true);

-- ============================================================
-- [데모 핵심] Butler 03호점(건대) — 김동락 + 상세 데이터
-- ============================================================

-- 세입자 김동락
insert into tenants (id, building_id, name, memo) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '33333333-3333-3333-3333-333333333333',
   '김동락',
   '반려견 키우면서 월세·관리비를 조금 밀리는 경향 😤');

-- 김동락 계약 2건 ("다른 계약서 총 2건"): 현재 계약중 101호 + 과거 종료 계약
insert into contracts (id, tenant_id, building_id, unit_no, contract_start, contract_end, deposit, monthly_rent, maintenance_fee, lease_type, status, is_primary) values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
   '101호', '2020-12-12', '2022-12-11', 10000000, 550000, 94500, '월세', '계약중', true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0002',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
   '101호', '2018-12-12', '2020-12-11', 8000000, 500000, 80000, '월세', '종료', false);

-- 김동락 수납 회차 (101호, 매월 650,000, 입금 예정일 12일, 월세 후불)
-- 9회차 대기 / 8회차 미납 / 7·6회차 완납
insert into payments (contract_id, round_no, amount, due_date, status, paid_date, is_postpaid) values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 9, 650000, '2022-12-12', '대기', null,         true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 8, 650000, '2022-11-12', '미납', null,         true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 7, 650000, '2022-10-12', '완납', '2022-10-12', true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', 6, 650000, '2022-09-12', '완납', '2022-09-11', true);

-- 03호점 지출 (이번 달 합계 1,221,000 / 4건). 냉장고 수리비만 is_repair=true → AI 분담 진입.
insert into expenses (building_id, expense_date, title, amount, proof_type, is_repair) values
  ('33333333-3333-3333-3333-333333333333', '2022-10-05', '에어컨 청소',          99000, '세금계산서',       false),
  ('33333333-3333-3333-3333-333333333333', '2022-10-10', '201호 냉장고 수리비',  165000, null,             true),
  ('33333333-3333-3333-3333-333333333333', '2022-10-18', '옥상 방수공사',        880000, '현금영수증(개인)', false),
  ('33333333-3333-3333-3333-333333333333', '2022-10-25', '도어록 교환',           77000, '간이영수증',       false);

-- 김동락 알림톡 히스토리 (모두 mock_sent — 종류별 태그/타임라인)
insert into notifications (contract_id, type, title, sent_at, status) values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '종료', '계약종료 알림톡 발송',   '2022-12-11 10:00+09', 'mock_sent'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송', '2022-11-11 18:00+09', 'mock_sent'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '미납', '미납 7일차 알림톡 발송', '2022-09-18 13:00+09', 'mock_sent'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송', '2022-09-11 18:00+09', 'mock_sent'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '연장', '연장 여부 알림톡 발송',   '2022-09-11 10:00+09', 'mock_sent'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송', '2022-08-11 18:00+09', 'mock_sent'),
  ('cccccccc-cccc-cccc-cccc-cccccccc0001', '미납', '미납 2일차 알림톡 발송', '2022-06-14 13:00+09', 'mock_sent');

-- ============================================================
-- 집계 수치를 와이어프레임과 맞추기 위한 채움(filler) 계약
-- 상세 탭에는 노출되지 않으나 building_stats / unpaid_stats View가
-- 입주율·세대구성·보증금·임대수익·이달 신규/만료를 정확히 계산하도록 한다.
-- ============================================================

-- 03호점: 14 월세 + 1 전세 = 15 입주(+공실 1). 김동락 외 13 월세 + 1 전세 추가.
-- 임대수익 합 = 김동락 550,000 + 채움 7,950,000 = 8,500,000.
-- 총 보증금 = 김동락 10,000,000 + 채움(13×10,000,000 + 전세 20,000,000) = 160,000,000(1.6억).
-- 이달 신규 1 = 채움 1건의 contract_start를 이번 달로 설정. 이달 만료 0.
do $$
declare t_id uuid; i int;
begin
  for i in 1..14 loop
    insert into tenants (building_id, name)
      values ('33333333-3333-3333-3333-333333333333', '03호점 세입자' || (i + 1))
      returning id into t_id;
    insert into contracts (tenant_id, building_id, unit_no, contract_start, contract_end,
                           deposit, monthly_rent, maintenance_fee, lease_type, status, is_primary)
    values (
      t_id, '33333333-3333-3333-3333-333333333333', (101 + i) || '호',
      case when i = 1 then date_trunc('month', current_date)::date else date '2021-03-01' end,  -- 신규 1건
      date '2026-12-31',                                                                        -- 이달 만료 0
      case when i = 14 then 20000000 else 10000000 end,
      case when i = 14 then 0 when i = 13 then 750000 else 600000 end,                          -- 월세 합 7,950,000
      case when i = 14 then 0 else 50000 end,
      case when i = 14 then '전세' else '월세' end,
      '계약중', true);
  end loop;
end $$;

-- 01호점: 30 입주(100%, 30/30). 월세 3건(합 1,850,000) + 전세 27건. 이달 신규 1 / 만료 2.
do $$
declare t_id uuid; i int;
begin
  for i in 1..30 loop
    insert into tenants (building_id, name)
      values ('11111111-1111-1111-1111-111111111111', '01호점 세입자' || i)
      returning id into t_id;
    insert into contracts (tenant_id, building_id, unit_no, contract_start, contract_end,
                           deposit, monthly_rent, maintenance_fee, lease_type, status, is_primary)
    values (
      t_id, '11111111-1111-1111-1111-111111111111', (100 + i) || '호',
      case when i = 1 then date_trunc('month', current_date)::date else date '2021-06-01' end,           -- 신규 1
      case when i in (2, 3) then (date_trunc('month', current_date) + interval '20 day')::date
           else date '2026-12-31' end,                                                                   -- 만료 2
      case when i <= 3 then 10000000 else 80000000 end,
      case when i = 1 then 600000 when i = 2 then 600000 when i = 3 then 650000 else 0 end,              -- 월세 합 1,850,000
      case when i <= 3 then 50000 else 0 end,
      case when i <= 3 then '월세' else '전세' end,
      '계약중', true);
  end loop;
end $$;

-- 02호점: 14세대 중 12 입주(85.7%, 12/14), 공실 2. 월세 3건(합 1,925,000) + 전세 9건. 미납 2건.
do $$
declare t_id uuid; c_id uuid; i int;
begin
  for i in 1..12 loop
    insert into tenants (building_id, name)
      values ('22222222-2222-2222-2222-222222222222', '02호점 세입자' || i)
      returning id into t_id;
    insert into contracts (tenant_id, building_id, unit_no, contract_start, contract_end,
                           deposit, monthly_rent, maintenance_fee, lease_type, status, is_primary)
    values (
      t_id, '22222222-2222-2222-2222-222222222222', (100 + i) || '호',
      date '2021-09-01', date '2026-12-31',
      case when i <= 3 then 10000000 else 60000000 end,
      case when i = 1 then 650000 when i = 2 then 625000 when i = 3 then 650000 else 0 end,  -- 월세 합 1,925,000
      case when i <= 3 then 50000 else 0 end,
      case when i <= 3 then '월세' else '전세' end,
      '계약중', true)
    returning id into c_id;
    -- 미납 2건 (월세 계약 2건에 미납 회차 부여)
    if i <= 2 then
      insert into payments (contract_id, round_no, amount, due_date, status, is_postpaid)
        values (c_id, 5, 650000, date '2022-11-12', '미납', false);
    end if;
  end loop;
end $$;
