import { createClient } from '@supabase/supabase-js'

// Supabase 직결 클라이언트 (CRUD·집계 View/RPC·Auth).
// 환경변수는 frontend/.env.local 에 설정 (.env.example 참고).
const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  // happy path만 두지 않는다 — 미설정 시 명확히 알린다.
  console.error(
    '[Butler] Supabase 환경변수가 없습니다. frontend/.env.local 에 ' +
      'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 를 설정하세요.',
  )
}

export const supabase = createClient(url ?? '', anonKey ?? '')
