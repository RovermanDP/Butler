<script setup>
import { computed } from 'vue'
import { formatWon } from '../lib/format'
import { formatShortDate } from '../lib/contractDates'

// 화면 10k·10l — 납부 내역 확인(첫 납부일~계약 종료일, 회차별).
// '확인 완료' 시 부모(Step3)의 납부 내역 필드가 '확인완료'로 잠긴다(재선택 불가).
// 책임은 '전달받은 회차 목록을 표로 보여주고 확인을 받는 것'(SRP). 회차 생성은 lib/payment(결정적)가 담당.
const props = defineProps({
  rows: { type: Array, default: () => [] }, // [{ round_no, due_date, amount, status }]
  paymentDay: { type: Number, default: 1 },
  leaseType: { type: String, default: '월세' }, // 배지 '월세'|'전세'
  paymentTiming: { type: String, default: '선불' }, // 배지 '선불'|'후불'
  amount: { type: Number, default: 0 }, // 매월 납부액(=매월 입금 예정 총액)
})

const emit = defineEmits(['confirm', 'cancel'])

const missRows = computed(() => props.rows.filter((r) => r.status === '미납'))
const summary = computed(() => ({
  totalRounds: props.rows.length,
  monthly: props.amount,
  missCount: missRows.value.length,
  missAmount: missRows.value.reduce((sum, r) => sum + (Number(r.amount) || 0), 0),
}))

// 상태별 행 스타일 클래스. '대기'/'미납'만 발생(시드 규칙) — '완납'은 등록 후 Flow B 영역.
function statusClass(status) {
  if (status === '미납') return 'miss'
  if (status === '완납' || status === '납부') return 'paid'
  return 'wait'
}
</script>

<template>
  <div class="overlay">
    <div class="scr">
      <div class="tbar">
        <button class="ico back" type="button" aria-label="뒤로" @click="emit('cancel')">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M15 18L9 12L15 6" />
          </svg>
        </button>
        <span class="ttl">납부 내역 확인</span>
        <span class="ico"></span>
      </div>

      <div class="body">
        <!-- 입금 예정일 + 계약형태/선불후불 배지 -->
        <div class="firstpay-card">
          <span class="dlabel">입금 예정일 <b>{{ paymentDay }}일</b></span>
          <span class="badges">
            <span class="bdg wm">{{ leaseType }}</span>
            <span class="bdg pre">{{ paymentTiming }}</span>
          </span>
        </div>

        <!-- 요약: 총 회차 / 매월 납부액 / 미납 -->
        <div class="paysum">
          <div class="r">
            <span class="k">총 납부회차</span><span class="v">{{ summary.totalRounds }} 회</span>
          </div>
          <div class="r">
            <span class="k">매월 납부액</span><span class="v">{{ formatWon(summary.monthly) }}</span>
          </div>
          <div class="r">
            <span class="k">미납 <span class="cnt">{{ summary.missCount }} 건</span></span>
            <span class="v" :class="{ red: summary.missCount > 0 }">{{ formatWon(summary.missAmount) }}</span>
          </div>
        </div>

        <!-- 회차표 헤더 -->
        <div class="list-h">
          <span class="ci-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M5 8H19V18C19 18.55 18.55 19 18 19H6C5.45 19 5 18.55 5 18V8Z" />
              <path d="M4 6H20" /><path d="M9.5 12.5L11 14L14.5 10.5" />
            </svg>
          </span>
          <b>납부 내역</b>
        </div>

        <!-- 회차 행 (첫 납부일~종료일 매월) -->
        <div v-if="rows.length === 0" class="empty">생성된 회차가 없습니다. 계약기간·금액을 확인해주세요.</div>
        <div v-for="row in rows" :key="row.round_no" class="payrow">
          <span class="stt" :class="statusClass(row.status)">{{ row.status }}</span>
          <span class="cyc">{{ row.round_no }}회차</span>
          <span class="amt" :class="{ wait: row.status !== '완납' && row.status !== '납부' }">
            <b>{{ formatWon(row.amount) }}</b>
            <small>{{ formatShortDate(row.due_date) }}</small>
          </span>
        </div>

        <div class="info-hint">
          <span class="ex">!</span>등록 후 계약 정보 탭에서 회차를 수정할 수 있어요
        </div>
      </div>

      <div class="formfoot">
        <!-- 회차 0건이면 확인 완료 불가 — '계약 종료일까지 회차별 표시'를 만족하지 못한 표를 잠그지 않는다. -->
        <button class="ff-next" type="button" :disabled="rows.length === 0" @click="emit('confirm')">
          확인 완료
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 전체 화면 오버레이(부모 .scr 위 흰 화면). 회차표 전용 chrome. */
.overlay {
  position: absolute;
  inset: 0;
  z-index: 11;
  background: #fff;
}
.scr {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  color: var(--ink);
  overflow: hidden;
}
.tbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 15px 6px;
}
.tbar .ttl {
  font-size: 15px;
  font-weight: 800;
}
.tbar .ico {
  width: 24px;
  height: 24px;
  color: var(--gray-6);
}
.tbar .back {
  border: none;
  background: none;
  cursor: pointer;
  padding: 0;
}
.tbar .back svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.body {
  flex: 1;
  overflow-y: auto;
  padding: 8px 15px 18px;
}

.firstpay-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 13px 14px;
}
.firstpay-card .dlabel {
  font-size: 13px;
  font-weight: 700;
  color: var(--ink);
}
.firstpay-card .dlabel b {
  color: var(--accent);
}
.firstpay-card .badges {
  display: flex;
  gap: 5px;
}
.firstpay-card .bdg {
  font-size: 10px;
  font-weight: 800;
  padding: 3px 8px;
  border-radius: 7px;
}
.firstpay-card .bdg.wm {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.firstpay-card .bdg.pre {
  background: var(--gray-1);
  color: var(--gray-6);
}

.paysum {
  background: var(--gray-1);
  border-radius: 12px;
  padding: 4px 14px;
  margin-top: 10px;
}
.paysum .r {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 11px 0;
}
.paysum .r + .r {
  border-top: 1px solid var(--line);
}
.paysum .k {
  font-size: 12px;
  color: var(--gray-6);
  font-weight: 600;
}
.paysum .v {
  font-size: 14px;
  font-weight: 800;
  color: var(--ink);
}
.paysum .v.red {
  color: var(--danger);
}
.paysum .cnt {
  font-size: 10px;
  color: #fff;
  background: var(--danger);
  padding: 2px 7px;
  border-radius: 7px;
  margin-left: 5px;
  font-weight: 800;
}

.list-h {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 16px;
}
.list-h b {
  color: var(--accent);
  font-size: 14px;
  font-weight: 800;
}
.list-h .ci-icon {
  width: 22px;
  height: 22px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.list-h .ci-icon svg {
  width: 21px;
  height: 21px;
  stroke: var(--accent);
  stroke-width: 1.8;
  fill: none;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.payrow {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 11px 0;
  border-bottom: 1px solid var(--line);
}
.payrow .stt {
  font-size: 10px;
  font-weight: 800;
  padding: 4px 8px;
  border-radius: 8px;
  flex: 0 0 auto;
}
.payrow .stt.paid {
  background: var(--ok-soft);
  color: var(--ok);
}
.payrow .stt.wait {
  background: var(--gray-1);
  color: var(--gray-6);
}
.payrow .stt.miss {
  background: var(--danger-soft);
  color: var(--danger);
}
.payrow .cyc {
  font-size: 13px;
  font-weight: 700;
  color: var(--ink);
}
.payrow .amt {
  margin-left: auto;
  text-align: right;
}
.payrow .amt b {
  font-size: 13px;
  font-weight: 800;
  color: var(--ink);
  display: block;
}
.payrow .amt.wait b {
  color: var(--gray-4);
}
.payrow .amt small {
  font-size: 10.5px;
  color: var(--gray-4);
}

.empty {
  padding: 24px 4px;
  text-align: center;
  font-size: 12px;
  color: var(--gray-5);
  font-weight: 600;
}

.info-hint {
  background: var(--gray-1);
  border-radius: 10px;
  padding: 12px 13px;
  font-size: 11px;
  line-height: 1.55;
  color: var(--gray-6);
  font-weight: 600;
  margin-top: 14px;
  display: flex;
  gap: 7px;
  align-items: flex-start;
}
.info-hint .ex {
  width: 15px;
  height: 15px;
  border-radius: 50%;
  background: var(--gray-3);
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  font-weight: 800;
  flex: 0 0 auto;
  margin-top: 1px;
}

.formfoot {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  padding: 10px 14px;
  border-top: 1px solid var(--line);
  background: #fff;
}
.formfoot .ff-next {
  flex: 1;
  text-align: center;
  border-radius: 12px;
  padding: 14px 0;
  background: var(--accent);
  color: #fff;
  font-weight: 800;
  font-size: 14px;
  border: none;
  cursor: pointer;
  font-family: inherit;
}
.formfoot .ff-next:disabled {
  background: var(--gray-3);
  cursor: not-allowed;
}
</style>
