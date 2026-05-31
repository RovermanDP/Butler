<script setup>
// 화면 10 — 세입자 등록 방법 선택 바텀시트.
// '직접 등록하기'(PoC 구현 경로) / '임대차 계약서 추천'(teaser, 6.3 범위 외 — 안내만).
// 표시 + 선택 전달만 담당(SRP). 분기/라우팅은 상위(App)가 소유한다.
defineProps({
  open: { type: Boolean, default: false },
})

defineEmits(['close', 'select-direct', 'select-recommend'])
</script>

<template>
  <Transition name="overlay">
    <div v-if="open" class="overlay">
      <div class="dim" @click="$emit('close')"></div>

      <div class="sheet">
        <div class="sh-top">
          <b>세입자 등록</b>
          <button class="x" type="button" aria-label="닫기" @click="$emit('close')">
            <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M6 6L18 18" /><path d="M18 6L6 18" />
            </svg>
          </button>
        </div>
        <div class="sh-desc">세입자 등록 방법을 선택해 주세요</div>

        <div class="opts">
          <button class="reg-opt active" type="button" @click="$emit('select-direct')">
            <b>직접 등록하기</b>
          </button>
          <button class="reg-opt" type="button" @click="$emit('select-recommend')">
            <b>임대차 계약서 <span class="tag">추천</span></b>
            <small>더 빠르게 세입자 등록을 완료할 수 있어요</small>
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.overlay {
  position: absolute;
  inset: 0;
  z-index: 7;
}
.dim {
  position: absolute;
  inset: 0;
  background: rgba(60, 60, 60, 0.52);
}
.sheet {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 8;
  background: #fff;
  border-radius: var(--r-sheet) var(--r-sheet) 0 0;
  padding: 18px 18px 22px;
  box-shadow: 0 -12px 30px rgba(0, 0, 0, 0.18);
}
.sh-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.sh-top b {
  font-size: 18px;
  font-weight: 800;
}
.sh-top .x {
  border: none;
  background: none;
  cursor: pointer;
  color: var(--gray-4);
  width: 22px;
  height: 22px;
  padding: 0;
}
.sh-top .x svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
}
.sh-desc {
  font-size: 12px;
  color: var(--gray-5);
  line-height: 1.6;
  margin: 12px 0 16px;
}
.opts {
  display: flex;
  flex-direction: column;
  gap: 11px;
}
.reg-opt {
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 15px;
  text-align: left;
  background: #fff;
  cursor: pointer;
  font-family: inherit;
}
.reg-opt b {
  font-size: 14px;
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--ink);
}
.reg-opt small {
  display: block;
  font-size: 11px;
  color: var(--gray-4);
  margin-top: 6px;
  font-weight: 600;
}
.reg-opt.active {
  border-color: var(--accent);
  box-shadow: 0 0 0 1.5px rgba(58, 110, 165, 0.22);
}
.reg-opt .tag {
  font-size: 9.5px;
  font-weight: 800;
  color: var(--accent-deep);
  background: var(--accent-soft);
  padding: 2px 7px;
  border-radius: var(--r-tag);
}

.overlay-enter-active,
.overlay-leave-active {
  transition: opacity 0.2s ease;
}
.overlay-enter-from,
.overlay-leave-to {
  opacity: 0;
}
.overlay-enter-active .sheet,
.overlay-leave-active .sheet {
  transition: transform 0.26s cubic-bezier(0.22, 1, 0.36, 1);
}
.overlay-enter-from .sheet,
.overlay-leave-to .sheet {
  transform: translateY(100%);
}
</style>
