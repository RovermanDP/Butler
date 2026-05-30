<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { fetchBuildings } from './lib/buildings'
import EmptyState from './views/EmptyState.vue'
import BuildingRegister from './views/BuildingRegister.vue'
import BuildingList from './views/BuildingList.vue'
import BuildingManageSheet from './components/BuildingManageSheet.vue'

// Flow A — 온보딩·건물 등록 (PRD 4.1).
// 빈 상태 → 건물 관리 모달 → (세입자 차단 분기) → 건물 등록 → 목록(화면 5) 진입.
// 가드(세입자 등록 차단)는 별도 API 없이 buildings.length === 0 으로 프론트에서 판단.
//
// 화면 라우팅 계약(Flow B 가 이어붙일 지점):
//   'loading' 시작 → 조회 후 건물 있으면 'list', 없으면 'empty'.
//   'list' 의 건물 카드 클릭 → (Flow B) 'detail' 상태로 단일 건물 4탭 진입 예정.
//   buildings 배열이 목록/가드/카운트의 단일 소스.
const screen = ref('loading') // 'loading' | 'empty' | 'list' | 'register' | 'error'
const buildings = ref([])
const loadError = ref('')

const sheetOpen = ref(false)

// 등록 직후 목록 상단 성공 배너
const flash = ref('')
let flashTimer = null

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
    buildings.value = await fetchBuildings()
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
  if (buildings.value.length === 0) {
    // 화면 2a — 건물 없이 세입자 등록 차단
    tenantTapped.value = true
    showToast('❗ 등록된 건물이 없습니다. 건물을 등록해주세요', 'error')
    return
  }
  // 건물이 있는 경우: 세입자 등록은 Flow A 범위 밖 → 안내만 한다.
  showToast('세입자 등록은 다음 단계에서 제공됩니다', 'info')
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
    <BuildingList v-else-if="screen === 'list'" :buildings="buildings" :flash="flash" />

    <BuildingManageSheet
      :open="sheetOpen"
      :tenant-tapped="tenantTapped"
      :toast="toast"
      :toast-kind="toastKind"
      @close="closeSheet"
      @select-building="onSelectBuilding"
      @select-tenant="onSelectTenant"
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
</style>
