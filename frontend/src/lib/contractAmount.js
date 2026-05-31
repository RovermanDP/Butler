// 계약 금액 관련 결정적 계산 — Step2 '매월 입금 예정 총액'의 단일 진실 공급원(OSoT).
// CLAUDE.md 책임 분담: 매월 총액은 LLM이 아니라 프론트의 결정적 계산으로 처리하며,
// Step2 합산 박스·완료 화면·payments 회차 생성(차기 Step)이 모두 이 함수를 공유한다.
// 금액은 원 단위 정수(또는 숫자 문자열). null/빈문자/NaN 은 0 으로 안전 처리한다.

// 한 항목의 합산 금액. 부가세 플래그가 켜지면 ×1.1(원 단위 반올림), 아니면 입력값 그대로.
// PRD 3장: "각 항목의 부가세 플래그가 켜져 있으면 해당 금액을 부가세 포함(×1.1)으로 합산".
export function vatInclusive(amount, vat) {
  const n = Number(amount) || 0
  return vat ? Math.round(n * 1.1) : n
}

// 매월 입금 예정 총액 = (월세 if 월세계약) + 관리비 + 기타비용1 + 기타비용2.
// 항목별 부가세 플래그 반영. 전세는 월세 항목을 제외한다(월세 row 자체가 폼에서 빠짐).
// c: { leaseType, monthlyRent, rentVat, maintenanceFee, maintenanceVat,
//      etcFee1, etc1Vat, etcFee2, etc2Vat }
export function monthlyTotal(c) {
  const rent = c.leaseType === '월세' ? vatInclusive(c.monthlyRent, c.rentVat) : 0
  return (
    rent +
    vatInclusive(c.maintenanceFee, c.maintenanceVat) +
    vatInclusive(c.etcFee1, c.etc1Vat) +
    vatInclusive(c.etcFee2, c.etc2Vat)
  )
}
