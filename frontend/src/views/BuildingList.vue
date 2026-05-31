<script setup>
// 화면 5 — 건물 목록(건물별). 등록 완료 후 첫 진입 화면이자 앱 시작 시 기본 홈.
// 카드 = buildings(등록 데이터) + stats(building_stats/unpaid_stats View) 합류.
//   · 입주율 ring·임대현황(n/n)·임대수익·신규/만료/미납 뱃지는 모두 집계 View 산출값.
//   · 카드 탭 → 단일 건물 상세(정보 탭, 화면 4) — select 이벤트로 상위(App)에 위임.
// 전체/건물별 토글·검색·즐겨찾기는 PRD상 B 범위지만 완료 기준 밖이라 시각만 유지(과도구현 지양).
import { formatWon } from '../lib/format'

const props = defineProps({
  buildings: { type: Array, required: true },
  // building_id → 집계 지표 맵. 등록 직후(미반영) 건물은 키가 없을 수 있어 statOf 로 방어한다.
  stats: { type: Object, default: () => ({}) },
  flash: { type: String, default: '' }, // 등록 직후 성공 배너(선택)
})

defineEmits(['select'])

// 집계 미반영(예: 방금 등록한 건물) 시에도 카드가 깨지지 않도록 기본값을 채운다.
function statOf(b) {
  return (
    props.stats[b.id] ?? {
      occupancy_rate: 0,
      occupied_units: 0,
      unit_count: b.unit_count,
      rental_income: 0,
      new_this_month: 0,
      expiring_this_month: 0,
      unpaid_count: 0,
    }
  )
}

// 입주율 ring(conic-gradient). 와이어프레임의 .r100/.r85/.r93 하드코딩을 비율로 동적화.
function ringStyle(rate) {
  const pct = Number(rate) || 0
  return { background: `conic-gradient(var(--accent) 0 ${pct}%, var(--gray-2) 0)` }
}
</script>

<template>
  <div class="scr">
    <div class="tbar">
      <span class="ttl">건물 관리</span>
      <span class="ico"></span>
    </div>

    <div class="month"><span>◀</span>2026년 5월<span>▶</span></div>

    <div class="tabs">
      <div>전체</div>
      <div class="on">건물별</div>
    </div>

    <div class="body">
      <Transition name="flash">
        <div v-if="flash" class="flash">✓ {{ flash }}</div>
      </Transition>

      <!-- 검색: Flow B+ 에서 필터 기능 연결, 지금은 시각만 -->
      <div class="search">
        <span>건물 검색</span>
        <span class="search-ic" aria-hidden="true">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <circle cx="11" cy="11" r="6.5" /><path d="M16 16L21 21" />
          </svg>
        </span>
      </div>

      <!-- 건물 카드. 탭 → 정보 탭(화면 4) 진입 -->
      <button
        v-for="b in buildings"
        :key="b.id"
        class="bcard"
        type="button"
        @click="$emit('select', b)"
      >
        <span class="star" :class="{ on: b.is_favorite }">{{ b.is_favorite ? '★' : '☆' }}</span>
        <div class="bn">{{ b.name }} ›</div>

        <div class="badges">
          <span v-if="statOf(b).new_this_month" class="tag new">신규 {{ statOf(b).new_this_month }}</span>
          <span v-if="statOf(b).expiring_this_month" class="tag end">만료 {{ statOf(b).expiring_this_month }}</span>
          <span v-if="statOf(b).unpaid_count" class="tag due">미납 {{ statOf(b).unpaid_count }}</span>
        </div>

        <div class="stat">
          <div class="ring" :style="ringStyle(statOf(b).occupancy_rate)">
            <b>{{ statOf(b).occupancy_rate }}%</b>
          </div>
          <div class="info">
            <div class="occ">임대현황 ({{ statOf(b).occupied_units }}/{{ statOf(b).unit_count }})</div>
            <div class="inc">{{ formatWon(statOf(b).rental_income) }}</div>
            <div class="bar"><i :style="{ width: (Number(statOf(b).occupancy_rate) || 0) + '%' }"></i></div>
          </div>
        </div>
      </button>
    </div>

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
  padding: 10px 15px 14px;
}
.flash {
  background: var(--accent-soft);
  color: var(--accent-deep);
  border-radius: 12px;
  padding: 11px 13px;
  font-size: 12.5px;
  font-weight: 700;
  margin-bottom: 10px;
}
.search {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border: 1px solid var(--gray-2);
  border-radius: var(--r-input);
  padding: 9px 12px;
  font-size: 12px;
  color: var(--gray-4);
}
.search-ic {
  width: 16px;
  height: 16px;
  color: var(--gray-4);
}
.search-ic svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
}
/* 카드 = 클릭 가능한 button. 기본 버튼 스타일 리셋 후 카드 레이아웃 적용. */
.bcard {
  display: block;
  width: 100%;
  text-align: left;
  font: inherit;
  color: inherit;
  cursor: pointer;
  position: relative;
  margin-top: 12px;
  border: 1px solid var(--gray-2);
  border-radius: var(--r-card);
  background: #fff;
  padding: 16px 14px;
}
.bcard:active {
  background: var(--gray-1);
}
.bcard .star {
  position: absolute;
  top: 14px;
  right: 14px;
  color: var(--gray-3);
  font-size: 16px;
}
.bcard .star.on {
  color: var(--warn);
}
.bcard .bn {
  font-size: 15px;
  font-weight: 800;
  padding-right: 24px;
}
.bcard .badges {
  display: flex;
  gap: 6px;
  margin: 8px 0 11px;
  flex-wrap: wrap;
  min-height: 0;
}
.bcard .badges:empty {
  margin: 6px 0 0;
}
.tag {
  font-size: 10px;
  font-weight: 700;
  padding: 3px 8px;
  border-radius: var(--r-tag);
}
.tag.new {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.tag.end {
  background: var(--gray-1);
  color: var(--gray-5);
}
.tag.due {
  background: var(--danger-soft);
  color: var(--danger);
}
.bcard .stat {
  display: flex;
  align-items: center;
  gap: 11px;
}
.ring {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  position: relative;
}
.ring::after {
  content: '';
  position: absolute;
  inset: 7px;
  background: #fff;
  border-radius: 50%;
}
.ring b {
  position: relative;
  z-index: 2;
  font-size: 12px;
  font-weight: 800;
}
.stat .info {
  flex: 1;
}
.stat .info .occ {
  font-size: 10.5px;
  color: var(--gray-4);
  font-weight: 600;
}
.stat .info .inc {
  font-size: 14px;
  font-weight: 800;
  margin-top: 1px;
}
.bar {
  height: 5px;
  border-radius: 4px;
  background: var(--gray-2);
  margin-top: 6px;
  overflow: hidden;
}
.bar i {
  height: 100%;
  background: var(--accent);
  display: block;
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
.flash-enter-active,
.flash-leave-active {
  transition: opacity 0.25s ease, transform 0.25s ease;
}
.flash-enter-from,
.flash-leave-to {
  opacity: 0;
  transform: translateY(-6px);
}
</style>
