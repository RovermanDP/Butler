<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { fetchBuildings, fetchBuildingStats } from './lib/buildings'
import EmptyState from './views/EmptyState.vue'
import BuildingRegister from './views/BuildingRegister.vue'
import BuildingList from './views/BuildingList.vue'
import BuildingDetail from './views/BuildingDetail.vue'
import TenantRegister from './views/TenantRegister.vue'
import BuildingManageSheet from './components/BuildingManageSheet.vue'
import TenantMethodSheet from './components/TenantMethodSheet.vue'

// Flow A — 온보딩·건물 등록 (PRD 4.1) + Flow B-1·B-2 — 목록·정보 탭 (PRD 4.2).
// 빈 상태 → 건물 관리 모달 → (세입자 차단 분기) → 건물 등록 → 목록(화면 5).
//   목록 카드 탭 → 단일 건물 정보 탭(화면 4). 정보 탭 FAB(+) → '건물 관리'(세입자 등록 활성, 화면 9).
// 가드(세입자 등록 활성/차단)는 별도 API 없이 buildings.length 으로 프론트에서 판단.
//
// 화면 라우팅: 'loading' → 조회 후 건물 있으면 'list', 없으면 'empty'.
//   'list' 카드 클릭 → 'detail'(선택 건물 정보 탭). buildings 배열이 목록/가드/카운트 단일 소스.
const screen = ref('loading') // 'loading' | 'empty' | 'list' | 'detail' | 'register' | 'tenant-register' | 'error'
const buildings = ref([])
const stats = ref({}) // building_id → 집계 지표(목록 카드·정보 탭 공용)
const selectedBuilding = ref(null) // 정보 탭(화면 4) 대상 건물
const loadError = ref('')

// 세입자 등록 활성 여부(화면 2 vs 화면 9 분기). 건물이 1개 이상이면 활성.
const tenantEnabled = computed(() => buildings.value.length > 0)

const sheetOpen = ref(false)

// Flow E — 세입자 등록 방법 선택 시트(화면 10). '건물 관리' 시트에서 세입자 등록 활성 탭 시 등장.
const methodSheetOpen = ref(false)

// 등록 직후 목록 상단 성공 배너
const flash = ref('')
let flashTimer = null

// 정보 탭 알림(벨) 진입점 안내 — 화면 레벨 토스트(시트 토스트와 별개)
const notice = ref('')
let noticeTimer = null

// 모달 토스트/강조 상태 (화면 2a)
const tenantTapped = ref(false)
const toast = ref('')
const toastKind = ref('error')
let toastTimer = null

function showToast(message, kind = 'error') {
  toast.value = message
  toastKind.value = kind
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    toast.value = ''
    tenantTapped.value = false
  }, 2800)
}

// 건물 목록 로드 → 라우팅 결정. 실패는 삼키지 않고 'error' 화면으로 노출(재시도 제공).
async function loadBuildings() {
  screen.value = 'loading'
  loadError.value = ''
  try {
    // 건물 목록과 집계 지표를 병렬 조회(둘 다 Supabase 직결).
    const [list, statMap] = await Promise.all([fetchBuildings(), fetchBuildingStats()])
    buildings.value = list
    stats.value = statMap
    screen.value = buildings.value.length ? 'list' : 'empty'
  } catch (e) {
    loadError.value = e.message
    screen.value = 'error'
  }
}

onMounted(loadBuildings)
onUnmounted(() => {
  clearTimeout(toastTimer)
  clearTimeout(flashTimer)
  clearTimeout(noticeTimer)
})

function openSheet() {
  sheetOpen.value = true
}

function closeSheet() {
  sheetOpen.value = false
  toast.value = ''
  tenantTapped.value = false
  clearTimeout(toastTimer)
}

function onSelectBuilding() {
  sheetOpen.value = false
  toast.value = ''
  tenantTapped.value = false
  screen.value = 'register'
}

function onSelectTenant() {
  if (!tenantEnabled.value) {
    // 화면 2a — 건물 없이 세입자 등록 차단
    tenantTapped.value = true
    showToast('❗ 등록된 건물이 없습니다. 건물을 등록해주세요', 'error')
    return
  }
  // 화면 9 → 화면 10 — 세입자 등록 활성(Flow E 진입점). 방법 선택 시트를 연다.
  sheetOpen.value = false
  tenantTapped.value = false
  toast.value = ''
  clearTimeout(toastTimer)
  methodSheetOpen.value = true
}

// 화면 10 — 직접 등록하기 → Step1 화면 진입. (계약서 추천은 teaser, 6.3 범위 외)
function onSelectDirect() {
  methodSheetOpen.value = false
  screen.value = 'tenant-register'
}

function onSelectRecommend() {
  methodSheetOpen.value = false
  notice.value = '임대차 계약서 추천(자동 추출)은 추후 제공 예정입니다'
  clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => (notice.value = ''), 2600)
}

// Step1 [뒤로]/상단 ‹ — 진입 직전 화면(정보 탭 또는 목록)으로 복귀.
function backFromTenant() {
  screen.value = selectedBuilding.value ? 'detail' : 'list'
}

// 목록 카드 탭 → 단일 건물 정보 탭(화면 4) 진입.
function openDetail(building) {
  selectedBuilding.value = building
  screen.value = 'detail'
}

// 정보 탭에서 ‹ 뒤로 → 목록 복귀.
function backFromDetail() {
  selectedBuilding.value = null
  screen.value = 'list'
}

// 정보 탭 알림(벨) → Flow D(알림톡 히스토리) 진입점. 라우팅은 App 이 소유한다.
// Flow D 화면 구현 시 이 핸들러만 화면 전환으로 교체하면 된다(진입점 계약 고정):
//   selectedBuilding.value = building; screen.value = 'notifications'
// Flow D 미구현인 현재는 진입점이 살아 있음을 화면 레벨 안내로 알린다(시트 토스트는 시트 전용).
function openNotifications(building) {
  notice.value = `${building.name} · 알림톡 내역은 다음 단계(Flow D)에서 제공됩니다`
  clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => (notice.value = ''), 2600)
}

function onRegistered(building) {
  buildings.value.unshift(building) // 최신 등록이 목록 상단
  closeSheet()
  screen.value = 'list' // 등록 성공 → 목록(화면 5) 자동 진입
  flash.value = '건물이 등록되었습니다'
  clearTimeout(flashTimer)
  flashTimer = setTimeout(() => (flash.value = ''), 2800)
}

function backToList() {
  // 등록 화면에서 뒤로: 건물이 있으면 목록, 없으면 빈 상태로 복귀
  screen.value = buildings.value.length ? 'list' : 'empty'
}
</script>

<template>
  <div class="app">
    <!-- 로딩: 건물 조회 중 -->
    <div v-if="screen === 'loading'" class="state">
      <div class="spinner" aria-hidden="true"></div>
      <p>불러오는 중…</p>
    </div>

    <!-- 에러: 조회 실패(네트워크/환경) — '건물 없음'으로 오인시키지 않고 재시도 제공 -->
    <div v-else-if="screen === 'error'" class="state">
      <p class="emoji">😵</p>
      <p class="title">건물 정보를 불러오지 못했습니다</p>
      <p class="detail">{{ loadError }}</p>
      <button class="retry" type="button" @click="loadBuildings">다시 시도</button>
    </div>

    <EmptyState v-else-if="screen === 'empty'" @open-sheet="openSheet" />
    <BuildingRegister
      v-else-if="screen === 'register'"
      @back="backToList"
      @submitted="onRegistered"
    />
    <BuildingList
      v-else-if="screen === 'list'"
      :buildings="buildings"
      :stats="stats"
      :flash="flash"
      @select="openDetail"
    />
    <BuildingDetail
      v-else-if="screen === 'detail' && selectedBuilding"
      :building="selectedBuilding"
      :stat="stats[selectedBuilding.id] ?? null"
      @back="backFromDetail"
      @open-sheet="openSheet"
      @open-notifications="openNotifications"
    />
    <TenantRegister
      v-else-if="screen === 'tenant-register'"
      :buildings="buildings"
      :preselect-building-id="selectedBuilding?.id ?? ''"
      @back="backFromTenant"
    />

    <BuildingManageSheet
      :open="sheetOpen"
      :tenant-enabled="tenantEnabled"
      :tenant-tapped="tenantTapped"
      :toast="toast"
      :toast-kind="toastKind"
      @close="closeSheet"
      @select-building="onSelectBuilding"
      @select-tenant="onSelectTenant"
    />

    <!-- 화면 10 — 세입자 등록 방법 선택(직접 등록 / 계약서 추천 teaser) -->
    <TenantMethodSheet
      :open="methodSheetOpen"
      @close="methodSheetOpen = false"
      @select-direct="onSelectDirect"
      @select-recommend="onSelectRecommend"
    />

    <!-- 목록 화면에서도 FAB 로 추가 등록 가능 -->
    <button
      v-if="screen === 'list'"
      class="fab"
      type="button"
      aria-label="건물·세입자 등록"
      @click="openSheet"
    >
      +
    </button>

    <!-- 화면 레벨 안내 토스트(예: 정보 탭 알림 진입점). 시트 토스트와 독립. -->
    <Transition name="notice">
      <div v-if="notice" class="app-notice">{{ notice }}</div>
    </Transition>
  </div>
</template>

<style scoped>
/* 모바일 세로 화면. 폰 목업 프레임은 쓰지 않고 화면 내부 구성만 재현한다(CLAUDE.md). */
.app {
  position: relative;
  max-width: 420px;
  height: 100dvh;
  margin: 0 auto;
  background: #fff;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* 로딩·에러 공통 중앙 정렬 상태 화면 */
.state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 24px;
  text-align: center;
  color: var(--gray-5);
}
.state .emoji {
  font-size: 34px;
}
.state .title {
  font-size: 15px;
  font-weight: 800;
  color: var(--ink);
}
.state .detail {
  font-size: 12px;
  color: var(--gray-4);
  word-break: break-all;
  max-width: 280px;
}
.state .retry {
  margin-top: 6px;
  border: none;
  background: var(--accent);
  color: #fff;
  border-radius: var(--r-button);
  padding: 11px 22px;
  font-weight: 800;
  font-size: 13px;
  font-family: inherit;
  cursor: pointer;
}
.spinner {
  width: 30px;
  height: 30px;
  border-radius: 50%;
  border: 3px solid var(--gray-2);
  border-top-color: var(--accent);
  animation: spin 0.8s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

/* 목록 화면 추가 등록용 FAB (빈 상태 FAB 와 동일 스펙, 펄스는 없음) */
.fab {
  position: absolute;
  right: 15px;
  bottom: 64px;
  width: 46px;
  height: 46px;
  border: none;
  border-radius: 50%;
  background: var(--accent);
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 22px;
  cursor: pointer;
  box-shadow: 0 10px 22px -8px rgba(58, 110, 165, 0.8);
  z-index: 6;
}

/* 화면 레벨 안내 토스트 — 하단 네비 위에 띄운다. */
.app-notice {
  position: absolute;
  left: 16px;
  right: 16px;
  bottom: 64px;
  z-index: 9;
  background: var(--accent-soft);
  color: var(--accent-deep);
  border-radius: 12px;
  padding: 12px 14px;
  font-size: 12.5px;
  font-weight: 700;
  text-align: center;
}
.notice-enter-active,
.notice-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.notice-enter-from,
.notice-leave-to {
  opacity: 0;
  transform: translateY(8px);
}
</style>
