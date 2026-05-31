-- ============================================================
-- Butler PoC — 시드 날짜 비파괴 마이그레이션
-- 이미 적재된 데모 데이터(김동락 외 02호점 미납)의 '과거 2022 고정일'을
-- current_date 기준 상대 날짜로 갱신한다. 행을 새로 만들거나 지우지 않고
-- 고정 UUID 행만 UPDATE 하므로 Flow A 실데이터·기타 데이터는 보존된다.
--
-- 적용: Supabase SQL Editor 에 붙여넣어 1회 실행. (여러 번 실행해도 안전 — 멱등)
-- ⚠ seed.sql 의 날짜와 동일한 식을 쓴다(둘을 함께 바꿀 때 같은 결과가 나오도록).
--   금액·세대수는 건드리지 않으므로 집계(입주율·임대수익·보증금·신규/만료)는 그대로다.
-- ============================================================

begin;

-- ── 김동락 현재 계약(0001): 약 2년, 시작/종료월이 '이번 달'과 겹치지 않게 ──────────
-- (시작월≠이번달 → 03호점 '이달 신규 0', 종료월≠이번달 → '이달 만료 0' 보존. 신규 1은 filler 산출.)
update contracts set
  contract_start     = (date_trunc('month', current_date) - interval '16 months' + interval '11 days')::date,
  contract_end       = (date_trunc('month', current_date) + interval '7 months'  + interval '10 days')::date,
  first_payment_date = (date_trunc('month', current_date) - interval '15 months' + interval '11 days')::date
where id = 'cccccccc-cccc-cccc-cccc-cccccccc0001';

-- ── 김동락 직전 종료 계약(0002): 현재 계약 직전 2년 ───────────────────────────────
update contracts set
  contract_start     = (date_trunc('month', current_date) - interval '40 months' + interval '11 days')::date,
  contract_end       = (date_trunc('month', current_date) - interval '16 months' + interval '10 days')::date,
  first_payment_date = (date_trunc('month', current_date) - interval '39 months' + interval '11 days')::date
where id = 'cccccccc-cccc-cccc-cccc-cccccccc0002';

-- ── 김동락 회차(0001): 9 대기(다음달)·8 미납(이번달 → D+n)·7·6 완납(지난 1·2개월) ──
update payments set
  due_date  = (date_trunc('month', current_date) + interval '1 month' + interval '11 days')::date,
  paid_date = null
where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001' and round_no = 9;

update payments set
  due_date  = (date_trunc('month', current_date) + interval '11 days')::date,
  paid_date = null
where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001' and round_no = 8;

update payments set
  due_date  = (date_trunc('month', current_date) - interval '1 month' + interval '11 days')::date,
  paid_date = (date_trunc('month', current_date) - interval '1 month' + interval '11 days')::date
where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001' and round_no = 7;

update payments set
  due_date  = (date_trunc('month', current_date) - interval '2 months' + interval '11 days')::date,
  paid_date = (date_trunc('month', current_date) - interval '2 months' + interval '10 days')::date
where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001' and round_no = 6;

-- ── 03호점 지출 4건: 이번 달로 → "이번 달 지출" 라벨과 실제 날짜 일치 ──────────────
update expenses set expense_date = (date_trunc('month', current_date) + interval '4 days')::date
where id = 'e0000000-0000-0000-0000-000000000001';
update expenses set expense_date = (date_trunc('month', current_date) + interval '9 days')::date
where id = 'e0000000-0000-0000-0000-000000000002';
update expenses set expense_date = (date_trunc('month', current_date) + interval '17 days')::date
where id = 'e0000000-0000-0000-0000-000000000003';
update expenses set expense_date = (date_trunc('month', current_date) + interval '24 days')::date
where id = 'e0000000-0000-0000-0000-000000000004';

-- ── 김동락 알림톡 히스토리 7건: 최근 몇 개월(mock — 납부/미납/연장/종료 색 태그) ────
update notifications set sent_at = date_trunc('month', current_date) + interval '10 days 18 hours'
where id = 'd0000000-0000-0000-0000-000000000001';
update notifications set sent_at = date_trunc('month', current_date) + interval '18 days 13 hours'
where id = 'd0000000-0000-0000-0000-000000000002';
update notifications set sent_at = date_trunc('month', current_date) - interval '1 month' + interval '10 days 18 hours'
where id = 'd0000000-0000-0000-0000-000000000003';
update notifications set sent_at = date_trunc('month', current_date) - interval '1 month' + interval '13 days 13 hours'
where id = 'd0000000-0000-0000-0000-000000000004';
update notifications set sent_at = date_trunc('month', current_date) - interval '2 months' + interval '10 days 18 hours'
where id = 'd0000000-0000-0000-0000-000000000005';
update notifications set sent_at = date_trunc('month', current_date) - interval '2 months' + interval '10 hours'
where id = 'd0000000-0000-0000-0000-000000000006';
update notifications set sent_at = date_trunc('month', current_date) - interval '16 months' + interval '10 days 10 hours'
where id = 'd0000000-0000-0000-0000-000000000007';

-- ── 02호점 채움 미납 회차(고정 UUID 없음 → 건물+회차+상태로 특정): 이번달 12일 ──────
update payments p set
  due_date = (date_trunc('month', current_date) + interval '11 days')::date
from contracts c
where p.contract_id = c.id
  and c.building_id = '22222222-2222-2222-2222-222222222222'
  and p.round_no = 5
  and p.status = '미납';

commit;
