<script setup>
// 화면 7 — 건물 상세 · 수납 탭 (PRD 4.2 B-4).
import { ref, computed } from 'vue'
import { formatWon } from '../lib/format'
import { formatShortDate } from '../lib/contractDates'
import { payableTenants, representative, aggregate, sortReps, statusClass } from '../lib/collect'
import { updatePaymentStatus } from '../lib/detail'
import PaymentStatusModal from './PaymentStatusModal.vue'

const props = defineProps({
  tenants: { type: Array, default: () => [] },
  buildingName: { type: String, default: '' },
})

const emit = defineEmits(['open-tenant', 'reload'])

const reps = computed(() => payableTenants(props.tenants).map(representative))
const agg = computed(() => aggregate(reps.value))

const STATUS_OPTS = ['전체', '완납', '미납', '대기']
const statusFilter = ref('전체')
const filterOpen = ref(false)
const sortMode = ref('unit')
const sortDir = ref('asc')

function pickFilter(s) {
  statusFilter.value = s
  filterOpen.value = false
}
function toggleDir() {
  sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
}

const visible = computed(() => {
  const f =
    statusFilter.value === '전체'
      ? reps.value
      : reps.value.filter((r) => r.status === statusFilter.value)
  return sortReps(f, sortMode.value, sortDir.value)
})

const editing = ref(null)
const saving = ref(false)
const saveErr = ref('')

function openEdit(rep) {
  saveErr.value = ''
  editing.value = rep
}
async function confirmStatus(status) {
  if (!editing.value?.payment) return
  saving.value = true
  saveErr.value = ''
  try {
    const today = new Date().toISOString().slice(0, 10)
    await updatePaymentStatus(editing.value.payment.id, status, today)
    editing.value = null
    emit('reload')
  } catch (err) {
    saveErr.value = err.message || '저장에 실패했습니다.'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="pays">
    <p v-if="!reps.length" class="empty">수납 현황이 없습니다.</p>

    <template v-else>
      <!-- 상단 집계 카드 -->
      <div class="collect-card">
        <div class="collect-total">
          <span class="k">총 {{ agg.total.count }} 건</span>
          <span class="v">{{ formatWon(agg.total.amount) }}</span>
        </div>
        <div class="collect-bar">
          <span class="seg-ok"  :style="{ width: agg.bar.ok   + '%' }"></span>
          <span class="seg-miss" :style="{ width: agg.bar.miss + '%' }"></span>
        </div>
        <div class="collect-legend">
          <span class="lg-ok"><i></i>완납</span>
          <span class="lg-miss"><i></i>미납</span>
          <span class="lg-all"><i></i>대기</span>
        </div>
        <div class="collect-div"></div>
        <div class="collect-row">
          <span class="k">완납 <span class="cbadge ok">{{ agg.paid.count }} 건</span></span>
          <span class="v ok">{{ formatWon(agg.paid.amount) }}</span>
        </div>
        <div class="collect-row">
          <span class="k">미납 <span class="cbadge miss">{{ agg.miss.count }} 건</span></span>
          <span class="v miss">{{ formatWon(agg.miss.amount) }}</span>
        </div>
        <div class="collect-row">
          <span class="k">대기 <span class="cbadge wait">{{ agg.wait.count }} 건</span></span>
          <span class="v">{{ formatWon(agg.wait.amount) }}</span>
        </div>
      </div>

      <!-- 정렬 · 상태 필터 -->
      <div class="collect-sort">
        <span class="cs-filter" @click="filterOpen = !filterOpen">
          <!-- ① "전체" → "완납"으로 표기 변경 -->
          {{ statusFilter === '전체' ? '전체' : statusFilter }} ⌄
          <div v-if="filterOpen" class="cs-menu">
            <button
              v-for="s in STATUS_OPTS"
              :key="s"
              type="button"
              :class="{ on: statusFilter === s }"
              @click.stop="pickFilter(s)"
            >
              <!-- 메뉴 안에서도 "전체" → "완납" -->
              {{ s }}
            </button>
          </div>
        </span>
        <span class="cs-modes">
          <span class="cs-mode" :class="{ on: sortMode === 'unit' }" @click="sortMode = 'unit'">세대/호수순</span>
          <span class="cs-mode" :class="{ on: sortMode === 'due'  }" @click="sortMode = 'due'">입금예정일순</span>
          <span class="cs-dir" @click="toggleDir">{{ sortDir === 'asc' ? '↑' : '↓' }}</span>
        </span>
      </div>

      <!-- 세입자별 수납 행 -->
      <div
        v-for="r in visible"
        :key="r.tenant.id"
        class="pay-trow"
        role="button"
        tabindex="0"
        @click="emit('open-tenant', r.tenant)"
      >
        <span class="pst" :class="statusClass(r.status)">{{ r.status }}</span>
        <div class="pt-info">
          <div class="nm">{{ r.tenant.name }}</div>
          <div class="unit">{{ r.tenant.primary.unit_no }}</div>
        </div>
        <div class="pt-amt">
          <div class="am">
            <button class="ed" type="button" aria-label="수동 수납 처리" @click.stop="openEdit(r)">✎</button>
            {{ formatWon(r.amount) }}
          </div>
          <div class="dt" :class="{ dday: r.status === '미납', okday: r.status === '완납' }">
            <template v-if="r.status === '미납'">D+{{ r.overdue }}</template>
            <template v-else>{{ formatShortDate(r.dueDate) }}</template>
          </div>
        </div>
        <span class="arr">›</span>
      </div>
    </template>

    <PaymentStatusModal
      v-if="editing"
      :tenant-name="editing.tenant.name"
      :unit-no="editing.tenant.primary.unit_no"
      :payment="editing.payment"
      :saving="saving"
      :error="saveErr"
      @confirm="confirmStatus"
      @cancel="editing = null"
    />
  </div>
</template>

<style scoped>
.empty {
  text-align: center;
  color: var(--gray-4);
  font-size: 12.5px;
  padding: 40px 0;
}
.collect-card {
  background: var(--gray-1);
  border-radius: 12px;
  padding: 14px 14px 8px;
}
.collect-total {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.collect-total .k {
  font-size: 13px;
  font-weight: 700;
  color: var(--ink-soft);
}
.collect-total .v {
  font-size: 16px;
  font-weight: 800;
  color: var(--ink);
}
.collect-bar {
  height: 11px;
  border-radius: 7px;
  overflow: hidden;
  display: flex;
  margin: 11px 0 8px;
  background: var(--gray-2);
}
.collect-bar span {
  display: block;
  height: 100%;
}
.collect-bar .seg-ok   { background: var(--ok); }
.collect-bar .seg-miss { background: var(--danger); }
.collect-legend {
  display: flex;
  gap: 11px;
  justify-content: flex-end;
  font-size: 10px;
  font-weight: 700;
  color: var(--ink-soft);
}
.collect-legend i {
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  margin-right: 4px;
  vertical-align: middle;
}
.collect-legend .lg-ok   i { background: var(--ok); }
.collect-legend .lg-miss i { background: var(--danger); }
.collect-legend .lg-all  i { background: #fff; border: 1px solid var(--gray-3); }
.collect-div {
  border-top: 1px solid var(--line);
  margin: 11px 0 2px;
}
.collect-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 9px 0;
}
.collect-row .k {
  font-size: 13px;
  font-weight: 600;
  color: var(--ink-soft);
  display: flex;
  align-items: center;
  gap: 7px;
}
.collect-row .v {
  font-size: 14px;
  font-weight: 800;
  color: var(--ink);
}
.collect-row .v.ok   { color: var(--ok); }
.collect-row .v.miss { color: var(--danger); }
.cbadge {
  font-size: 10px;
  font-weight: 800;
  padding: 2px 8px;
  border-radius: 7px;
}
.cbadge.ok   { background: var(--ok-soft);      color: var(--ok); }
.cbadge.miss { background: var(--danger-soft);   color: var(--danger); }
/* ② 대기 뱃지: 회색 테두리 박스로 구분 */
.cbadge.wait { background: var(--gray-1); color: var(--ink-soft); border: 1px solid var(--gray-3); }
.collect-sort {
  display: flex;
  align-items: center;
  margin: 15px 0 2px;
  font-size: 11.5px;
  font-weight: 700;
}
.collect-sort .cs-filter {
  color: var(--ink-soft);
  position: relative;
  cursor: pointer;
  user-select: none;
}
.collect-sort .cs-menu {
  position: absolute;
  top: 100%;
  left: 0;
  margin-top: 6px;
  background: #fff;
  border: 1px solid var(--line);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(31,31,36,0.08);
  padding: 4px;
  z-index: 5;
  min-width: 96px;
}
.collect-sort .cs-menu button {
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
.collect-sort .cs-menu button.on {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.collect-sort .cs-modes {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 9px;
}
.collect-sort .cs-mode {
  color: var(--ink-mute);
  cursor: pointer;
}
.collect-sort .cs-mode.on {
  color: var(--accent);
  text-decoration: underline;
  font-weight: 800;
}
.collect-sort .cs-dir {
  color: var(--ink-soft);
  font-weight: 800;
  cursor: pointer;
}
.pay-trow {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 13px 2px;
  border-top: 1px solid var(--line);
  position: relative;
  cursor: pointer;
}
.pay-trow .pst {
  flex: 0 0 auto;
  font-size: 10px;
  font-weight: 800;
  padding: 5px 8px;
  border-radius: 7px;
}
.pay-trow .pst.ok   { background: var(--ok-soft);    color: var(--ok); }
.pay-trow .pst.miss { background: var(--danger-soft); color: var(--danger); }
/* ② 대기 상태: 테두리 있는 회색 박스 */
.pay-trow .pst.wait { background: #fff; color: var(--ink-soft); border: 1px solid var(--gray-3); }
.pay-trow .pt-info { flex: 1; min-width: 0; }
.pay-trow .pt-info .nm {
  font-size: 14px;
  font-weight: 800;
  color: var(--ink);
  white-space: nowrap;
}
.pay-trow .pt-info .unit {
  font-size: 10.5px;
  color: var(--ink-mute);
  font-weight: 600;
  margin-top: 3px;
}
.pay-trow .pt-amt { flex: 0 0 auto; text-align: right; }
.pay-trow .pt-amt .am {
  font-size: 12.5px;
  font-weight: 800;
  color: var(--ink);
  display: flex;
  align-items: center;
  gap: 5px;
  justify-content: flex-end;
}
.pay-trow .pt-amt .am .ed {
  width: 17px;
  height: 17px;
  border-radius: 50%;
  background: var(--gray-2);
  color: var(--ink-soft);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  border: none;
  padding: 0;
  cursor: pointer;
}
.pay-trow .pt-amt .dt {
  font-size: 10px;
  color: var(--ink-mute);
  margin-top: 3px;
}
.pay-trow .pt-amt .dt.dday  { color: var(--danger); font-weight: 700; }
.pay-trow .pt-amt .dt.okday { color: var(--ok);     font-weight: 700; }
.pay-trow .arr {
  flex: 0 0 auto;
  color: var(--gray-3);
  font-size: 15px;
}
</style>