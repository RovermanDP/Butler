<script setup>
import { ref, computed } from 'vue'

// 화면 10i-1 / 10i-2 — 휠 피커 바텀시트(재사용).
// Step3 의 '납부일(1~31일)'과 '과거 미납 내역(미납없음/1·2개월)' 두 곳에서 같은 컴포넌트로 쓴다.
// 책임은 '옵션 목록에서 한 값 선택'뿐(SRP). 말일 보정·첫 납부일 계산 등 도메인 로직은 부모/ lib 가 담당.
// 부모가 v-if 로 마운트/언마운트하며, 확정(선택하기) 시 선택값을 emit('confirm', value) 한다.
const props = defineProps({
  // 옵션 목록: [{ value, label }]. value 는 부모가 쓰는 원본값(숫자 day, '미납없음' 등).
  options: { type: Array, required: true },
  // 진입 시 가운데 정렬할 현재 값. 목록에 없으면 0번으로 시작.
  modelValue: { type: [String, Number], default: null },
  title: { type: String, default: '' },
  desc: { type: String, default: '' },
})

const emit = defineEmits(['confirm', 'cancel'])

// 현재 가운데(선택) 인덱스. 휠 회전/탭/드래그로 이동한다.
const startIndex = props.options.findIndex((o) => o.value === props.modelValue)
const index = ref(startIndex >= 0 ? startIndex : 0)

// 가운데(offset 0) 기준 위·아래 2칸씩(총 5칸) 표시. 범위를 벗어나면 빈 칸(label='').
// 바깥칸일수록 흐리게(f3 > f2 > on) — 와이어프레임 .wheel 시각 단계.
const slots = computed(() =>
  [-2, -1, 0, 1, 2].map((offset) => {
    const i = index.value + offset
    const opt = props.options[i]
    return {
      key: offset,
      label: opt ? opt.label : '',
      cls: offset === 0 ? 'on' : Math.abs(offset) === 1 ? 'f2' : 'f3',
      idx: opt ? i : null,
    }
  }),
)

// 인덱스 이동(범위 클램프) — 휠/드래그/탭 공통 진입점.
function step(delta) {
  const next = index.value + delta
  if (next < 0 || next > props.options.length - 1) return
  index.value = next
}

// 표시된 칸 탭 → 그 칸으로 곧장 이동(가운데/이웃칸 모두 선택 가능).
function tapSlot(slot) {
  if (slot.idx === null) return
  index.value = slot.idx
}

// 마우스 휠 — 한 노치당 한 칸.
function onWheel(event) {
  step(Math.sign(event.deltaY))
}

// 포인터 드래그(터치/마우스) — 누적 이동량이 STEP px 단위로 한 칸씩 회전.
const STEP_PX = 30
const dragging = ref(false)
let lastY = 0
let accum = 0
function onPointerDown(event) {
  dragging.value = true
  lastY = event.clientY
  accum = 0
  // 의도적으로 setPointerCapture 를 쓰지 않는다 — 캡처하면 자식 칸(button)의 click 이 휠로 가로채여
  // 탭-선택이 깨진다. 드래그는 휠 영역 내 pointermove 로 충분하고, 칸 탭은 click 으로 안정적으로 처리된다.
}
function onPointerMove(event) {
  if (!dragging.value) return
  accum += event.clientY - lastY
  lastY = event.clientY
  while (accum <= -STEP_PX) {
    step(1)
    accum += STEP_PX
  }
  while (accum >= STEP_PX) {
    step(-1)
    accum -= STEP_PX
  }
}
function onPointerUp() {
  dragging.value = false
}

function onConfirm() {
  const opt = props.options[index.value]
  if (!opt) return
  emit('confirm', opt.value)
}
</script>

<template>
  <div class="overlay">
    <div class="dim" @click="emit('cancel')"></div>
    <div class="sheet" role="dialog" aria-modal="true">
      <div class="sh-top">
        <b>{{ title }}</b>
        <button class="x" type="button" aria-label="닫기" @click="emit('cancel')">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M6 6L18 18" /><path d="M18 6L6 18" />
          </svg>
        </button>
      </div>
      <p v-if="desc" class="sh-desc">{{ desc }}</p>

      <div
        class="wheel"
        @wheel.prevent="onWheel"
        @pointerdown="onPointerDown"
        @pointermove="onPointerMove"
        @pointerup="onPointerUp"
        @pointercancel="onPointerUp"
      >
        <button
          v-for="slot in slots"
          :key="slot.key"
          type="button"
          class="wv"
          :class="slot.cls"
          :disabled="slot.idx === null"
          @click="tapSlot(slot)"
        >
          {{ slot.label }}
        </button>
      </div>

      <button class="sheet-cta" type="button" @click="onConfirm">선택하기</button>
    </div>
  </div>
</template>

<style scoped>
/* 와이어프레임 .sheet / .wheel 토큰 이식(보드 장식 제외). 부모 .scr 내부에 절대배치. */
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
.sh-desc {
  font-size: 12px;
  color: var(--gray-5);
  line-height: 1.6;
  margin: 12px 0 4px;
}
.wheel {
  position: relative;
  height: 170px;
  margin-top: 10px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  touch-action: none;
  cursor: grab;
}
.wheel:active {
  cursor: grabbing;
}
/* 가운데 선택 영역 강조 바 */
.wheel::before {
  content: '';
  position: absolute;
  left: 8px;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  height: 34px;
  background: var(--accent-soft);
  border-radius: 9px;
  z-index: 0;
}
.wv {
  position: relative;
  z-index: 1;
  width: 100%;
  line-height: 1.9;
  text-align: center;
  border: none;
  background: none;
  font-family: inherit;
  cursor: pointer;
  padding: 0;
}
.wv:disabled {
  cursor: default;
  visibility: hidden;
}
.wv.f3 {
  font-size: 11px;
  color: var(--gray-3);
  font-weight: 600;
}
.wv.f2 {
  font-size: 13px;
  color: var(--gray-4);
  font-weight: 600;
}
.wv.on {
  font-size: 17px;
  color: var(--accent);
  font-weight: 800;
}
.sheet-cta {
  margin-top: 8px;
  width: 100%;
  background: var(--accent);
  color: #fff;
  border: none;
  border-radius: 12px;
  padding: 14px;
  text-align: center;
  font-weight: 800;
  font-size: 14px;
  font-family: inherit;
  cursor: pointer;
}
</style>
