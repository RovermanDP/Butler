// 계약 기간 관련 결정적 날짜 계산 — Step1 캘린더·종료일 자동 +1년의 단일 진실 공급원(OSoT).
// CLAUDE.md 책임 분담: 종료일 +1년·말일(윤년) 보정은 LLM이 아니라 프론트의 결정적 계산으로 처리한다.
// 모든 날짜는 'YYYY-MM-DD'(date 컬럼과 동일 표기) 문자열로 주고받는다.

const WEEKDAYS_KO = ['일', '월', '화', '수', '목', '금', '토']

function pad2(n) {
  return String(n).padStart(2, '0')
}

// 'YYYY-MM-DD' → { y, m(1~12), d }. 형식이 아니면 null.
export function parseIsoDate(iso) {
  if (typeof iso !== 'string') return null
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
  if (!match) return null
  const y = Number(match[1])
  const m = Number(match[2])
  const d = Number(match[3])
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null
  return { y, m, d }
}

// y년 m월(1~12)의 일수. 윤년 2월은 29, 평년은 28.
export function daysInMonth(y, m) {
  // new Date(y, m, 0) = m월(1-based)의 0번째 날 = 직전 달 말일 = m월 말일.
  return new Date(y, m, 0).getDate()
}

// 해당 월 1일의 요일(0=일 ~ 6=토).
export function firstWeekday(y, m) {
  return new Date(y, m - 1, 1).getDay()
}

// 시작일 + 정확히 1년(같은 월/일). 시작이 윤년 2/29면 종료는 평년의 가장 가까운 날(2/28)로 보정.
// 예) 2026-05-31 → 2027-05-31, 2024-02-29 → 2025-02-28.
export function addOneYear(iso) {
  const parsed = parseIsoDate(iso)
  if (!parsed) return ''
  const { y, m, d } = parsed
  const ny = y + 1
  const day = Math.min(d, daysInMonth(ny, m)) // 말일 보정(2/29 → 2/28)
  return `${ny}-${pad2(m)}-${pad2(day)}`
}

// 'YYYY-MM-DD' → 'M월 D일 (요일)' (캘린더 모달 상단 표기).
export function formatKoDate(iso) {
  const parsed = parseIsoDate(iso)
  if (!parsed) return ''
  const { y, m, d } = parsed
  const wd = WEEKDAYS_KO[new Date(y, m - 1, d).getDay()]
  return `${m}월 ${d}일 (${wd})`
}

// 'YYYY-MM-DD' → 'Y년 M월 D일' (Step3 첫 납부일 표기). 형식 아니면 빈 문자열.
export function formatKoYmd(iso) {
  const parsed = parseIsoDate(iso)
  if (!parsed) return ''
  const { y, m, d } = parsed
  return `${y}년 ${m}월 ${d}일`
}

// 'YYYY-MM-DD' → 'YY.MM.DD' (회차표·납부 행의 보조 날짜 표기). 형식 아니면 빈 문자열.
export function formatShortDate(iso) {
  const parsed = parseIsoDate(iso)
  if (!parsed) return ''
  const { y, m, d } = parsed
  return `${String(y).slice(2)}.${pad2(m)}.${pad2(d)}`
}

// 'YYYY-MM-DD' → 'YYYY.MM.DD' (세입자 탭 계약기간 표기: 2020.12.12 ~ 2022.12.11). 형식 아니면 빈 문자열.
export function formatDotYmd(iso) {
  const parsed = parseIsoDate(iso)
  if (!parsed) return ''
  const { y, m, d } = parsed
  return `${y}.${pad2(m)}.${pad2(d)}`
}

// 'YYYY-MM-DD'(예정일)로부터 오늘까지 경과 일수. 미납 D+N 표기용(음수는 0으로 클램프).
// 데모 시드는 과거 날짜라 큰 값이 나올 수 있으나, Flow E 신규 등록분은 최근 날짜라 정상 범위.
export function daysOverdue(iso, today = new Date()) {
  const parsed = parseIsoDate(iso)
  if (!parsed) return 0
  const { y, m, d } = parsed
  const due = new Date(y, m - 1, d)
  const base = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  const diff = Math.floor((base - due) / 86400000)
  return diff > 0 ? diff : 0
}

// 월 그리드(6주 X 7일). 앞쪽 빈칸은 null, 날짜 칸은 'YYYY-MM-DD'.
// 캘린더 모달이 요일 정렬된 셀을 그리는 데 쓴다.
export function monthGrid(y, m) {
  const lead = firstWeekday(y, m)
  const total = daysInMonth(y, m)
  const cells = []
  for (let i = 0; i < lead; i++) cells.push(null)
  for (let d = 1; d <= total; d++) cells.push(`${y}-${pad2(m)}-${pad2(d)}`)
  return cells
}

// 월 이동(+1/-1) 시 넘길 { y, m }. 12월 → 익년 1월, 1월 → 전년 12월 롤오버.
export function shiftMonth(y, m, delta) {
  const idx = (y * 12 + (m - 1)) + delta
  return { y: Math.floor(idx / 12), m: (idx % 12) + 1 }
}

export { pad2 }
