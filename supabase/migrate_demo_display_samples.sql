-- ============================================================
-- Butler PoC — 2026년 5월 기준 현실형 데모 데이터 보정 (v3)
--
-- 수정사항:
-- 1. 건물별 신규 세입자 다양화 (계약 시작월 분산)
-- 2. 전세 세입자 관리비 회차 생성 → 수납 현황 포함
-- 3. 완납자 생성 (계약기간 전체에 걸친 회차 완납 처리)
-- 4. 총 입금 금액 ↔ 수납 데이터 ↔ 계약기간 일치
-- 5. 지출 날짜 2026년 5월로 고정
-- ============================================================

-- ------------------------------------------------------------
-- 0) 임시 테이블
-- ------------------------------------------------------------

drop table if exists tmp_demo_contracts;

create temporary table tmp_demo_contracts (
  contract_id        uuid,
  tenant_id          uuid,
  building_id        uuid,
  unit_no            text,
  rn                 int,
  tenant_name        text,
  phone              text,
  memo               text,
  contract_start     date,
  contract_end       date,
  lease_type         text,
  deposit            bigint,
  monthly_rent       bigint,
  maintenance_fee    bigint,
  etc_fee1           bigint,
  etc_fee2           bigint,
  payment_day        int,
  payment_timing     text,
  first_payment_date date,
  may_status         text,
  may_paid_date      date
) on commit drop;


-- ------------------------------------------------------------
-- 1) 현재 계약중 대표 계약 → 데모값 생성
-- ------------------------------------------------------------

insert into tmp_demo_contracts
select
  c.id as contract_id,
  c.tenant_id,
  c.building_id,
  c.unit_no,
  row_number() over (partition by c.building_id order by c.unit_no) as rn,

  -- ── 이름 ──
  case
    when c.building_id = '11111111-1111-1111-1111-111111111111' then
      (array[
        '정하윤','최민준','권도윤','한서연','문지후','오지민','서유찬','강나은','이현우','박서진',
        '김나연','조민성','유채원','신동현','배지안','홍유준','안서우','노지훈','차예린','임서준',
        '하민서','윤태오','문하린','강도윤','최유림','이준서','서다은','장우진','백지호','남가은'
      ])[row_number() over (partition by c.building_id order by c.unit_no)]
    when c.building_id = '22222222-2222-2222-2222-222222222222' then
      (array[
        '장서윤','윤지호','송민재','백예린','임하준','조아린','남도현','신유나','류서준','고하린',
        '전민규','양지안','오하준','문예서'
      ])[row_number() over (partition by c.building_id order by c.unit_no)]
    else
      (array[
        '김동락','이수민','박준호','최하늘','정유진','강민재','오세훈','한지우','문서연','배도현',
        '유나경','서지훈','권민서','하도윤','차수빈','윤재민'
      ])[row_number() over (partition by c.building_id order by c.unit_no)]
  end as tenant_name,

  -- ── 전화번호 ──
  case
    when c.building_id = '11111111-1111-1111-1111-111111111111'
      then '010-5101-' || lpad((1000 + row_number() over (partition by c.building_id order by c.unit_no))::text, 4, '0')
    when c.building_id = '22222222-2222-2222-2222-222222222222'
      then '010-5202-' || lpad((2000 + row_number() over (partition by c.building_id order by c.unit_no))::text, 4, '0')
    else
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 1 then '010-1234-5678'
        else '010-5303-' || lpad((3000 + row_number() over (partition by c.building_id order by c.unit_no))::text, 4, '0')
      end
  end as phone,

  -- ── 메모 (rn 기준, 다양화) ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) = 1
      then '납부일 전날 꼭 연락 필요 — 종종 잊음'
    when row_number() over (partition by c.building_id order by c.unit_no) = 2
      then '2026년 2월 신규 입주. 관리비 자동이체 설정 완료.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 3
      then '연속 완납 중. 조용한 세입자.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 4
      then '전세 세입자. 보증금 반환 일정 확인 필요.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 5
      then '최근 미납 발생. 연락 요망.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 6
      then '관리비 카드 이체 설정 완료.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 7
      then '계약 갱신 의향 있음. 6월 중 협의 예정.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 8
      then '2026년 4월 신규 입주. 보증금 완납 확인.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 9
      then '이번 달 미납. 주말 이후 처리 예정이라고 함.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 10
      then '2025년 11월 입주. 수납 정상.'
    when row_number() over (partition by c.building_id order by c.unit_no) = 11
      then '수납 정상. 특이사항 없음.'
    else null
  end as memo,

  -- ── 계약 시작일 ──
  -- 01호점: 5월신규3(rn2,8,14) / 만료케이스는 contract_end로 제어 / 나머지 분산
  -- 02호점: 5월신규2(rn2,5)    / 나머지 분산
  -- 03호점: 5월신규1(rn2)      / 나머지 분산
  case
    when c.building_id = '11111111-1111-1111-1111-111111111111' then
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2026-05-01'
        when row_number() over (partition by c.building_id order by c.unit_no) = 8  then date '2026-05-10'
        when row_number() over (partition by c.building_id order by c.unit_no) = 14 then date '2026-05-15'
        when row_number() over (partition by c.building_id order by c.unit_no) = 20 then date '2025-10-01'
        when row_number() over (partition by c.building_id order by c.unit_no) % 7 = 0 then date '2024-09-01'
        when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then date '2024-11-01'
        when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then date '2025-01-15'
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2024-07-10'
        else date '2024-07-12'
      end
    when c.building_id = '22222222-2222-2222-2222-222222222222' then
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2026-05-05'
        when row_number() over (partition by c.building_id order by c.unit_no) = 5  then date '2026-05-20'
        when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then date '2025-03-01'
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2024-08-01'
        else date '2024-07-12'
      end
    else  -- 03호점
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2026-05-01'
        when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then date '2025-05-01'
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2024-07-10'
        else date '2024-07-12'
      end
  end as contract_start,

  -- ── 계약 종료일 ──
  -- 만료 케이스: 01호점 2명(rn3→2026-05-31, rn6→2026-05-20)
  --             02호점 1명(rn3→2026-05-25)
  --             03호점 1명(rn4→2026-05-31)
  -- 신규 케이스는 contract_start+2년으로 자동
  case
    when c.building_id = '11111111-1111-1111-1111-111111111111' then
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 3  then date '2026-05-31'
        when row_number() over (partition by c.building_id order by c.unit_no) = 6  then date '2026-05-20'
        when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2028-04-30'
        when row_number() over (partition by c.building_id order by c.unit_no) = 8  then date '2028-05-09'
        when row_number() over (partition by c.building_id order by c.unit_no) = 14 then date '2028-05-14'
        when row_number() over (partition by c.building_id order by c.unit_no) = 20 then date '2027-09-30'
        when row_number() over (partition by c.building_id order by c.unit_no) % 7 = 0 then date '2026-08-31'
        when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then date '2026-10-31'
        when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then date '2027-01-14'
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2026-07-09'
        else date '2026-07-11'
      end
    when c.building_id = '22222222-2222-2222-2222-222222222222' then
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 3  then date '2026-05-25'
        when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2028-05-04'
        when row_number() over (partition by c.building_id order by c.unit_no) = 5  then date '2028-05-19'
        when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then date '2027-02-28'
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2026-07-31'
        else date '2026-07-11'
      end
    else  -- 03호점
      case
        when row_number() over (partition by c.building_id order by c.unit_no) = 4  then date '2026-05-31'
        when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2028-04-30'
        when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then date '2027-04-30'
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2026-07-09'
        else date '2026-07-11'
      end
  end as contract_end,

  -- ── 월세/전세 섞기 ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) in (4, 7, 10, 18, 22, 26, 30)
      then '전세'
    else '월세'
  end as lease_type,

  -- ── 보증금 ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) in (4, 7, 10, 18, 22, 26, 30)
      then
        case
          when c.building_id = '11111111-1111-1111-1111-111111111111' then 85000000
          when c.building_id = '22222222-2222-2222-2222-222222222222' then 75000000
          else 80000000
        end
    else
      case
        when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then 15000000
        when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then 12000000
        else 10000000
      end
  end as deposit,

  -- ── 월세 (전세=null) ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) in (4, 7, 10, 18, 22, 26, 30)
      then null
    else
      (array[480000,520000,550000,580000,600000,620000,550000,580000,660000,600000,
             520000,660000,580000,600000,720000,540000,580000,620000,660000,700000,
             520000,540000,560000,600000,630000,660000,580000,600000,640000,680000]
      )[row_number() over (partition by c.building_id order by c.unit_no)]
  end as monthly_rent,

  -- ── 관리비: 월세 50,000 / 전세 80,000 ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) in (4, 7, 10, 18, 22, 26, 30)
      then 80000
    else 50000
  end as maintenance_fee,

  -- ── 기타비용 (일부) ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) in (3, 6, 11) then 30000
    else 0
  end as etc_fee1,
  0 as etc_fee2,

  -- ── 납부일 다양화 ──
  case
    when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then 10
    when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then 25
    when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then 4
    else 12
  end as payment_day,

  '후불' as payment_timing,

  -- ── 첫 납부일 (계약시작 익월) ──
  (
    date_trunc('month',
      (
        case
          when c.building_id = '11111111-1111-1111-1111-111111111111' then
            case
              when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2026-05-01'
              when row_number() over (partition by c.building_id order by c.unit_no) = 8  then date '2026-05-10'
              when row_number() over (partition by c.building_id order by c.unit_no) = 14 then date '2026-05-15'
              when row_number() over (partition by c.building_id order by c.unit_no) = 20 then date '2025-10-01'
              when row_number() over (partition by c.building_id order by c.unit_no) % 7 = 0 then date '2024-09-01'
              when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then date '2024-11-01'
              when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then date '2025-01-15'
              when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2024-07-10'
              else date '2024-07-12'
            end
          when c.building_id = '22222222-2222-2222-2222-222222222222' then
            case
              when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2026-05-05'
              when row_number() over (partition by c.building_id order by c.unit_no) = 5  then date '2026-05-20'
              when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then date '2025-03-01'
              when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2024-08-01'
              else date '2024-07-12'
            end
          else
            case
              when row_number() over (partition by c.building_id order by c.unit_no) = 2  then date '2026-05-01'
              when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then date '2025-05-01'
              when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then date '2024-07-10'
              else date '2024-07-12'
            end
        end + interval '1 month'
      )
    )
    + (
        case
          when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then 10
          when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then 25
          when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then 4
          else 12
        end - 1
      ) * interval '1 day'
  )::date as first_payment_date,

  -- ── 2026년 5월 수납 상태 ──
  -- 01호점(30세대): 미납3(rn1,5,9) / 나머지 완납
  -- 02호점(12세대): 미납2(rn1,5) / 나머지 완납
  -- 03호점(16세대): 미납1(rn1) / 나머지 완납
  -- 단, first_payment_date > '2026-05-XX' 인 신규세입자는 payments 생성 자체가 안 됨(where 조건)
  case
    when c.building_id = '11111111-1111-1111-1111-111111111111' then
      case when row_number() over (partition by c.building_id order by c.unit_no) in (1,5,9) then '미납' else '완납' end
    when c.building_id = '22222222-2222-2222-2222-222222222222' then
      case when row_number() over (partition by c.building_id order by c.unit_no) in (1,5)   then '미납' else '완납' end
    else
      case when row_number() over (partition by c.building_id order by c.unit_no) = 1         then '미납' else '완납' end
  end as may_status,

  -- ── 완납 시 paid_date ──
  case
    when (
      case
        when c.building_id = '11111111-1111-1111-1111-111111111111'
          then case when row_number() over (partition by c.building_id order by c.unit_no) in (1,5,9) then 'miss' else 'paid' end
        when c.building_id = '22222222-2222-2222-2222-222222222222'
          then case when row_number() over (partition by c.building_id order by c.unit_no) in (1,5)   then 'miss' else 'paid' end
        else case when row_number() over (partition by c.building_id order by c.unit_no) = 1           then 'miss' else 'paid' end
      end
    ) = 'paid'
    then
      make_date(2026, 5, least(28,
        case
          when row_number() over (partition by c.building_id order by c.unit_no) % 5 = 0 then 10
          when row_number() over (partition by c.building_id order by c.unit_no) % 4 = 0 then 25
          when row_number() over (partition by c.building_id order by c.unit_no) % 3 = 0 then 4
          else 12
        end
      ))
    else null
  end as may_paid_date

from contracts c
where c.status = '계약중'
  and c.is_primary = true;


-- ------------------------------------------------------------
-- 2) tenants 업데이트
-- ------------------------------------------------------------

update tenants t
set
  name  = d.tenant_name,
  phone = d.phone,
  memo  = d.memo
from tmp_demo_contracts d
where t.id = d.tenant_id;


-- ------------------------------------------------------------
-- 3) contracts 업데이트
-- ------------------------------------------------------------

update contracts c
set
  contract_start     = d.contract_start,
  contract_end       = d.contract_end,
  lease_type         = d.lease_type,
  deposit            = d.deposit,
  monthly_rent       = d.monthly_rent,
  maintenance_fee    = d.maintenance_fee,
  etc_fee1           = d.etc_fee1,
  etc_fee2           = d.etc_fee2,
  rent_vat           = false,
  maintenance_vat    = false,
  etc1_vat           = false,
  etc2_vat           = false,
  payment_day        = d.payment_day,
  payment_timing     = d.payment_timing,
  first_payment_date = d.first_payment_date,
  depositor_name     = d.tenant_name,
  -- 증빙: 하위 필드 함께 세팅 (contracts_proof_subfield_chk 충족)
  proof_kind = case
    when d.rn % 5 = 1 then '현금영수증(개인소득공제용)'
    when d.rn % 5 = 2 then '현금영수증(사업자증빙용)'
    else '해당없음'
  end,
  proof_phone = case
    when d.rn % 5 = 1 then d.phone
    else null
  end,
  proof_biz_reg_no = case
    when d.rn % 5 = 2 then '123-45-' || lpad((67890 + d.rn)::text, 5, '0')
    else null
  end,
  proof_email           = null,
  proof_biz_license_url = null
from tmp_demo_contracts d
where c.id = d.contract_id;


-- ------------------------------------------------------------
-- 4) payments 재생성
--
-- 목표: 계약 시작월부터 2026년 8월까지 회차 생성 + 총 입금 금액과 일치
--
-- 전략:
--   · 전세 세입자: monthly_rent=null → amount = maintenance_fee (관리비만 청구)
--     → payableTenants 에서 전세 제외하지 않도록 collect.js 의 조건이
--       lease_type !== '전세' 이지만, 관리비 회차가 있으면 수납 현황에 포함됨.
--     ※ 실제로 collect.js 에서 전세를 제외하므로 전세 회차는 세입자 상세에만 표시됨.
--   · 완납 회차: 2026년 5월까지의 모든 경과 회차
--     (단, first_payment_date 이전 회차는 생성 안 함)
--   · 5월 상태: may_status 로 미납/완납 분기
--   · 6~8월: 대기
-- ------------------------------------------------------------

delete from payments p
using tmp_demo_contracts d
where p.contract_id = d.contract_id;

-- 회차 범위: 계약 first_payment_date 달부터 2026-08까지 (최대 48개월)
insert into payments (contract_id, round_no, amount, due_date, status, paid_date, is_postpaid)
with months as (
  select generate_series(1, 48) as offset_mo
),
all_rows as (
  select
    d.contract_id,
    m.offset_mo,
    -- 회차 번호: 202601, 202602 ... 형식으로 연월 기반
    (
      extract(year from (d.first_payment_date + ((m.offset_mo - 1) || ' months')::interval))::int * 100
      + extract(month from (d.first_payment_date + ((m.offset_mo - 1) || ' months')::interval))::int
    ) as round_no,
    -- 회차 금액: 월세 + 관리비 + 기타. 전세는 월세=null이므로 관리비만
    (coalesce(d.monthly_rent, 0) + coalesce(d.maintenance_fee, 0) + coalesce(d.etc_fee1, 0))::bigint as amount,
    -- 납부일 (말일 보정: least 로 해당 월 최대 일수 방어 — 간단히 28 상한)
    make_date(
      extract(year from (d.first_payment_date + ((m.offset_mo - 1) || ' months')::interval))::int,
      extract(month from (d.first_payment_date + ((m.offset_mo - 1) || ' months')::interval))::int,
      least(28, d.payment_day)
    ) as due_date,
    d.may_status,
    d.may_paid_date,
    d.payment_day
  from tmp_demo_contracts d
  cross join months m
  -- 2026-08까지만 생성
  where (d.first_payment_date + ((m.offset_mo - 1) || ' months')::interval)::date <= date '2026-08-31'
    and (d.first_payment_date + ((m.offset_mo - 1) || ' months')::interval)::date <= d.contract_end
)
select
  contract_id,
  round_no,
  amount,
  due_date,
  -- 상태 결정
  case
    when due_date > date '2026-05-31' then '대기'   -- 6월 이후: 대기
    when round_no = (202600 + 5)      then may_status  -- 5월: 개별 지정
    else '완납'                                      -- 5월 이전: 완납
  end as status,
  -- paid_date
  case
    when due_date > date '2026-05-31' then null
    when round_no = (202600 + 5) then may_paid_date
    else due_date  -- 과거 완납분은 due_date 당일 납부로 처리
  end as paid_date,
  true as is_postpaid
from all_rows
where amount > 0
on conflict (contract_id, round_no) do update set
  amount      = excluded.amount,
  due_date    = excluded.due_date,
  status      = excluded.status,
  paid_date   = excluded.paid_date,
  is_postpaid = excluded.is_postpaid;


-- ------------------------------------------------------------
-- 5) 지출 날짜 2026년 5월로 수정
-- ------------------------------------------------------------

update expenses
set expense_date = date '2026-05-24'
where building_id = '33333333-3333-3333-3333-333333333333'
  and title = '도어락 교환';

update expenses
set expense_date = date '2026-05-18'
where building_id = '33333333-3333-3333-3333-333333333333'
  and title = '옥상 방수공사';

update expenses
set expense_date = date '2026-05-10'
where building_id = '33333333-3333-3333-3333-333333333333'
  and title = '201호 냉장고 수리비';

update expenses
set expense_date = date '2026-05-05'
where building_id = '33333333-3333-3333-3333-333333333333'
  and title = '에어컨 청소';

-- 01호점 지출도 5월로 보정 (도어록 교환 → 타이틀 유사 항목 포함)
update expenses
set expense_date = date '2026-05-12'
where building_id = '11111111-1111-1111-1111-111111111111'
  and title like '%냉장고%';

update expenses
set expense_date = date '2026-05-07'
where building_id = '11111111-1111-1111-1111-111111111111'
  and title like '%방수%';

-- 지출 날짜가 2026-06월로 잡혀있는 경우 5월로 일괄 보정
update expenses
set expense_date = to_date('2026-05-' || lpad(extract(day from expense_date)::text, 2, '0'), 'YYYY-MM-DD')
where expense_date >= date '2026-06-01'
  and expense_date <  date '2026-07-01';


-- ------------------------------------------------------------
-- 6) building_stats / unpaid_stats View 재정의
--    building_stats.new_this_month = 2026-05 기준
-- ------------------------------------------------------------

create or replace view building_stats as
select
  b.id as building_id,
  b.name,
  b.unit_count,

  count(distinct c.unit_no) filter (where c.status = '계약중') as occupied_units,

  trunc(
    count(distinct c.unit_no) filter (where c.status = '계약중')::numeric
    / nullif(b.unit_count, 0) * 100, 1
  ) as occupancy_rate,

  count(distinct c.unit_no) filter (where c.status = '계약중' and c.lease_type = '월세') as wolse_count,
  count(distinct c.unit_no) filter (where c.status = '계약중' and c.lease_type = '전세') as jeonse_count,

  b.unit_count - count(distinct c.unit_no) filter (where c.status = '계약중') as vacant_count,

  coalesce(sum(c.deposit) filter (where c.status = '계약중'), 0) as deposit_total,

  coalesce(
    sum(coalesce(c.monthly_rent,0) + coalesce(c.maintenance_fee,0) + coalesce(c.etc_fee1,0) + coalesce(c.etc_fee2,0))
    filter (where c.status = '계약중' and c.lease_type = '월세'), 0
  ) as rental_income,

  count(*) filter (
    where c.status = '계약중'
      and c.contract_start >= date '2026-05-01'
      and c.contract_start <  date '2026-06-01'
  ) as new_this_month,

  count(*) filter (
    where c.status = '계약중'
      and c.contract_end >= date '2026-05-01'
      and c.contract_end <  date '2026-06-01'
  ) as expiring_this_month

from buildings b
left join contracts c on c.building_id = b.id
group by b.id, b.name, b.unit_count;


create or replace view unpaid_stats as
select
  c.building_id,
  count(*) filter (where p.status = '미납') as unpaid_count,
  coalesce(sum(p.amount) filter (where p.status = '미납'), 0) as unpaid_amount
from contracts c
join payments p on p.contract_id = c.id
where c.status = '계약중'
group by c.building_id;


-- ------------------------------------------------------------
-- 7) 알림톡 히스토리 생성 (01·02·03호점 전체)
--    모든 날짜는 2026년 5월 이내로 고정
--    03호점은 seed.sql의 김동락 외 나머지 세입자 추가
-- ------------------------------------------------------------

-- 기존 demo 알림톡 정리 (재실행 idempotent) — 03호점도 김동락 제외하고 정리
delete from notifications
where contract_id in (
  select c.id from contracts c
  join tenants t on t.id = c.tenant_id
  where c.building_id in (
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333'
  )
  and c.status = '계약중'
  and c.is_primary = true
  and t.phone is not null
  and c.id != 'cccccccc-cccc-cccc-cccc-cccccccc0001'  -- 김동락은 seed.sql 소유
);

-- 납부 1일전 알림 (3·4·5월, 납부일 전날 18:00) — 3개 건물 전체
insert into notifications (contract_id, type, title, body, sent_at, status)
select
  c.id,
  '납부',
  '납부 1일전 알림톡 발송',
  t.name || '님, 내일(' || to_char(make_date(2026, m.mo, least(28, c.payment_day)), 'MM월 DD일') || ') ' ||
    (coalesce(c.monthly_rent,0) + coalesce(c.maintenance_fee,0) + coalesce(c.etc_fee1,0))::bigint ||
    '원 납부 예정입니다.',
  make_date(2026, m.mo, least(28, c.payment_day)) - interval '1 day' + interval '18 hours',
  'mock_sent'
from contracts c
join tenants t on t.id = c.tenant_id
cross join (select unnest(array[3,4,5]) as mo) m
where c.building_id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333'
)
and c.status = '계약중'
and c.is_primary = true
and t.phone is not null
and c.id != 'cccccccc-cccc-cccc-cccc-cccccccc0001'
-- 신규(5월 시작) 세입자는 납부일이 6월 이후라 5월 알림 제외
and c.first_payment_date <= make_date(2026, m.mo, 28)
-- 전세는 월세 없으므로 amount > 0인 경우만 (관리비만인 경우 포함)
and (coalesce(c.monthly_rent,0) + coalesce(c.maintenance_fee,0) + coalesce(c.etc_fee1,0)) > 0;

-- 미납 알림 (D+3, D+7 — 5월 미납 대상자, 모든 건물)
insert into notifications (contract_id, type, title, body, sent_at, status)
select
  c.id,
  '미납',
  '미납 ' || v.n || '일차 알림톡 발송',
  t.name || '님, ' || to_char(make_date(2026, 5, least(28, c.payment_day)), 'MM월 DD일') ||
    ' 납부 예정분(' ||
    (coalesce(c.monthly_rent,0) + coalesce(c.maintenance_fee,0) + coalesce(c.etc_fee1,0))::bigint ||
    '원)이 미납되었습니다.',
  -- D+3/D+7 이지만 5월 31일 이내로 캡
  least(
    make_date(2026, 5, least(28, c.payment_day)) + (v.n || ' days')::interval + interval '13 hours',
    timestamptz '2026-05-31 23:59:00'
  ),
  'mock_sent'
from contracts c
join tenants t on t.id = c.tenant_id
cross join (select unnest(array[3,7]) as n) v
where exists (
  select 1 from payments p
  where p.contract_id = c.id
    and p.round_no = 202605
    and p.status = '미납'
)
and c.building_id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333'
)
and c.status = '계약중'
and c.is_primary = true
and t.phone is not null
and c.id != 'cccccccc-cccc-cccc-cccc-cccccccc0001';

-- 연장 알림 (계약 종료일이 2026-11-30 이내인 세입자 → 5월 15일 발송으로 고정)
insert into notifications (contract_id, type, title, body, sent_at, status)
select
  c.id,
  '연장',
  '계약 연장 여부 알림톡 발송',
  t.name || '님, 계약 종료(' || to_char(c.contract_end, 'YY.MM.DD') ||
    ')가 다가옵니다. 연장 여부를 확인해 주세요.',
  timestamptz '2026-05-15 10:00:00',  -- 5월 15일 고정
  'mock_sent'
from contracts c
join tenants t on t.id = c.tenant_id
where c.building_id in (
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333'
)
and c.status = '계약중'
and c.is_primary = true
and t.phone is not null
and c.id != 'cccccccc-cccc-cccc-cccc-cccccccc0001'
and c.contract_end <= date '2026-11-30';


-- ------------------------------------------------------------
-- 8) 김동락(03호점 101호) 알림톡 5월 이내로 재생성
--    seed.sql 에서 current_date 기준으로 생성되어 6월이 포함되므로 덮어씀
-- ------------------------------------------------------------

delete from notifications
where contract_id = 'cccccccc-cccc-cccc-cccc-cccccccc0001';

-- 납부 1일전: 3·4·5월 (납부일=12일 → 전날 11일 18:00)
insert into notifications (id, contract_id, type, title, sent_at, status) values
  ('d1000000-0000-0000-0000-000000000021'::uuid,
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   '납부', '납부 1일전 알림톡 발송',
   timestamptz '2026-03-11 18:00:00', 'mock_sent'),
  ('d1000000-0000-0000-0000-000000000022'::uuid,
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   '납부', '납부 1일전 알림톡 발송',
   timestamptz '2026-04-11 18:00:00', 'mock_sent'),
  ('d1000000-0000-0000-0000-000000000023'::uuid,
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   '납부', '납부 1일전 알림톡 발송',
   timestamptz '2026-05-11 18:00:00', 'mock_sent');

-- 미납 D+3, D+7 (5월 12일 기준 → 5월 15일, 5월 19일)
insert into notifications (id, contract_id, type, title, sent_at, status) values
  ('d2000000-0000-0000-0000-000000000003'::uuid,
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   '미납', '미납 3일차 알림톡 발송',
   timestamptz '2026-05-15 13:00:00', 'mock_sent'),
  ('d2000000-0000-0000-0000-000000000007'::uuid,
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   '미납', '미납 7일차 알림톡 발송',
   timestamptz '2026-05-19 13:00:00', 'mock_sent');

-- 연장 여부: 5월 15일 (계약 종료 2026-07-12로 6개월 이내)
insert into notifications (id, contract_id, type, title, sent_at, status) values
  ('d3000000-0000-0000-0000-000000000001'::uuid,
   'cccccccc-cccc-cccc-cccc-cccccccc0001',
   '연장', '계약 연장 여부 알림톡 발송',
   timestamptz '2026-05-15 10:00:00', 'mock_sent');