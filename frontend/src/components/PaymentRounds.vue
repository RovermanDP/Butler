<script setup>
import { formatWon } from '../lib/format'
import { formatShortDate, daysOverdue } from '../lib/contractDates'
import { statusClass } from '../lib/collect'

defineProps({
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
  background: #fff;
}
.hist .h .st {
  font-size: 10px;
  font-weight: 700;
  padding: 3px 8px;
  border-radius: 7px;
  flex: 0 0 auto;
}
/* 대기: 회색 테두리 박스 */
.hist .h .st.wait {
  background: var(--gray-1);
  color: var(--gray-5);
  border: 1px solid var(--gray-3);
}
/* 미납: 빨간 배경 */
.hist .h .st.miss {
  background: var(--danger-soft);
  color: var(--danger);
}
/* 완납: 초록 배경, 흰 글씨 */
.hist .h .st.ok {
  background: var(--ok);
  color: #fff;
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
/* 완납 금액: 기본 ink 유지 (배경 흰색이므로 초록 불필요) */
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