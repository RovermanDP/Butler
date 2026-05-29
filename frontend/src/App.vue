<script setup>
import { ref, onMounted } from 'vue'
import { supabase, supabaseConfigError } from './lib/supabase'

// 기반 세션 검증 화면: Supabase 직결 + FastAPI 헬스체크가 동작하는지 확인한다.
// (실제 플로우 화면은 PRD 4.x 세션에서 구현)
const dbState = ref({ status: 'loading', message: '', buildings: [] })
const apiState = ref({ status: 'loading', message: '' })

async function checkSupabase() {
  // env 미설정 시 supabase 는 null — 화면이 깨지지 않게 에러 상태로 안내한다.
  if (!supabase) {
    dbState.value = { status: 'error', message: supabaseConfigError, buildings: [] }
    return
  }

  // buildings 와 집계 View(building_stats) 를 함께 조회해 연결·집계 동작 검증
  const { data: buildings, error } = await supabase
    .from('buildings')
    .select('id, name, address, unit_count, is_favorite')
    .order('name')

  if (error) {
    dbState.value = { status: 'error', message: error.message, buildings: [] }
    return
  }

  const { data: stats, error: statErr } = await supabase
    .from('building_stats')
    .select('building_id, occupancy_rate, rental_income, vacant_count')

  if (statErr) {
    dbState.value = { status: 'error', message: statErr.message, buildings }
    return
  }

  const statById = new Map(stats.map((s) => [s.building_id, s]))
  dbState.value = {
    status: 'ok',
    message: `건물 ${buildings.length}곳 · 집계 View 정상`,
    buildings: buildings.map((b) => ({ ...b, stat: statById.get(b.id) })),
  }
}

async function checkApi() {
  try {
    const res = await fetch('/api/health')
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const json = await res.json()
    apiState.value = { status: 'ok', message: json.service ?? 'ok' }
  } catch (e) {
    // 백엔드 미기동 시에도 화면은 깨지지 않게 명확한 메시지로 처리
    apiState.value = { status: 'error', message: e.message }
  }
}

function fmtWon(n) {
  return `${Number(n ?? 0).toLocaleString('ko-KR')} 원`
}

onMounted(() => {
  checkSupabase()
  checkApi()
})
</script>

<template>
  <main class="screen">
    <header class="head">
      <h1>Butler</h1>
      <p class="sub">기반 세션 연결 점검</p>
    </header>

    <section class="card">
      <div class="row">
        <span class="label">Supabase (DB·집계)</span>
        <span :class="['badge', dbState.status]">{{ dbState.status }}</span>
      </div>
      <p class="msg">{{ dbState.message }}</p>

      <ul v-if="dbState.buildings.length" class="list">
        <li v-for="b in dbState.buildings" :key="b.id">
          <div class="b-name">{{ b.is_favorite ? '★ ' : '' }}{{ b.name }}</div>
          <div class="b-meta">{{ b.address }} · {{ b.unit_count }}세대</div>
          <div v-if="b.stat" class="b-stat">
            입주율 {{ b.stat.occupancy_rate }}% · 공실 {{ b.stat.vacant_count }} ·
            임대수익 {{ fmtWon(b.stat.rental_income) }}
          </div>
        </li>
      </ul>
    </section>

    <section class="card">
      <div class="row">
        <span class="label">FastAPI (AI·알림톡)</span>
        <span :class="['badge', apiState.status]">{{ apiState.status }}</span>
      </div>
      <p class="msg">{{ apiState.message }}</p>
    </section>
  </main>
</template>

<style scoped>
.screen {
  max-width: 420px;
  margin: 0 auto;
  padding: 20px 16px 40px;
  min-height: 100vh;
}
.head h1 {
  margin: 0;
  font-size: 28px;
  color: var(--mint-deep);
}
.sub {
  margin: 4px 0 20px;
  color: var(--gray-5);
  font-size: 14px;
}
.card {
  border: 1px solid var(--gray-2);
  border-radius: var(--r-card);
  padding: 16px;
  margin-bottom: 14px;
}
.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.label {
  font-weight: 600;
}
.badge {
  font-size: 12px;
  padding: 3px 10px;
  border-radius: var(--r-tag);
  text-transform: uppercase;
}
.badge.ok {
  background: var(--mint-soft);
  color: var(--mint-deep);
}
.badge.error {
  background: var(--red-soft);
  color: var(--red);
}
.badge.loading {
  background: var(--gray-1);
  color: var(--gray-5);
}
.msg {
  margin: 8px 0 0;
  font-size: 13px;
  color: var(--gray-5);
  word-break: break-all;
}
.list {
  list-style: none;
  margin: 14px 0 0;
  padding: 0;
}
.list li {
  padding: 12px;
  border-radius: var(--r-tag);
  background: var(--gray-1);
  margin-bottom: 8px;
}
.b-name {
  font-weight: 600;
}
.b-meta {
  font-size: 12px;
  color: var(--gray-5);
  margin-top: 2px;
}
.b-stat {
  font-size: 12px;
  color: var(--mint-deep);
  margin-top: 6px;
}
</style>
