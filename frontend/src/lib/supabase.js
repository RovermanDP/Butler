import { createClient } from '@supabase/supabase-js'

// Supabase 직결 클라이언트 (CRUD·집계 View/RPC·Auth).
// 환경변수는 frontend/.env.local 에 설정 (.env.example 참고).
const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// happy path만 두지 않는다 — 미설정 시 createClient는 import 단계에서 throw 하므로
// (앱 부팅이 깨진다) 클라이언트를 만들지 않고 null + 사유 메시지를 내보내,
// 화면의 에러 상태(App.vue dbState)로 처리한다.
export const supabaseConfigError = !url || !anonKey
  ? 'Supabase 환경변수가 없습니다. frontend/.env.local 에 VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 를 설정하세요.'
  : ''

if (supabaseConfigError) console.error('[Butler]', supabaseConfigError)

export const supabase = supabaseConfigError ? null : createClient(url, anonKey)
