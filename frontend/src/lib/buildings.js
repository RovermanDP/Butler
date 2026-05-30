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
