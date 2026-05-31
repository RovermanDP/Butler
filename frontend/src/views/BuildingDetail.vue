<script setup>
// 화면 4 — 단일 건물 상세 · 정보 탭 (PRD 4.2 B-2).
// 목록 카드(화면 5) 탭으로 진입. 입주율 도넛·세대구성·이달 신규/만료·총 보증금·임대수익은
// building_stats View 산출값(stat prop). 상단 좌측 ‹ 뒤로, 우측 알림(벨) 아이콘.
//
// 4개 탭(정보·세입자·수납·지출) + 좌우 스와이프 (PRD 4.2 B-2~B-5).
//  · 정보 탭: stat prop(building_stats View) 사용.
//  · 세입자·수납·지출 탭: lib/detail 에서 건물별 tenants/contracts/payments/expenses 를 조회해 표시.
//    → Flow E 등록분(세입자·계약·회차)이 세입자·수납 탭에 그대로 반영된다.
//  · 우측 알림(벨) → Flow D 진입점(open-notifications). 계약 연장/종료·AI 분담은 미구현 별도 플로우라
//    teaser/open-repair 이벤트만 올린다(라우팅·안내는 상위 App 이 소유 — 벨과 동일 패턴).
//  · 우하단 고정 FAB(+) → '건물 관리' 시트(화면 9). 정보·세입자 탭에서만 노출(PRD). open-sheet 로 위임.
import { ref, computed, onMounted, watch } from 'vue'
import { formatWon, formatEok } from '../lib/format'
import { fetchTenantsWithPayments, fetchBuildingExpenses } from '../lib/detail'
import TenantsTab from '../components/TenantsTab.vue'
import PaymentsTab from '../components/PaymentsTab.vue'
import ExpensesTab from '../components/ExpensesTab.vue'
import TenantDetail from './TenantDetail.vue'

const props = defineProps({
  building: { type: Object, required: true },
  // building_stats 산출값. 등록 직후(집계 미반영) 건물은 null 일 수 있어 기본값으로 방어.
  stat: { type: Object, default: null },
})

const emit = defineEmits(['back', 'open-sheet', 'open-notifications', 'teaser', 'open-repair'])

// 집계 미반영 시에도 화면이 깨지지 않도록 unit_count 기준 기본값을 채운다.
const s = computed(
  () =>
    props.stat ?? {
      occupancy_rate: 0,
      occupied_units: 0,
      unit_count: props.building.unit_count,
      wolse_count: 0,
      jeonse_count: 0,
      vacant_count: props.building.unit_count,
      deposit_total: 0,
      rental_income: 0,
      new_this_month: 0,
      expiring_this_month: 0,
    },
)

const donutStyle = computed(() => {
  const pct = Number(s.value.occupancy_rate) || 0
  return { background: `conic-gradient(var(--accent) 0 ${pct}%, var(--gray-2) 0)` }
})

// ── 탭 상태 ──────────────────────────────────────────────
const TABS = ['정보', '세입자', '수납', '지출']
const activeTab = ref(0)
// FAB(+)는 정보·세입자 탭에서만 고정 노출(PRD: "정보 탭·세입자 탭 우하단 고정 FAB").
const showFab = computed(() => activeTab.value === 0 || activeTab.value === 1)

function goTab(i) {
  activeTab.value = i
}

// 좌우 스와이프: |Δx|가 임계값 이상이고 가로 우세일 때만 인접 탭으로 이동(세로 스크롤 방해 금지).
let tsX = 0
let tsY = 0
function onTouchStart(e) {
  const t = e.changedTouches[0]
  tsX = t.clientX
  tsY = t.clientY
}
function onTouchEnd(e) {
  const t = e.changedTouches[0]
  const dx = t.clientX - tsX
  const dy = t.clientY - tsY
  if (Math.abs(dx) < 40 || Math.abs(dx) <= Math.abs(dy)) return
  if (dx < 0) activeTab.value = Math.min(TABS.length - 1, activeTab.value + 1)
  else activeTab.value = Math.max(0, activeTab.value - 1)
}

// ── 상세 데이터(세입자·수납·지출) ────────────────────────
// 진입(onMounted) 시 1회 병렬 조회. 건물 전환(watch) 시 재조회. Flow E 등록 후 복귀는
// 컴포넌트 재마운트(onMounted)로 자동 반영된다. 해피패스만 두지 않고 로딩/에러 상태를 제공한다.
const tenants = ref([])
const expenses = ref([])
const loading = ref(false)
const loadErr = ref('')

async function loadDetail() {
  loading.value = true
  loadErr.value = ''
  try {
    const [t, e] = await Promise.all([
      fetchTenantsWithPayments(props.building.id),
      fetchBuildingExpenses(props.building.id),
    ])
    tenants.value = t
    expenses.value = e
  } catch (err) {
    loadErr.value = err.message
  } finally {
    loading.value = false
  }
}

onMounted(loadDetail)
watch(
  () => props.building.id,
  () => {
    activeTab.value = 0
    detailTenant.value = null // 건물 전환 시 열린 상세 닫기
    loadDetail()
  },
)

// ── 세입자 상세 오버레이(화면 6a/6b/6c + 6d) ─────────────
// 세입자 목록(화면 6) 행 탭 또는 수납 탭(화면 7) 세입자 행 탭으로 진입.
// 이 컴포넌트가 이미 조회해 둔 tenants(계약·회차·알림톡)를 그대로 넘겨 재조회를 피한다(OSoT).
// 4탭 상태/스크롤을 보존하려고 App 레벨 화면이 아니라 여기서 오버레이로 소유한다.
const detailTenant = ref(null) // 열린 세입자(상세) | null
const detailTab = ref('정보') // 진입 시 초기 sub-tab('정보' | '수납')

function openTenantDetail(tenant, tab = '정보') {
  detailTenant.value = tenant
  detailTab.value = tab
}
function closeTenantDetail() {
  detailTenant.value = null
}
// 삭제 완료 → 상세 닫고 목록 재조회(삭제된 세입자 제거 반영).
function onTenantDeleted() {
  detailTenant.value = null
  loadDetail()
}
</script>

<template>
  <!-- 세입자 상세(6a/6b/6c) 오버레이: 열려 있으면 4탭 대신 상세를 전체 화면으로 보여준다. -->
  <TenantDetail
    v-if="detailTenant"
    :tenant="detailTenant"
    :building-name="building.name"
    :initial-tab="detailTab"
    @back="closeTenantDetail"
    @teaser="(label) => emit('teaser', label)"
    @deleted="onTenantDeleted"
  />

  <div v-show="!detailTenant" class="scr">
    <div class="tbar">
      <button class="ico back" type="button" aria-label="뒤로" @click="$emit('back')">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M15 18L9 12L15 6" /></svg>
      </button>
      <span class="ttl">{{ building.name }}</span>
      <button class="ico bell" type="button" aria-label="알림톡 내역" @click="$emit('open-notifications', building)">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 17H9C7.34315 17 6 15.6569 6 14V10.5C6 7.46243 8.46243 5 11.5 5H12.5C15.5376 5 18 7.46243 18 10.5V14C18 15.6569 16.6569 17 15 17Z" />
          <path d="M4.5 17H19.5" />
          <path d="M10 20C10.5 20.6667 11.1667 21 12 21C12.8333 21 13.5 20.6667 14 20" />
        </svg>
      </button>
    </div>

    <div class="month"><span>◀</span>2026년 5월<span>▶</span></div>

    <!-- 4개 탭: 클릭 또는 좌우 스와이프로 전환(정보 ↔ 세입자 ↔ 수납 ↔ 지출). -->
    <div class="tabs">
      <div
        v-for="(t, i) in TABS"
        :key="t"
        :class="{ on: activeTab === i }"
        @click="goTab(i)"
      >
        {{ t }}
      </div>
    </div>

    <div class="body" @touchstart.passive="onTouchStart" @touchend.passive="onTouchEnd">
      <!-- 정보 탭 -->
      <template v-if="activeTab === 0">
        <div class="sub-h">임대 현황 <span class="more">({{ s.occupied_units }}/{{ s.unit_count }})</span></div>

        <div class="donut-wrap">
          <div class="donut" :style="donutStyle">
            <div class="v"><b>{{ s.occupancy_rate }}%</b><small>입주율</small></div>
          </div>
          <div class="legend">
            <div class="row"><span class="l"><i class="w"></i>월세 세대</span><b>{{ s.wolse_count }}</b></div>
            <div class="row"><span class="l"><i class="j"></i>전세 세대</span><b>{{ s.jeonse_count }}</b></div>
            <div class="row"><span class="l"><i class="g"></i>공실</span><b>{{ s.vacant_count }}</b></div>
          </div>
        </div>

        <div class="mini2">
          <div class="chip"><span class="k">이달의 신규 ›</span><b>{{ s.new_this_month }}</b></div>
          <div class="chip"><span class="k">이달의 만료 ›</span><b>{{ s.expiring_this_month }}</b></div>
        </div>

        <div class="sumbox">
          <div class="row"><span class="k">총 보증금</span><span class="v">{{ formatEok(s.deposit_total) }}</span></div>
          <div class="row"><span class="k">임대수익</span><span class="v">{{ formatWon(s.rental_income) }}</span></div>
        </div>
      </template>

      <!-- 세입자·수납·지출 탭: 공통 로딩/에러 가드 후 각 탭 렌더 -->
      <template v-else>
        <p v-if="loading" class="tabstate">불러오는 중…</p>
        <div v-else-if="loadErr" class="tabstate err">
          <p>{{ loadErr }}</p>
          <button type="button" @click="loadDetail">다시 시도</button>
        </div>
        <TenantsTab
          v-else-if="activeTab === 1"
          :tenants="tenants"
          :building-name="building.name"
          @open-tenant="(t) => openTenantDetail(t, '정보')"
          @teaser="(label) => emit('teaser', label)"
        />
        <PaymentsTab
          v-else-if="activeTab === 2"
          :tenants="tenants"
          :building-name="building.name"
          @open-tenant="(t) => openTenantDetail(t, '수납')"
          @reload="loadDetail"
        />
        <ExpensesTab
          v-else-if="activeTab === 3"
          :expenses="expenses"
          @open-repair="(e) => $emit('open-repair', e)"
        />
      </template>
    </div>

    <!-- 고정 FAB(+): .body 의 형제로 .scr 안에 둠 → 본문 스크롤과 무관하게 우하단 고정(PRD). 정보·세입자 탭만. -->
    <button v-if="showFab" class="fab" type="button" aria-label="건물·세입자 등록" @click="$emit('open-sheet')">+</button>

    <nav class="bnav">
      <div class="on">
        <span class="ic" aria-hidden="true">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M4.5 20V8.5C4.5 7.95 4.95 7.5 5.5 7.5H10.5C11.05 7.5 11.5 7.95 11.5 8.5V20" />
            <path d="M12.5 20V4.5C12.5 3.95 12.95 3.5 13.5 3.5H18.5C19.05 3.5 19.5 3.95 19.5 4.5V20" />
            <path d="M8 10.5H8.01" /><path d="M8 13.5H8.01" /><path d="M16 7.5H16.01" />
            <path d="M16 10.5H16.01" /><path d="M16 13.5H16.01" /><path d="M3.5 20.5H20.5" />
          </svg>
        </span>
        건물관리
      </div>
      <div>
        <span class="ic" aria-hidden="true">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <circle cx="6" cy="12" r="1.5" /><circle cx="12" cy="12" r="1.5" />
            <circle cx="18" cy="12" r="1.5" />
          </svg>
        </span>
        더보기
      </div>
    </nav>
  </div>
</template>

<style scoped>
.scr {
  flex: 1;
  display: flex;
  flex-direction: column;
  color: var(--ink);
  overflow: hidden;
  position: relative;
}
.tbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 12px 4px;
  gap: 8px;
}
.tbar .ttl {
  font-size: 13.5px;
  font-weight: 800;
  flex: 1;
  text-align: center;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.tbar .ico {
  border: none;
  background: none;
  padding: 0;
  width: 24px;
  height: 24px;
  flex: 0 0 auto;
  color: var(--ink);
  cursor: pointer;
}
.tbar .ico svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.tbar .bell {
  color: var(--gray-6);
}
.month {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 14px;
  font-size: 14px;
  font-weight: 800;
  color: var(--ink);
  padding: 6px 0 8px;
}
.month span {
  color: var(--gray-4);
  font-size: 12px;
}
.tabs {
  display: flex;
  gap: 10px;
  padding: 0 15px;
  border-bottom: 1px solid var(--gray-2);
}
.tabs div {
  font-size: 12.5px;
  font-weight: 700;
  color: var(--gray-4);
  padding: 8px 0 9px;
  position: relative;
}
.tabs div.on {
  color: var(--ink);
}
.tabs div.on::after {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  bottom: -1px;
  height: 2.5px;
  background: var(--ink);
  border-radius: 3px;
}
.body {
  flex: 1;
  overflow-y: auto;
  padding: 4px 15px 14px;
}
/* 세입자·수납·지출 탭 로딩/에러 상태(해피패스만 두지 않기). */
.tabstate {
  text-align: center;
  color: var(--gray-4);
  font-size: 12.5px;
  padding: 44px 0;
}
.tabstate.err {
  color: var(--danger);
}
.tabstate.err button {
  margin-top: 10px;
  border: none;
  background: var(--accent);
  color: #fff;
  border-radius: var(--r-button);
  padding: 9px 18px;
  font-weight: 800;
  font-size: 12px;
  font-family: inherit;
  cursor: pointer;
}
.sub-h {
  font-size: 14px;
  font-weight: 800;
  margin: 16px 0 8px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.sub-h .more {
  font-size: 11px;
  color: var(--gray-4);
  font-weight: 600;
}
.donut-wrap {
  display: flex;
  align-items: center;
  gap: 13px;
  margin-top: 8px;
}
.donut {
  width: 90px;
  height: 90px;
  border-radius: 50%;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  position: relative;
}
.donut::after {
  content: '';
  position: absolute;
  inset: 12px;
  background: #fff;
  border-radius: 50%;
}
.donut .v {
  position: relative;
  z-index: 2;
  text-align: center;
}
.donut .v b {
  font-size: 19px;
  font-weight: 800;
  display: block;
}
.donut .v small {
  font-size: 10px;
  color: var(--accent);
  font-weight: 700;
}
.legend {
  flex: 1;
  font-size: 12px;
}
.legend .row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 0;
}
.legend .row .l {
  display: flex;
  align-items: center;
  gap: 7px;
  color: var(--gray-5);
  font-weight: 600;
}
.legend .row .l i {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  display: inline-block;
}
/* 월세=accent, 전세=accent-deep(같은 단일 accent 계열의 음영으로 구분), 공실=gray. */
.legend .row .l i.w {
  background: var(--accent);
}
.legend .row .l i.j {
  background: var(--accent-deep);
}
.legend .row .l i.g {
  background: var(--gray-3);
}
.legend .row b {
  font-weight: 800;
  font-size: 13px;
}
.mini2 {
  display: flex;
  gap: 9px;
  margin-top: 13px;
}
.mini2 .chip {
  flex: 1;
  border: 1px solid var(--gray-2);
  border-radius: var(--r-card);
  padding: 10px 11px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.mini2 .chip .k {
  font-size: 11px;
  color: var(--gray-5);
  font-weight: 600;
}
.mini2 .chip b {
  font-size: 15px;
  font-weight: 800;
}
.sumbox {
  margin-top: 11px;
  background: var(--gray-1);
  border-radius: var(--r-card);
  padding: 3px 13px;
}
.sumbox .row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 11px 0;
  border-bottom: 1px solid var(--gray-2);
}
.sumbox .row:last-child {
  border: 0;
}
.sumbox .k {
  font-size: 12px;
  color: var(--gray-5);
  font-weight: 600;
}
.sumbox .v {
  font-size: 12.5px;
  font-weight: 800;
}
/* 고정 FAB — 빈 상태/목록 FAB 와 동일 스펙(펄스 없음). bnav 위 우하단. */
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
.bnav {
  height: 52px;
  border-top: 1px solid var(--gray-2);
  display: flex;
  align-items: center;
  background: #fff;
  flex: 0 0 auto;
}
.bnav div {
  flex: 1;
  text-align: center;
  font-size: 10px;
  font-weight: 700;
  color: var(--gray-4);
}
.bnav div .ic {
  display: block;
  margin: 0 auto 3px;
  width: 22px;
  height: 22px;
}
.bnav div .ic svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.6;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.bnav div.on {
  color: var(--accent);
}
</style>
