<script setup>
// 화면 2 — 건물 관리 모달(바텀시트). FAB(+) 탭 시 등장.
// 화면 2a — 세입자 등록을 건물 미등록 상태에서 누르면 빨간 토스트로 차단.
// 화면 9 — 건물 등록 완료 후엔 세입자 등록이 활성('✓ 지금 등록 가능' 뱃지) → Flow E 진입점.
//
// ⚠ CLAUDE.md: 화면 2(빈 상태)·화면 9(등록 완료)는 동일 컴포넌트를 재사용(복제 금지)하고,
//    세입자 등록 활성 여부만 tenantEnabled prop 으로 분기한다.
// 분기 판단(건물 수)은 상위(App)가 하고, 이 컴포넌트는 표시 + 사용자 입력 전달만 담당(SRP).
defineProps({
  open: { type: Boolean, default: false },
  // 세입자 등록 활성 여부. true = 화면 9(활성·뱃지) / false = 화면 2(비활성·회색).
  tenantEnabled: { type: Boolean, default: false },
  // (비활성 상태에서) 세입자 등록을 눌러 빨간 강조(outline)를 줄지 여부 — 화면 2a
  tenantTapped: { type: Boolean, default: false },
  toast: { type: String, default: '' },
  toastKind: { type: String, default: 'error' }, // 'error' | 'info'
})

defineEmits(['close', 'select-building', 'select-tenant'])
</script>

<template>
  <Transition name="overlay">
    <div v-if="open" class="overlay">
      <div class="dim" @click="$emit('close')"></div>

      <div class="sheet">
        <div class="sh-top">
          <b>건물 관리</b>
          <button class="x" type="button" aria-label="닫기" @click="$emit('close')">
            <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M6 6L18 18" /><path d="M18 6L6 18" />
            </svg>
          </button>
        </div>
        <div v-if="tenantEnabled" class="sh-desc">
          건물이 이미 등록되어 있어요.<br />이제 <b>세입자 등록</b>까지 바로 진행할 수 있습니다.
        </div>
        <div v-else class="sh-desc">
          편리하고 효율적인 건물 관리를 위해<br />건물과 세입자 정보를 등록해주세요.
        </div>

        <div class="opts">
          <button class="opt active" type="button" @click="$emit('select-building')">
            <div class="oic">🏢<span class="pl">+</span></div>
            <div class="ol">건물등록</div>
          </button>
          <button
            class="opt"
            :class="[tenantEnabled ? 'active enabled-new' : 'dis', { tapped: !tenantEnabled && tenantTapped }]"
            type="button"
            @click="$emit('select-tenant')"
          >
            <span v-if="tenantEnabled" class="okmark">✓ 지금 등록 가능</span>
            <span v-else-if="tenantTapped" class="taptag">탭함</span>
            <div class="oic">👥<span class="pl">+</span></div>
            <div class="ol">세입자 등록</div>
          </button>
        </div>
      </div>

      <Transition name="toast">
        <div v-if="toast" class="err-toast" :class="toastKind">{{ toast }}</div>
      </Transition>
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
  gap: 11px;
}
.opt {
  flex: 1;
  border-radius: var(--r-promo);
  padding: 18px 12px 16px;
  text-align: center;
  border: 1px solid var(--gray-2);
  background: #fff;
  position: relative;
  cursor: pointer;
}
.opt .oic {
  width: 42px;
  height: 42px;
  border-radius: 11px;
  margin: 0 auto 10px;
  display: grid;
  place-items: center;
  font-size: 19px;
  position: relative;
}
.opt .oic .pl {
  position: absolute;
  top: -6px;
  right: -6px;
  width: 17px;
  height: 17px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  font-size: 10px;
  color: #fff;
  font-weight: 800;
}
.opt .ol {
  font-size: 14px;
  font-weight: 800;
}
.opt.active .oic {
  background: var(--accent-soft);
}
.opt.active .oic .pl {
  background: var(--accent);
}
.opt.active .ol {
  color: var(--ink);
}
.opt.dis {
  background: var(--gray-1);
}
.opt.dis .oic {
  background: var(--gray-2);
  color: var(--gray-4);
}
.opt.dis .oic .pl {
  background: var(--gray-3);
}
.opt.dis .ol {
  color: var(--gray-4);
}
.opt.tapped {
  outline: 2px solid var(--danger);
  outline-offset: 1px;
}
/* 화면 9 — 세입자 등록 활성. 건물등록과 동일한 active 톤 + '지금 등록 가능' 초록 뱃지. */
.opt.enabled-new {
  outline: 1.5px solid var(--ok);
  outline-offset: 1px;
}
.opt .okmark {
  position: absolute;
  top: -9px;
  left: 50%;
  transform: translateX(-50%);
  font-size: 9px;
  font-weight: 800;
  color: #fff;
  background: var(--ok);
  padding: 2px 8px;
  border-radius: 7px;
  white-space: nowrap;
}
.opt .taptag {
  position: absolute;
  top: -9px;
  left: 50%;
  transform: translateX(-50%);
  font-size: 9px;
  font-weight: 800;
  color: #fff;
  background: var(--danger);
  padding: 2px 7px;
  border-radius: 7px;
  white-space: nowrap;
}
.err-toast {
  position: absolute;
  left: 12px;
  right: 12px;
  bottom: 12px;
  z-index: 9;
  border-radius: 12px;
  padding: 13px 14px;
  font-size: 12.5px;
  font-weight: 700;
  display: flex;
  align-items: center;
  gap: 8px;
  justify-content: center;
}
.err-toast.error {
  background: var(--danger-soft);
  color: var(--danger);
}
.err-toast.info {
  background: var(--accent-soft);
  color: var(--accent-deep);
}

/* 전환: dim 페이드 + 시트 슬라이드업 */
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
.toast-enter-active,
.toast-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(8px);
}
</style>
