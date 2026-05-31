<script setup>
import { ref, computed } from 'vue'
import { parseIsoDate, formatKoDate, monthGrid, shiftMonth, daysInMonth } from '../lib/contractDates'

// 화면 10a-1 — 계약기간 캘린더(날짜 선택) 모달.
// 시작일/종료일 공용. '확인' 시 선택 날짜('YYYY-MM-DD')를 부모로 올린다.
// 종료일 +1년 자동 산정은 부모(Step1)가 담당하고, 이 컴포넌트는 '날짜 한 개 선택'만 책임진다(SRP).
const props = defineProps({
  // 모달 진입 시 미리 선택돼 있을 날짜('YYYY-MM-DD'|''). 없으면 오늘 기준 달을 연다.
  value: { type: String, default: '' },
  title: { type: String, default: '날짜 선택' },
})

const emit = defineEmits(['confirm', 'cancel'])

const WEEK_HEADERS = ['일', '월', '화', '수', '목', '금', '토']

// 초기 선택값/표시 월: 전달된 값이 있으면 그 달, 없으면 실제 오늘 달.
const initial = parseIsoDate(props.value) ?? (() => {
  const now = new Date()
  return { y: now.getFullYear(), m: now.getMonth() + 1, d: now.getDate() }
})()

const view = ref({ y: initial.y, m: initial.m }) // 현재 표시 중인 연/월
const selected = ref(props.value || '') // 현재 선택된 날짜(없으면 빈 값 = 미선택)

const cells = computed(() => monthGrid(view.value.y, view.value.m))
const bigLabel = computed(() => (selected.value ? formatKoDate(selected.value) : '날짜를 선택해주세요'))
const monthLabel = computed(() => `${view.value.y}년 ${view.value.m}월`)

function move(delta) {
  view.value = shiftMonth(view.value.y, view.value.m, delta)
}

function pick(iso) {
  selected.value = iso
}

function onConfirm() {
  if (!selected.value) return // 미선택 시 확인 비활성(연속 클릭/빈 확정 방어)
  emit('confirm', selected.value)
}
</script>

<template>
  <div class="overlay">
    <div class="dim" @click="emit('cancel')"></div>
    <div class="datemodal" role="dialog" aria-modal="true">
      <div class="dm-title">{{ title }}</div>
      <div class="dm-big">{{ bigLabel }}</div>

      <div class="dm-month">
        <span class="ym">{{ monthLabel }}</span>
        <span class="nav">
          <button type="button" aria-label="이전 달" @click="move(-1)">‹</button>
          <button type="button" aria-label="다음 달" @click="move(1)">›</button>
        </span>
      </div>

      <div class="dm-cal">
        <div v-for="h in WEEK_HEADERS" :key="h" class="hd">{{ h }}</div>
        <template v-for="(iso, i) in cells" :key="i">
          <div v-if="!iso" class="d empty"></div>
          <button
            v-else
            type="button"
            class="d"
            :class="{ sel: iso === selected }"
            @click="pick(iso)"
          >
            {{ Number(iso.slice(8, 10)) }}
          </button>
        </template>
      </div>

      <div class="dm-actions">
        <button type="button" class="act" @click="emit('cancel')">취소</button>
        <button type="button" class="act" :class="{ dis: !selected }" @click="onConfirm">확인</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 와이어프레임 .datemodal 토큰 이식(보드 장식 제외). 부모 .scr 내부에 절대배치된다. */
.overlay {
  position: absolute;
  inset: 0;
  z-index: 10;
}
.dim {
  position: absolute;
  inset: 0;
  background: rgba(31, 31, 36, 0.42);
}
.datemodal {
  position: absolute;
  top: 50%;
  left: 14px;
  right: 14px;
  transform: translateY(-50%);
  background: #fff;
  border-radius: 16px;
  padding: 14px 14px 11px;
  box-shadow: 0 18px 36px rgba(31, 31, 36, 0.28);
}
.dm-title {
  font-size: 10px;
  color: var(--gray-4);
  font-weight: 700;
  margin-bottom: 5px;
}
.dm-big {
  font-size: 18px;
  font-weight: 800;
  color: var(--ink);
  padding: 0 0 8px;
  border-bottom: 1.5px solid var(--ink);
}
.dm-month {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 9px 0 4px;
}
.dm-month .ym {
  font-size: 11px;
  font-weight: 800;
  color: var(--ink);
}
.dm-month .nav {
  display: flex;
  gap: 6px;
}
.dm-month .nav button {
  border: none;
  background: var(--gray-1);
  color: var(--gray-6);
  width: 26px;
  height: 26px;
  border-radius: 8px;
  font-size: 15px;
  font-weight: 700;
  cursor: pointer;
}
.dm-cal {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  row-gap: 3px;
  text-align: center;
}
.dm-cal .hd {
  font-size: 9.5px;
  font-weight: 700;
  color: var(--gray-4);
  padding: 3px 0 4px;
}
.dm-cal .d {
  width: 26px;
  height: 26px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: 600;
  color: var(--ink);
  border-radius: 50%;
  border: none;
  background: none;
  cursor: pointer;
  font-family: inherit;
}
.dm-cal .d.empty {
  cursor: default;
}
.dm-cal .d.sel {
  background: var(--accent);
  color: #fff;
  font-weight: 800;
}
.dm-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 10px;
}
.dm-actions .act {
  border: none;
  background: none;
  font-size: 12px;
  font-weight: 800;
  color: var(--accent);
  padding: 6px 10px;
  cursor: pointer;
  font-family: inherit;
}
.dm-actions .act.dis {
  color: var(--gray-3);
  cursor: not-allowed;
}
</style>
