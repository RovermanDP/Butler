import { supabase, supabaseConfigError } from './supabase'

// 건물 데이터 접근 (Supabase 직결).
// CLAUDE.md 책임 분담: 단순 CRUD·집계는 FastAPI를 거치지 않고 Supabase로 직결한다.
// 빈 상태 가드(건물 수)와 등록 폼이 함께 쓰므로 한 곳(OSoT)에 모은다.

// 건물 유형 선택지 — 등록 폼 select 의 단일 진실 공급원.
export const BUILDING_TYPES = [
  '다세대주택',
  '다가구주택',
  '아파트',
  '오피스텔',
  '단독주택',
  '상가/근린생활시설',
]

// 건물 목록. 등록 완료 후 첫 진입 화면(화면 5)·앱 시작 라우팅·세입자 차단 가드의
// 단일 소스다. 건물 수가 필요한 곳은 별도 count 조회 없이 배열 length 로 파생한다(OSoT).
export async function fetchBuildings() {
  if (!supabase) throw new Error(supabaseConfigError)
  const { data, error } = await supabase
    .from('buildings')
    .select('id, name, address, unit_count, building_type, account_info, is_favorite, created_at')
    .order('created_at', { ascending: false })
  if (error) throw new Error(error.message)
  return data ?? []
}

// 건물별 집계 지표 (입주율·세대구성·보증금·임대수익·이달 신규/만료 + 미납).
// PRD 3장: 집계는 컬럼이 아니라 View 로 계산 → building_stats + unpaid_stats 를 합쳐
// building_id 로 키잉한 맵으로 반환한다(목록 카드·정보 탭 공용 소스).
// buildings 와 별도 소스라 화면(목록/정보 탭)에서 building_id 로 합류시킨다(SRP).
export async function fetchBuildingStats() {
  if (!supabase) throw new Error(supabaseConfigError)
  const [statsRes, unpaidRes] = await Promise.all([
    supabase.from('building_stats').select('*'),
    supabase.from('unpaid_stats').select('*'),
  ])
  if (statsRes.error) throw new Error(statsRes.error.message)
  if (unpaidRes.error) throw new Error(unpaidRes.error.message)

  // 미납은 미납이 있는 건물만 행이 생기므로(LEFT 아님) 맵으로 먼저 모은다.
  const unpaid = {}
  for (const u of unpaidRes.data ?? []) unpaid[u.building_id] = u

  const map = {}
  for (const s of statsRes.data ?? []) {
    map[s.building_id] = {
      ...s,
      unpaid_count: unpaid[s.building_id]?.unpaid_count ?? 0,
      unpaid_amount: unpaid[s.building_id]?.unpaid_amount ?? 0,
    }
  }
  return map
}

// 건물 등록. payload 는 buildings 컬럼(snake_case) 그대로.
// 등록 직후 목록/완료 화면에서 쓸 최소 필드만 반환한다.
export async function insertBuilding(payload) {
  if (!supabase) throw new Error(supabaseConfigError)
  const { data, error } = await supabase
    .from('buildings')
    .insert(payload)
    .select('id, name, address, unit_count, building_type, account_info')
    .single()
  if (error) throw new Error(error.message)
  return data
}
