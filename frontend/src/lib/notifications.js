// Flow D — 자동 알림톡 (PRD 4.4).
// CLAUDE.md 책임 분담: 히스토리 '조회'는 Supabase 직결, 미리보기·발송(mock)은 FastAPI 경유.
//   · fetchBuildingNotifications: 건물 단위 알림톡 내역(화면 11) — notifications → contracts(건물)·세입자명.
//   · requestNotificationPreview: 카카오 미리보기 + 발송 스케줄(화면 12) — 템플릿 치환(FastAPI).
//   · sendNotificationMock: 발송(mock) — status='mock_sent' 기록만(실제 카카오 연동 없음, 6.1).
import { supabase, supabaseConfigError } from './supabase'

// FastAPI 베이스 URL — repair.js 와 동일 키(VITE_API_BASE_URL). 미설정 시 로컬 기본값.
const API_BASE = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000'

// 건물 단위 알림톡 히스토리 — 정보 탭 벨(화면 4) → 화면 11. 최신 발송이 위로.
// 미리보기(화면 12)에 필요한 계약 데이터를 함께 내려받아 추가 조회를 피한다(OSoT).
// notifications → contracts(!inner, building_id 필터) → tenants(!inner, 세입자명).
export async function fetchBuildingNotifications(buildingId) {
  if (!supabase) throw new Error(supabaseConfigError)
  const { data, error } = await supabase
    .from('notifications')
    .select(
      `id, contract_id, type, title, body, scheduled_at, sent_at, status,
       contracts!inner ( id, unit_no, building_id, lease_type, monthly_rent,
         maintenance_fee, etc_fee1, etc_fee2, rent_vat, maintenance_vat,
         etc1_vat, etc2_vat, payment_day, payment_timing, contract_end, deposit,
         tenants!inner ( name ) )`,
    )
    .eq('contracts.building_id', buildingId)
    .order('sent_at', { ascending: false })
  if (error) throw new Error(`알림톡 히스토리 조회 실패: ${error.message}`)

  // 화면이 바로 쓰도록 계약·세입자명을 평탄화한다.
  return (data ?? []).map((n) => ({
    id: n.id,
    contract_id: n.contract_id,
    type: n.type,
    title: n.title,
    body: n.body,
    sent_at: n.sent_at,
    status: n.status,
    contract: n.contracts ?? null,
    tenantName: n.contracts?.tenants?.name ?? '',
  }))
}

// FastAPI 호출 공통 — 실패는 삼키지 않고 의미 있는 에러를 던진다(repair.js 패턴).
async function postJson(path, payload, failMsg) {
  let res
  try {
    res = await fetch(`${API_BASE}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
  } catch {
    throw new Error('알림톡 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.')
  }
  if (!res.ok) {
    let detail = ''
    try {
      const body = await res.json()
      detail = typeof body?.detail === 'string' ? body.detail : ''
    } catch {
      // 본문 파싱 실패는 무시하고 상태코드 기반 메시지로 대체.
    }
    throw new Error(detail || `${failMsg} (${res.status}).`)
  }
  return res.json()
}

// 미리보기·스케줄 생성(FastAPI 템플릿 치환).
export function requestNotificationPreview(payload) {
  return postJson('/api/notifications/preview', payload, '미리보기 생성에 실패했습니다')
}

// 발송(mock) — status='mock_sent' 기록. 실제 카카오 발송 없음(6.1).
export function sendNotificationMock(payload) {
  return postJson('/api/notifications/send', payload, '발송(mock)에 실패했습니다')
}
