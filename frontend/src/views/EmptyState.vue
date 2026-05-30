<script setup>
// 화면 1 — 빈 상태(신규 사용자). 등록 건물이 없을 때의 첫 화면.
// FAB(+) 탭 시 건물 관리 모달을 연다(상위에서 처리).
// 상단 탭·월 네비·하단 네비는 와이어프레임 크롬 재현(정보 탭 기능은 Flow B 범위).
defineEmits(['open-sheet'])
</script>

<template>
  <div class="scr">
    <div class="tbar">
      <span class="ttl">건물관리</span>
      <span class="ico"></span>
    </div>

    <div class="month"><span>◀</span>2026년 5월<span>▶</span></div>

    <div class="tabs">
      <div class="on">정보</div>
      <div>세입자</div>
      <div>수납</div>
    </div>

    <div class="body">
      <div class="promo blue">
        <span class="pg">6/7</span>
        <b>세입자와 연동</b>하고<br />공지와 소식을 간편하게 전달해요 📣
      </div>

      <div class="empty">
        <div class="bg"><span class="plus">+</span></div>
        <p>등록된 건물이 없습니다 😅<br />건물과 세입자 정보를<br />등록해 주세요</p>
      </div>
    </div>

    <button class="fab" type="button" aria-label="건물·세입자 등록" @click="$emit('open-sheet')">
      +
    </button>

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
}
.tbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 15px 4px;
}
.tbar .ttl {
  font-size: 15px;
  font-weight: 800;
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
  gap: 14px;
  padding: 0 15px;
  border-bottom: 1px solid var(--gray-2);
}
.tabs div {
  font-size: 12.5px;
  font-weight: 700;
  color: var(--gray-4);
  padding: 8px 0 9px;
  position: relative;
  white-space: nowrap;
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
  padding: 13px 15px;
  display: flex;
  flex-direction: column;
}
.promo {
  background: var(--accent);
  color: #fff;
  border-radius: var(--r-promo);
  padding: 13px 14px;
  font-size: 12.5px;
  line-height: 1.5;
  font-weight: 600;
  position: relative;
  overflow: hidden;
}
.promo b {
  font-weight: 800;
}
.promo .pg {
  position: absolute;
  top: 8px;
  right: 12px;
  font-size: 10px;
  background: rgba(255, 255, 255, 0.25);
  padding: 2px 7px;
  border-radius: var(--r-tag);
  font-weight: 700;
}
.empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: var(--gray-4);
  margin-top: 8px;
}
.empty .bg {
  width: 64px;
  height: 80px;
  border-radius: 12px;
  background: var(--gray-2);
  position: relative;
}
.empty .bg .plus {
  position: absolute;
  top: -9px;
  right: -9px;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: var(--accent);
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 13px;
  font-weight: 800;
}
.empty p {
  font-size: 12px;
  text-align: center;
  line-height: 1.6;
}
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
  animation: pulse 1.6s ease-in-out infinite;
}
@keyframes pulse {
  0%,
  100% {
    box-shadow: 0 10px 22px -8px rgba(58, 110, 165, 0.8);
  }
  50% {
    box-shadow: 0 0 0 9px rgba(58, 110, 165, 0.2);
  }
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
