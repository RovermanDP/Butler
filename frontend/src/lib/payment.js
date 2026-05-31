// 납부 정보 관련 결정적 계산 — Step3 '첫 납부일·회차 생성·과거 미납 시드'의 단일 진실 공급원(OSoT).
// CLAUDE.md 책임 분담: 첫 납부일(선불=당월/후불=익월)·말일 보정·payments 회차 생성·과거 미납 시드는
//   LLM이 아니라 프론트의 결정적 계산으로 처리한다. Step3 회차표·이후 완료(저장) 단계가 이 함수를 공유한다.
// 날짜는 'YYYY-MM-DD'(date 컬럼과 동일 표기) 문자열, 금액은 원 단위 정수.

import { daysInMonth, parseIsoDate, pad2 } from './contractDates'

// 과거 미납 내역 선택지(휠 피커 옵션, 한글 그대로 — CLAUDE.md enum).
export const PAST_UNPAID_OPTIONS = ['미납없음', '1개월', '2개월']

// 선택값 → 미납 회차 수. '미납없음'=0 / '1개월'=1 / '2개월'=2. 알 수 없는 값은 0.
export function pastUnpaidCount(value) {
  const idx = PAST_UNPAID_OPTIONS.indexOf(value)
  return idx > 0 ? idx : 0
}

// 납부일 말일 보정 — 해당 연/월에 day가 없으면(예: 2월 30일) 그 달 말일로 당긴다.
// PRD 3장: 1~31, 월별 말일 보정(2월 28/29, 4·6·9·11월 30, 그 외 31).
export function correctedDay(y, m, day) {
  return Math.min(day, daysInMonth(y, m))
}

// 첫 납부일 — 선불=당월(n월) m일 / 후불=익월(n+1월) m일. n=12월이면 익년 1월로 롤오버.
// today: Date(기본 = 실제 오늘). paymentDay: 1~31. timing: '선불'|'후불'. 반환 'YYYY-MM-DD'.
export function firstPaymentDate(paymentDay, timing, today = new Date()) {
  let y = today.getFullYear()
  let m = today.getMonth() + 1 // 1~12
  if (timing === '후불') {
    m += 1
    if (m > 12) {
      m = 1
      y += 1
    }
  }
  const d = correctedDay(y, m, paymentDay)
  return `${y}-${pad2(m)}-${pad2(d)}`
}

// payments 회차 일괄 생성 — 첫 납부일부터 계약 종료일까지 매월 1회차.
//   각 회차 due_date = 그 달 m일(말일 보정), amount=매월 입금 예정 총액, status 기본 '대기'.
//   과거 미납 수만큼 가장 이른 회차를 '미납'으로 시드한다(PRD 3장 — 등록 시 일괄 insert).
// 반환: [{ round_no, due_date, amount, status }] (round_no 1부터, due_date 오름차순).
export function generateSchedule({ firstPayment, contractEnd, amount, paymentDay, unpaidCount = 0 }) {
  const start = parseIsoDate(firstPayment)
  if (!start || !parseIsoDate(contractEnd)) return []
  const amt = Number(amount) || 0
  const rows = []
  let y = start.y
  let m = start.m
  let round = 1
  // 상한(10년=120회)으로 무한 루프 방어 — 비정상 입력(종료일 누락 등) 시에도 멈춘다.
  while (round <= 120) {
    const d = correctedDay(y, m, paymentDay)
    const dueIso = `${y}-${pad2(m)}-${pad2(d)}`
    // ISO 'YYYY-MM-DD'는 사전식 비교 = 날짜 비교. 종료일을 넘으면 중단.
    if (dueIso > contractEnd) break
    rows.push({ round_no: round, due_date: dueIso, amount: amt, status: '대기' })
    round += 1
    m += 1
    if (m > 12) {
      m = 1
      y += 1
    }
  }
  // 과거 미납 시드 — 가장 이른 unpaidCount개 회차를 '미납'으로 표시.
  const misses = Math.min(Math.max(0, unpaidCount), rows.length)
  for (let i = 0; i < misses; i++) rows[i].status = '미납'
  return rows
}
