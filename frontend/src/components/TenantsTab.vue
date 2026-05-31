<script setup>
// 화면 6 — 건물 상세 · 세입자 탭 = 세입자 '목록' (PRD 4.2 B-3).
// 기존 인라인 카드(메모·계약·금액)는 세입자 상세(TenantDetail.vue)로 이전했다.
// 여기는 호실별 목록 + 검색 + 전체▽ 상태필터(클라이언트) + 연동하기(teaser)만 담당한다.
//   · 행 탭 → open-tenant(상위 BuildingDetail 이 세입자 상세 오버레이를 연다).
//   · 검색: 이름·호실 substring(클라이언트). 상태필터: primary.status(계약중/만료/종료).
// 표시만 담당(데이터 in / 이벤트 out). phone 보유 세입자만 내려오므로 채움 데이터는 이미 걸러짐.
import { ref, computed } from 'vue'
import { formatShortDate } from '../lib/contractDates'

const props = defineProps({
  tenants: { type: Array, default: () => [] },
  buildingName: { type: String, default: '' },
})

const emit = defineEmits(['open-tenant', 'teaser'])

// ── 검색 · 상태 필터(클라이언트) ─────────────────────────
const query = ref('')
const STATUS_OPTS = ['전체', '계약중', '만료', '종료']
const statusFilter = ref('전체')
const filterOpen = ref(false)

function pickFilter(s) {
  statusFilter.value = s
  filterOpen.value = false
}

const visible = computed(() => {
  const q = query.value.trim().toLowerCase()
  return props.tenants.filter((t) => {
    if (statusFilter.value !== '전체' && t.primary?.status !== statusFilter.value) return false
    if (!q) return true
    const hay = `${t.name ?? ''} ${t.primary?.unit_no ?? ''}`.toLowerCase()
    return hay.includes(q)
  })
})

// 신규 태그: 계약 시작일이 당월이면 '신규'(building_stats new_this_month 와 동일 기준).
const now = new Date()
const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
function isNew(t) {
  return String(t.primary?.contract_start ?? '').slice(0, 7) === ym
}
</script>

<template>
  <div class="tenants">
    <!-- 검색바 -->
    <label class="tn-search">
      <input v-model="query" type="text" placeholder="세입자를 검색해보세요" />
      <span class="search-inline" aria-hidden="true">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <circle cx="11" cy="11" r="6.5" /><path d="M16 16L21 21" />
        </svg>
      </span>
    </label>

    <!-- 전체▽ 상태필터 · 연동하기(teaser) -->
    <div class="tn-listhead">
      <span class="tn-filter" @click="filterOpen = !filterOpen">
        {{ statusFilter }} ⌄
        <div v-if="filterOpen" class="tn-menu">
          <button
            v-for="s in STATUS_OPTS"
            :key="s"
            type="button"
            :class="{ on: statusFilter === s }"
            @click.stop="pickFilter(s)"
          >
            {{ s }}
          </button>
        </div>
      </span>
      <button class="tn-link" type="button" @click="emit('teaser', '연동하기')">☑ 연동하기</button>
    </div>

    <!-- 목록 -->
    <p v-if="!tenants.length" class="empty">등록된 세입자가 없습니다.</p>
    <p v-else-if="!visible.length" class="empty">검색 결과가 없습니다.</p>

    <div
      v-for="t in visible"
      :key="t.id"
      class="tn-row"
      role="button"
      tabindex="0"
      @click="emit('open-tenant', t)"
      @keydown.enter="emit('open-tenant', t)"
    >
      <span class="unit">{{ t.primary.unit_no }}</span>
      <span class="info">
        <b class="nm">{{ t.name }}</b>
        <span class="meta">
          <span class="term">
            {{ formatShortDate(t.primary.contract_start) }}~{{ formatShortDate(t.primary.contract_end) }}
          </span>
          <span class="tag" :class="t.primary.lease_type === '전세' ? 'js' : 'wm'">
            {{ t.primary.lease_type }}
          </span>
          <span v-if="isNew(t)" class="tag new">신규</span>
        </span>
      </span>
      <span class="arr">›</span>
    </div>
  </div>
</template>

<style scoped>
.empty {
  text-align: center;
  color: var(--gray-4);
  font-size: 12.5px;
  padding: 40px 0;
}
/* 검색바 */
.tn-search {
  background: var(--gray-1);
  border-radius: 10px;
  padding: 10px 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.tn-search input {
  flex: 1;
  min-width: 0;
  border: none;
  background: none;
  font-family: inherit;
  font-size: 12.5px;
  font-weight: 500;
  color: var(--ink);
}
.tn-search input::placeholder {
  color: var(--ink-mute);
}
.tn-search input:focus {
  outline: none;
}
.tn-search .search-inline svg {
  width: 18px;
  height: 18px;
  fill: none;
  stroke: var(--ink-mute);
  stroke-width: 1.8;
  stroke-linecap: round;
}
/* 필터 헤더 */
.tn-listhead {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 14px 0 6px;
}
.tn-filter {
  font-size: 12.5px;
  font-weight: 700;
  color: var(--ink-soft);
  position: relative;
  cursor: pointer;
  user-select: none;
}
.tn-menu {
  position: absolute;
  top: 100%;
  left: 0;
  margin-top: 6px;
  background: #fff;
  border: 1px solid var(--line);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(31, 31, 36, 0.08);
  padding: 4px;
  z-index: 5;
  min-width: 90px;
}
.tn-menu button {
  display: block;
  width: 100%;
  text-align: left;
  border: none;
  background: none;
  font-family: inherit;
  font-size: 11.5px;
  font-weight: 700;
  color: var(--ink-soft);
  padding: 8px 10px;
  border-radius: 7px;
  cursor: pointer;
}
.tn-menu button.on {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.tn-link {
  font-size: 11px;
  font-weight: 800;
  color: var(--accent-deep);
  background: var(--accent-soft);
  padding: 7px 12px;
  border-radius: 10px;
  border: none;
  font-family: inherit;
  cursor: pointer;
}
/* 호실별 목록 행 */
.tn-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 13px 2px;
  border-top: 1px solid var(--line);
  cursor: pointer;
}
.tn-row .unit {
  flex: 0 0 auto;
  width: 60px;
  font-size: 11.5px;
  font-weight: 700;
  color: var(--ink-soft);
  line-height: 1.3;
}
.tn-row .info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.tn-row .info .nm {
  font-size: 14px;
  font-weight: 800;
  color: var(--ink);
}
.tn-row .info .meta {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}
.tn-row .info .term {
  font-size: 10.5px;
  color: var(--ink-mute);
  font-weight: 600;
}
.tn-row .arr {
  flex: 0 0 auto;
  color: var(--gray-3);
  font-size: 15px;
}
.tag {
  font-size: 9.5px;
  font-weight: 800;
  padding: 2px 7px;
  border-radius: 7px;
}
.tag.wm {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.tag.js {
  background: var(--warn-soft);
  color: var(--warn);
}
.tag.new {
  background: var(--ok-soft);
  color: var(--ok);
}
</style>
