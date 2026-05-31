<script setup>
// 화면 8 — 건물 상세 · 지출 탭 (PRD 4.2 B-5).
// 이번 달 지출 합계 + 항목 리스트. is_repair=true(수리비) 항목만 'AI 분담 ▸' 노출 → 탭 시 Flow C 진입점(open-repair).
// Flow C(AI 수선비 분담)는 미구현 별도 플로우라 여기선 진입점 이벤트만 올린다(벨→Flow D 와 동일 패턴).
import { computed } from 'vue'
import { formatWon } from '../lib/format'
import { formatShortDate } from '../lib/contractDates'

const props = defineProps({
  expenses: { type: Array, default: () => [] },
})

defineEmits(['open-repair'])

const total = computed(() => props.expenses.reduce((s, e) => s + Number(e.amount), 0))
</script>

<template>
  <div class="exps">
    <div class="expsum">
      <div class="lab">이번 달 지출 금액</div>
      <div class="big">{{ formatWon(total) }} <span class="c">{{ expenses.length }}건</span></div>
    </div>

    <p v-if="!expenses.length" class="empty">지출 내역이 없습니다.</p>

    <!-- 수리비 행은 버튼(탭하면 AI 분담). 일반 지출은 정적 행. -->
    <component
      :is="e.is_repair ? 'button' : 'div'"
      v-for="e in expenses"
      :key="e.id"
      class="erow"
      :class="{ repair: e.is_repair }"
      :type="e.is_repair ? 'button' : undefined"
      @click="e.is_repair && $emit('open-repair', e)"
    >
      <span v-if="e.is_repair" class="badge">탭하면 AI 분담</span>
      <div class="top">
        <span class="dt">{{ formatShortDate(e.expense_date) }}</span>
        <span class="am">{{ formatWon(e.amount) }}</span>
      </div>
      <div class="bot">
        <span class="ttl">{{ e.title }}</span>
        <span v-if="e.is_repair" class="rc ai">AI 분담 ▸</span>
        <span v-else class="rc">{{ e.proof_type }}</span>
      </div>
    </component>
  </div>
</template>

<style scoped>
.empty {
  text-align: center;
  color: var(--gray-4);
  font-size: 12.5px;
  padding: 40px 0;
}
.expsum {
  margin: 4px 0 6px;
}
.expsum .lab {
  font-size: 12px;
  color: var(--ink-mute);
  font-weight: 600;
}
.expsum .big {
  font-size: 21px;
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 3px;
  color: var(--ink);
}
.expsum .big .c {
  font-size: 11px;
  background: var(--warn-soft);
  color: var(--warn);
  padding: 3px 8px;
  border-radius: 8px;
  font-weight: 700;
}
.erow {
  display: block;
  width: 100%;
  text-align: left;
  background: #fff;
  border: none;
  border-bottom: 1px solid var(--line);
  padding: 11px 0;
  font-family: inherit;
  color: var(--ink);
}
/* 수리비(AI 분담) 행만 강조 카드 + 상단 뱃지. */
.erow.repair {
  position: relative;
  border: 1px solid var(--accent);
  border-radius: 12px;
  padding: 11px 11px;
  margin: 6px 0;
  cursor: pointer;
}
.erow .badge {
  position: absolute;
  top: -9px;
  right: 11px;
  font-size: 9px;
  font-weight: 800;
  color: #fff;
  background: var(--accent);
  padding: 2px 7px;
  border-radius: 7px;
}
.erow .top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
}
.erow .dt {
  font-size: 10.5px;
  color: var(--ink-mute);
}
.erow .am {
  font-size: 13.5px;
  font-weight: 800;
}
.erow .bot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 3px;
}
.erow .ttl {
  font-size: 12px;
  font-weight: 700;
}
.erow .rc {
  font-size: 9.5px;
  background: var(--gray-1);
  color: var(--gray-5);
  padding: 2px 7px;
  border-radius: 7px;
  font-weight: 600;
}
.erow .rc.ai {
  background: var(--accent-soft);
  color: var(--accent-deep);
  font-weight: 700;
}
</style>
