// Flow C — AI 수선비 분담 API 클라이언트 (PRD 4.3).
// CRUD·조회는 Supabase 직결이지만, AI 산출은 FastAPI 경유다(CLAUDE.md 책임 분담).
// FastAPI 베이스 URL 은 VITE_API_BASE_URL(.env). 미설정 시 로컬 기본값.
const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000'

// 분담 비율 산출 요청 → { landlord_ratio, tenant_ratio, landlord_amount, tenant_amount,
//                         basis_lh, basis_court }.
// 실패(서버 미응답·검증 오류·네트워크)는 throw 한다 — 호출부가 에러 화면을 띄운다(무음 처리 금지).
export async function requestRepairAllocation({ expenseId, item, cost, cause, usageYears }) {
  let res
  try {
    res = await fetch(`${API_BASE}/api/repair-allocation`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        expense_id: expenseId ?? null,
        item,
        cost,
        cause,
        usage_years: usageYears,
      }),
    })
  } catch {
    // fetch 자체 실패 = 서버 미기동/네트워크 단절. 사용자에게 명확히 안내한다.
    throw new Error('AI 분담 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.')
  }

  if (!res.ok) {
    let detail = ''
    try {
      const body = await res.json()
      detail = typeof body?.detail === 'string' ? body.detail : ''
    } catch {
      // 본문 파싱 실패는 무시하고 상태코드 기반 메시지로 대체.
    }
    throw new Error(detail || `분담 비율 산출에 실패했습니다 (${res.status}).`)
  }

  return res.json()
}
