<script setup>
// 화면 6 — 건물 상세 · 세입자 탭 (PRD 4.2 B-3).
// phone 보유 세입자(데모 김동락 + Flow E 등록분) 카드 리스트. 채움 세입자는 lib/detail 에서 이미 걸러짐.
// 표시만 담당(데이터 in / 이벤트 out). 계약 연장·종료는 미구현 플로우라 teaser 만 emit.
import { formatWon } from '../lib/format'
import { formatDotYmd } from '../lib/contractDates'

defineProps({
  tenants: { type: Array, default: () => [] },
  buildingName: { type: String, default: '' },
})

const emit = defineEmits(['teaser'])

// 관리비는 0 이면 행을 숨긴다(전세 등). 월세 행은 월세계약에서만 노출.
function teaser(label) {
  emit('teaser', label)
}
</script>

<template>
  <div class="tenants">
    <p v-if="!tenants.length" class="empty">등록된 세입자가 없습니다.</p>

    <div v-for="t in tenants" :key="t.id" class="tcard">
      <div class="thead">
        <span class="nm">{{ t.name }}</span>
        <span class="pill" :class="{ off: t.primary.status !== '계약중' }">{{ t.primary.status }}</span>
        <span class="acts">
          <span class="cbtn call" aria-hidden="true">📞</span>
          <span class="cbtn msg" aria-hidden="true">💬</span>
        </span>
      </div>

      <button
        v-if="t.contractCount > 1"
        class="linkrow"
        type="button"
        @click="teaser('다른 계약서')"
      >
        📄 다른 계약서 총 <b>&nbsp;{{ t.contractCount }}&nbsp;</b>건 <span class="arr">›</span>
      </button>

      <div v-if="t.memo" class="memo">{{ t.memo }}<span class="pen" aria-hidden="true">✎</span></div>

      <div class="sub-h">계약정보</div>
      <div class="contract">
        <div class="ph"><i class="home" aria-hidden="true">🏠</i>{{ buildingName }} / {{ t.primary.unit_no }}</div>
        <div class="dt">{{ formatDotYmd(t.primary.contract_start) }} ~ {{ formatDotYmd(t.primary.contract_end) }}</div>
        <div class="cact">
          <button type="button" @click="teaser('계약 연장')">계약 연장 ›</button>
          <button type="button" @click="teaser('계약 종료')">계약 종료 ›</button>
        </div>
      </div>

      <div class="money">
        <div class="row">
          <span class="k">보증금</span>
          <span class="v">{{ formatWon(t.primary.deposit) }}</span>
        </div>
        <div v-if="t.primary.lease_type === '월세'" class="row">
          <span class="k">월세 <span v-if="t.primary.rent_vat" class="vat">부가세 포함</span></span>
          <span class="v">{{ formatWon(t.primary.monthly_rent) }}</span>
        </div>
        <div v-if="t.primary.maintenance_fee > 0" class="row">
          <span class="k">관리비 <span v-if="t.primary.maintenance_vat" class="vat">부가세 포함</span></span>
          <span class="v">{{ formatWon(t.primary.maintenance_fee) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.empty {
  text-align: center;
  color: var(--gray-4);
  font-size: 12.5px;
  padding: 40px 0;
}
/* 세입자 여러 명일 때 카드 사이를 얇은 선으로 구분. */
.tcard + .tcard {
  margin-top: 14px;
  padding-top: 16px;
  border-top: 1px solid var(--gray-2);
}
.thead {
  display: flex;
  align-items: center;
  gap: 9px;
  margin: 4px 0 13px;
}
.thead .nm {
  font-size: 17px;
  font-weight: 800;
  color: var(--ink);
}
.pill {
  font-size: 10px;
  font-weight: 700;
  padding: 3px 9px;
  border-radius: 8px;
  background: var(--ok);
  color: #fff;
}
.pill.off {
  background: var(--gray-3);
}
.thead .acts {
  margin-left: auto;
  display: flex;
  gap: 8px;
}
.thead .acts .cbtn {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--accent-soft);
  display: grid;
  place-items: center;
  font-size: 13px;
}
.linkrow {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: #fff;
  padding: 10px 12px;
  font-size: 12px;
  color: var(--ink);
  font-weight: 600;
  display: flex;
  align-items: center;
  cursor: pointer;
  font-family: inherit;
}
.linkrow .arr {
  margin-left: auto;
  color: var(--gray-4);
}
.memo {
  background: var(--gray-1);
  border-radius: 12px;
  padding: 11px 12px 30px;
  margin-top: 10px;
  font-size: 11.5px;
  line-height: 1.55;
  color: var(--ink-soft);
  position: relative;
  min-height: 58px;
}
.memo .pen {
  position: absolute;
  bottom: 10px;
  right: 11px;
  color: var(--accent);
  font-size: 13px;
}
.sub-h {
  font-size: 14px;
  font-weight: 800;
  margin: 16px 0 8px;
  color: var(--ink);
}
.contract {
  font-size: 12px;
}
.contract .ph {
  display: flex;
  align-items: center;
  gap: 7px;
  font-weight: 700;
  color: var(--ink);
}
.contract .ph i {
  width: 20px;
  height: 20px;
  border-radius: 7px;
  background: var(--accent);
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 11px;
  flex: 0 0 auto;
  font-style: normal;
}
.contract .dt {
  color: var(--ink-mute);
  font-size: 11px;
  margin: 3px 0 10px 27px;
}
.contract .cact {
  display: flex;
  gap: 8px;
  margin-left: 27px;
}
.contract .cact button {
  flex: 1;
  border: 1px solid var(--line);
  border-radius: 10px;
  background: #fff;
  padding: 9px 0;
  font-size: 11.5px;
  font-weight: 700;
  color: var(--accent-deep);
  font-family: inherit;
  cursor: pointer;
}
.money {
  margin-top: 11px;
}
.money .row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 7px 0;
}
.money .k {
  font-size: 12px;
  color: var(--ink-mute);
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: 5px;
}
.money .v {
  font-size: 12.5px;
  font-weight: 800;
  color: var(--ink);
}
.vat {
  font-size: 9.5px;
  background: var(--warn-soft);
  color: var(--warn);
  padding: 2px 6px;
  border-radius: 7px;
  font-weight: 700;
}
</style>
