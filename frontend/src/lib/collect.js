// 건물 수납 현황(화면 7 · PRD 4.2 B-4) — 대표 회차 선정·집계·정렬 순수 함수 (OSoT).
// 세입자별 행과 상단 집계 카드가 '동일한 대표 회차'에서 산출되도록 한 곳에 모은다.
// 표시 포맷(원화·날짜)은 컴포넌트가 담당하고, 여기서는 분류·계산만 한다(SRP).
import { daysOverdue } from './contractDates'

// 회차 상태 → CSS 클래스. CLAUDE.md 상태색: 대기=gray / 미납=danger / 완납=ok.
const STATUS_CLASS = { 대기: 'wait', 미납: 'miss', 완납: 'paid' }
export function statusClass(status) {
  return STATUS_CLASS[status] ?? 'wait'
}

// 수납 현황 대상 세입자: 회차(payments)가 있고 + 월세(전세 제외).
// ⚠ 전세 세대는 월세 회차가 없어 수납 현황 목록에서 제외(PRD/CLAUDE.md).
export function payableTenants(tenants) {
  return (tenants ?? []).filter(
    (t) => t.payments?.length > 0 && t.primary?.lease_type !== '전세',
  )
}

// 세입자 1명의 '대표 회차' 선정. 우선순위 미납 > 대기 > 완납.
//  · 미납 존재  → 가장 이른(round_no 최소) 미납 회차. 예정일=due_date(D+n 표기).
//  · 대기 존재  → 가장 이른 대기 회차. 예정일=due_date.
//  · 모두 완납  → 가장 최근(round_no 최대) 완납 회차. 예정일=paid_date||due_date.
// 반환: { tenant, payment, status, amount, dueDate, paid, overdue }
export function representative(t) {
  const ps = t.payments ?? []
  const earliest = (s) =>
    ps.filter((p) => p.status === s).sort((a, b) => a.round_no - b.round_no)[0]
  const latest = (s) =>
    ps.filter((p) => p.status === s).sort((a, b) => b.round_no - a.round_no)[0]

  const payment = earliest('미납') ?? earliest('대기') ?? latest('완납') ?? ps[0]
  const status = payment?.status ?? '대기'
  return {
    tenant: t,
    payment,
    status,
    amount: Number(payment?.amount) || 0,
    dueDate: status === '완납' ? payment?.paid_date || payment?.due_date : payment?.due_date,
    paid: status === '완납',
    overdue: status === '미납' ? daysOverdue(payment?.due_date) : 0,
  }
}

// 대표 회차 목록 → 상단 집계. 세입자 1명 = 1건. 대표 상태로 분류·금액 합산.
export function aggregate(reps) {
  const bucket = () => ({ count: 0, amount: 0 })
  const agg = { total: bucket(), paid: bucket(), miss: bucket(), wait: bucket() }
  const KEY = { 완납: 'paid', 미납: 'miss', 대기: 'wait' }
  for (const r of reps) {
    agg.total.count += 1
    agg.total.amount += r.amount
    const k = KEY[r.status] ?? 'wait'
    agg[k].count += 1
    agg[k].amount += r.amount
  }
  // 진행 막대 비율(%) — 완납·미납 구간만 칠하고 나머지(대기)는 gray 배경이 드러난다.
  const pct = (n) => (agg.total.count ? Math.round((n / agg.total.count) * 100) : 0)
  agg.bar = { ok: pct(agg.paid.count), miss: pct(agg.miss.count) }
  return agg
}

// 단일 세입자 회차 요약 — 세입자 상세 정보 탭(6a) 수납 요약·수납 탭(6c) payhead 공유(OSoT/SRP).
// 표시 포맷은 컴포넌트가 담당하고, 여기서는 분류·합산만 한다. 화면 7 집계(aggregate)는
// '세입자 1명=1건' 단위지만, 여기는 '한 세입자의 회차들' 단위라 역할이 다르다.
// 반환: { paidCount, paidTotal, missCount, missTotal, monthly }
//   · paid*  : 완납 회차 건수·합계(= '총 입금 금액').
//   · miss*  : 미납 회차 건수·합계.
//   · monthly: 매월 납부액 = 대표 회차 금액(미납 > 대기 > 완납 우선, 없으면 첫 회차). 회차 금액은 동일하므로 대표 1건으로 충분.
export function tenantPaymentSummary(payments) {
  const ps = payments ?? []
  const sum = (s) =>
    ps.filter((p) => p.status === s).reduce((acc, p) => acc + (Number(p.amount) || 0), 0)
  const count = (s) => ps.filter((p) => p.status === s).length
  const rep =
    ps.find((p) => p.status === '미납') ??
    ps.find((p) => p.status === '대기') ??
    ps.find((p) => p.status === '완납') ??
    ps[0]
  return {
    paidCount: count('완납'),
    paidTotal: sum('완납'),
    missCount: count('미납'),
    missTotal: sum('미납'),
    monthly: Number(rep?.amount) || 0,
  }
}

// 호실 자연 정렬용 키: "107동 1105호" → 숫자 시퀀스 비교로 101호 < 1105호 < 102호 오류 방지.
function unitKey(unitNo) {
  return (unitNo ?? '')
    .split(/(\d+)/)
    .map((seg) => (/^\d+$/.test(seg) ? Number(seg) : seg))
}
function cmpUnit(a, b) {
  const ka = unitKey(a)
  const kb = unitKey(b)
  for (let i = 0; i < Math.max(ka.length, kb.length); i++) {
    const x = ka[i]
    const y = kb[i]
    if (x === undefined) return -1
    if (y === undefined) return 1
    if (typeof x === 'number' && typeof y === 'number') {
      if (x !== y) return x - y
    } else if (String(x) !== String(y)) {
      return String(x) < String(y) ? -1 : 1
    }
  }
  return 0
}

// 대표 회차 목록 정렬. mode 'unit'(세대/호수순) | 'due'(입금예정일순), dir 'asc' | 'desc'.
export function sortReps(reps, mode, dir) {
  const sign = dir === 'desc' ? -1 : 1
  const arr = [...reps]
  arr.sort((a, b) => {
    let c
    if (mode === 'due') {
      c = String(a.dueDate ?? '').localeCompare(String(b.dueDate ?? ''))
    } else {
      c = cmpUnit(a.tenant.primary?.unit_no, b.tenant.primary?.unit_no)
    }
    return c * sign
  })
  return arr
}
