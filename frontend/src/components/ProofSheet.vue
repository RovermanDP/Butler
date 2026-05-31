<script setup>
// 화면 10m — 증빙 발급 설정 모달(5종).
// 책임은 '5종 중 하나 선택'뿐(SRP). 선택값에 따른 하위 필드(휴대폰/사업자번호/이메일/등록증)는 부모(Step3)가 분기 렌더.
// ⚠ 이 proof_kind(임대료 증빙 발급 설정)는 expenses.proof_type(지출 증빙)과 별개 개념(CLAUDE.md).
// 부모가 v-if 로 마운트/언마운트하며, 항목 탭 시 emit('select', kind) 후 부모가 닫는다.
defineProps({
  // 현재 선택된 종류(하이라이트용). 미선택이면 ''.
  modelValue: { type: String, default: '' },
})

const emit = defineEmits(['select', 'cancel'])

// CLAUDE.md enum(한글 그대로) — contracts.proof_kind 5종.
const OPTIONS = [
  '해당없음',
  '현금영수증(개인소득공제용)',
  '현금영수증(사업자증빙용)',
  '세금계산서',
  '계산서',
]
</script>

<template>
  <div class="overlay">
    <div class="dim" @click="emit('cancel')"></div>
    <div class="sheet" role="dialog" aria-modal="true">
      <div class="sh-top">
        <b>증빙</b>
        <button class="x" type="button" aria-label="닫기" @click="emit('cancel')">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M6 6L18 18" /><path d="M18 6L6 18" />
          </svg>
        </button>
      </div>
      <div class="sheet-list">
        <button
          v-for="opt in OPTIONS"
          :key="opt"
          type="button"
          class="sl"
          :class="{ on: opt === modelValue }"
          @click="emit('select', opt)"
        >
          {{ opt }}
          <span v-if="opt === modelValue" class="ck" aria-hidden="true">✓</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
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
.sheet {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  background: #fff;
  border-radius: 22px 22px 0 0;
  padding: 18px 18px 22px;
  box-shadow: 0 -12px 30px rgba(31, 31, 36, 0.18);
}
.sh-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}
.sh-top b {
  font-size: 17px;
  font-weight: 800;
  color: var(--ink);
}
.sh-top .x {
  border: none;
  background: none;
  cursor: pointer;
  padding: 0;
  width: 22px;
  height: 22px;
  color: var(--gray-4);
}
.sh-top .x svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.sheet-list {
  display: flex;
  flex-direction: column;
}
.sl {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 15px 2px;
  font-size: 14px;
  font-weight: 700;
  color: var(--ink);
  border: none;
  border-bottom: 1px solid var(--line);
  background: none;
  cursor: pointer;
  font-family: inherit;
  text-align: left;
  width: 100%;
}
.sl:last-child {
  border-bottom: 0;
}
.sl.on {
  color: var(--accent-deep);
}
.sl .ck {
  color: var(--accent);
  font-size: 13px;
  font-weight: 800;
}
</style>
