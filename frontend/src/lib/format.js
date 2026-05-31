// 금액 표시 포맷 — 화면 공통(목록 카드·정보 탭 등)에서 쓰는 단일 진실 공급원(OSoT).
// CLAUDE.md 컨벤션: 통화는 `1,850,000 원` 형식. 보증금 등 큰 금액은 정보 탭에서 `1.6억 원` 압축 표기.
// Supabase 는 bigint/numeric 을 문자열로 줄 수 있어 Number() 로 방어한다.

// `1,850,000 원` 형식. null/undefined/NaN 은 0 원으로 안전 처리.
export function formatWon(amount) {
  return `${(Number(amount) || 0).toLocaleString('ko-KR')} 원`
}

// 1억 이상은 `1.6억 원`(소수 1자리, .0 은 생략)으로, 그 미만은 원 단위로.
// 정보 탭 '총 보증금'(와이어프레임 1.6억 원) 표기에 사용.
export function formatEok(amount) {
  const n = Number(amount) || 0
  if (n >= 1e8) {
    const eok = Math.round((n / 1e8) * 10) / 10 // 소수 1자리 반올림 → 1.6, 21.9 …
    return `${eok}억 원`
  }
  return formatWon(n)
}
