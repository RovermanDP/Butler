-- ============================================================
-- Butler PoC — 시드 데이터 (와이어프레임 실제 값 기준)
-- ⚠ 날짜는 current_date 기준 상대값으로 둔다(계약기간·회차 due_date·지출·알림톡).
--    → 데모를 언제 돌려도 미납 D+n·"이번 달 지출"이 현실적으로 표시된다(과거 2022 고정일 폐기).
--    금액·세대수(입주율·임대수익·보증금)는 날짜 무관이라 와이어프레임 수치 그대로 유지.
--    김동락 계약 시작/종료 월은 '이번 달'과 겹치지 않게 둬 03호점 '이달 신규 1/만료 0'(filler 산출)을 보존.
-- ⚠ 비파괴 · idempotent: 고정 UUID + on conflict + 채움 루프 존재가드로, 기존 데이터(예: Flow A로
--    등록한 건물)를 지우지 않고 데모 데이터만 덧입힌다. 여러 번 실행해도 중복 INSERT 되지 않는다.
--    예외: 김동락 계약(0001)의 회차·알림톡은 데모 날짜 재생성을 위해 '그 계약의 행만' delete 후 재삽입한다
--    (이 파일이 소유한 데모 행만 — 사용자 데이터는 건드리지 않음). 계약기간은 on conflict do update 로 갱신.
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
--       계약기간 = 데모 기준 2024-07-12 ~ 2026-07-12(약 2년). current_date(데모=2026-05-31) 상대값으로 표현 →
--         시작 = 이번달(-22개월)+11일, 종료 = 이번달(+2개월)+11일. 시작/종료월(7월)≠이번달(5월) → 이달 신규/만료 0 유지.
--       월세 550,000·관리비 94,500은 '부가세 포함(최종 청구)' 금액이므로 VAT 플래그는 false.
--       (PRD 3장: 플래그 true면 ×1.1 가산 → 이미 포함값에 켜면 이중가산되어 회차 금액과 불일치)
--       12일 후불, 첫 납부=시작 +1개월(2024-08-12), 증빙=현금영수증(개인소득공제용).
--       0002: 과거 종료 계약(현재 계약 직전 2년: 2022-07-12 ~ 2024-07-11) — 신규 필드 null.
-- ⚠ 데모 날짜 재생성: on conflict 시 계약기간/첫 납부일을 갱신한다(아래 회차·알림톡 재생성과 짝).
insert into contracts (id, tenant_id, building_id, unit_no, contract_start, contract_end,
                       deposit, monthly_rent, maintenance_fee, lease_type,
                       rent_vat, maintenance_vat,
                       payment_day, payment_timing, first_payment_date, depositor_name,
                       proof_kind, proof_phone,
                       status, is_primary) values
  ('cccccccc-cccc-cccc-cccc-cccccccc0001',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
   '101호',
   (date_trunc('month', current_date) - interval '22 months' + interval '11 days')::date,  -- 시작 2024-07-12
   (date_trunc('month', current_date) + interval '2 months'  + interval '11 days')::date,   -- 종료 2026-07-12
   10000000, 550000, 94500, '월세',
   false, false,
   12, '후불',
   (date_trunc('month', current_date) - interval '21 months' + interval '11 days')::date, '김동락',  -- 첫 납부 2024-08-12(후불 → 시작 +1개월)
   '현금영수증(개인소득공제용)', '010-1234-5678',
   '계약중', true),
  ('cccccccc-cccc-cccc-cccc-cccccccc0002',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333',
   '101호',
   (date_trunc('month', current_date) - interval '46 months' + interval '11 days')::date,  -- 직전 종료 계약 2022-07-12
   (date_trunc('month', current_date) - interval '22 months' + interval '10 days')::date,   -- 종료 2024-07-11(현재 계약 시작 직전)
   8000000, 500000, 80000, '월세',
   false, false,
   12, '후불',
   (date_trunc('month', current_date) - interval '45 months' + interval '11 days')::date, '김동락',
   '해당없음', null,
   '종료', false)
on conflict (id) do update set
  contract_start     = excluded.contract_start,
  contract_end       = excluded.contract_end,
  first_payment_date = excluded.first_payment_date;

-- 김동락 수납 회차 (101호, 회차 청구 650,000, 입금 예정일 12일, 월세 후불)
-- ⚠ 데모 큐레이션: 계약 전기간(첫 납부 2024-08-12 ~ 종료 2026-07-12) 매월 12일 = 24회차를 시리즈로 생성한다.
--    · 회차 청구액 650,000은 와이어프레임 표기값(월세 550,000+관리비 94,500=644,500의 데모 반올림).
--    · 상태: due_date > 오늘 → '대기'(미래 회차), 미납 큐레이션(이번달 회차) → '미납', 그 외 경과분 → '완납'.
--    · 미납 1건 = 이번달(2026-05, off_mo 0, due 2026-05-12) → 알림톡 '미납 3·7일차'와 짝. 오늘(05-31) 기준 D+19.
--      총 입금 = 완납 21회차 × 650,000 = 13,650,000 / 미납 1건 = 650,000(현재 날짜 2026-05-31 기준).
--    PRD 3장 §"payments 회차 자동 생성"은 Flow E '등록 시점'의 결정적 계산 책임이며, 이 데모 계약은 그 산출물이 아니다.
-- 데모 날짜 재생성을 위해 이 계약(0001)의 기존 회차를 비우고 다시 채운다(이 파일이 소유한 데모 행만 삭제).
delete from payments where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001';
insert into payments (contract_id, round_no, amount, due_date, status, paid_date, is_postpaid)
select
  'cccccccc-cccc-cccc-cccc-cccccccc0001',
  p.n,
  650000,
  p.due,
  case when p.due > current_date then '대기'
       when p.off_mo = 0 then '미납'
       else '완납' end,
  case when p.due > current_date or p.off_mo = 0 then null else p.due end,
  true
from (
  select gs.n,
         (21 - (gs.n - 1)) as off_mo,  -- round1 = -21개월(2024-08) … round22 = 0(2026-05) … round24 = +2(2026-07)
         (date_trunc('month', current_date) - ((21 - (gs.n - 1)) || ' months')::interval + interval '11 days')::date as due
  from generate_series(1, 24) as gs(n)
) p
on conflict (contract_id, round_no) do nothing;

-- 03호점 지출 (이번 달 합계 1,221,000 / 4건). 냉장고 수리비만 is_repair=true → AI 분담 진입.
-- expense_date 도 이번 달(현재 기준)로 둔다 → 지출 탭 "이번 달 지출" 라벨과 실제 날짜가 일치.
insert into expenses (id, building_id, expense_date, title, amount, proof_type, is_repair) values
  ('e0000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', (date_trunc('month', current_date) + interval '4 days')::date,  '에어컨 청소',          99000, '세금계산서',       false),
  ('e0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', (date_trunc('month', current_date) + interval '9 days')::date,  '201호 냉장고 수리비',  165000, null,             true),
  ('e0000000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', (date_trunc('month', current_date) + interval '17 days')::date, '옥상 방수공사',        880000, '현금영수증(개인)', false),
  ('e0000000-0000-0000-0000-000000000004', '33333333-3333-3333-3333-333333333333', (date_trunc('month', current_date) + interval '24 days')::date, '도어록 교환',           77000, '간이영수증',       false)
on conflict (id) do nothing;

-- 김동락 알림톡 히스토리 (모두 mock_sent — 종류별 태그/타임라인). 회차 타임라인과 짝을 이뤄 재생성한다.
--   · 납부 1일전(매월 11일 18:00): 첫 납부월(2024-08)부터 이번달(2026-05)까지 22건. PRD 발송 스케줄 D-1.
--   · 미납 n일차(13:00, n∈{3,7} POC 고정, 날짜=11+n일): 이번달(2026-05) 미납 회차에 대해 3일차·7일차 = 2건.
--   · 연장 여부(매월 15일 10:00): 종료(2026-07)월 기준 -6 ~ -2개월 = 2026-01 ~ 2026-05 → 5건.
-- 데모 날짜 재생성을 위해 이 계약(0001)의 기존 알림톡을 비우고 다시 채운다(이 파일이 소유한 데모 행만 삭제).
delete from notifications where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001';
-- 납부 1일전 22건 (이번달 기준 -0 ~ -21개월, 매월 11일 18:00)
insert into notifications (id, contract_id, type, title, sent_at, status)
select
  ('d1000000-0000-0000-0000-' || lpad(gs.m::text, 12, '0'))::uuid,
  'cccccccc-cccc-cccc-cccc-cccccccc0001', '납부', '납부 1일전 알림톡 발송',
  date_trunc('month', current_date) - (gs.m || ' months')::interval + interval '10 days 18 hours',
  'mock_sent'
from generate_series(0, 21) as gs(m);
-- 미납 n일차 2건 (이번달 2026-05 미납 회차 대상, 날짜=11+n일 13:00 → 05-14·05-18)
insert into notifications (id, contract_id, type, title, sent_at, status)
select
  ('d2000000-0000-0000-0000-' || lpad(v.n::text, 12, '0'))::uuid,
  'cccccccc-cccc-cccc-cccc-cccccccc0001', '미납', '미납 ' || v.n || '일차 알림톡 발송',
  date_trunc('month', current_date) + ((10 + v.n) || ' days')::interval + interval '13 hours',
  'mock_sent'
from (values (3), (7)) as v(n);
-- 연장 여부 5건 (이번달 기준 -0 ~ -4개월 = 2026-05 ~ 2026-01, 매월 15일 10:00)
insert into notifications (id, contract_id, type, title, sent_at, status)
select
  ('d3000000-0000-0000-0000-' || lpad(gs.m::text, 12, '0'))::uuid,
  'cccccccc-cccc-cccc-cccc-cccccccc0001', '연장', '연장 여부 알림톡 발송',
  date_trunc('month', current_date) - (gs.m || ' months')::interval + interval '14 days 10 hours',
  'mock_sent'
from generate_series(0, 4) as gs(m);

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
        values (c_id, 5, 650000, (date_trunc('month', current_date) + interval '11 days')::date, '미납', false);
    end if;
  end loop;
end $$;
