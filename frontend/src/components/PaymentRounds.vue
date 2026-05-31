<script setup>
// 공유 회차 리스트 — 단일 세입자의 회차(대기·미납·완납)를 표로 렌더한다.
// 화면 6c(세입자 상세 · 수납 sub-tab, B-3에서 구현)가 이 컴포넌트를 사용한다.
// ⚠ 건물 수납 탭(PaymentsTab.vue=현황 목록)과는 역할이 다르다 — 여기는 단일 세입자 회차 리스트.
// 상태색: 대기=gray / 미납=danger(D+n) / 완납=ok(💳 강조). (CLAUDE.md)
import { formatWon } from '../lib/format'
import { formatShortDate, daysOverdue } from '../lib/contractDates'
import { statusClass } from '../lib/collect'

defineProps({
  // 회차 목록(round_no 내림차순 = 최근 회차 먼저, 와이어프레임 9→6).
  payments: { type: Array, default: () => [] },
})
</script>

<template>
  <div class="hist">
    <div v-for="p in payments" :key="p.id" class="h">
      <span class="st" :class="statusClass(p.status)">{{ p.status }}</span>
      <span class="rd">{{ p.round_no }}회차</span>
      <span class="am" :class="{ active: p.status === '완납' }">
        <b>{{ p.status === '완납' ? '💳 ' : '' }}{{ formatWon(p.amount) }}</b>
        <small v-if="p.status === '미납'" class="dday">D+{{ daysOverdue(p.due_date) }}</small>
        <small v-else>{{ formatShortDate(p.status === '완납' ? p.paid_date || p.due_date : p.due_date) }}</small>
      </span>
    </div>
  </div>
</template>

<style scoped>
.hist {
  margin-top: 13px;
}
.hist .h {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid var(--line);
}
.hist .h .st {
  font-size: 10px;
  font-weight: 700;
  padding: 3px 8px;
  border-radius: 7px;
}
.hist .h .st.wait {
  background: var(--gray-1);
  color: var(--gray-5);
}
.hist .h .st.miss {
  background: var(--danger-soft);
  color: var(--danger);
}
.hist .h .st.paid {
  background: var(--ok-soft);
  color: var(--ok);
}
.hist .h .rd {
  font-size: 12px;
  font-weight: 700;
  color: var(--ink);
}
.hist .h .am {
  margin-left: auto;
  text-align: right;
}
.hist .h .am b {
  font-size: 12.5px;
  font-weight: 800;
  display: block;
  color: var(--ink-mute);
}
.hist .h .am.active b {
  color: var(--ink);
}
.hist .h .am small {
  font-size: 10px;
  color: var(--ink-mute);
}
.hist .h .am small.dday {
  color: var(--danger);
  font-weight: 700;
}
</style>
