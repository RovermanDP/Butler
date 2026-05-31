<script setup>
// ✎ 수동 수납 처리 모달 (화면 7 · PRD 4.2 B-4).
// 대표 회차 1건의 상태(대기/미납/완납)를 수동 선택해 저장한다. PG·자동 수납 없음 — payments update 만.
// 저장(update)·재조회는 부모(PaymentsTab)가 수행하고, 여기선 선택 UI + 저장중/에러 표시만 담당(SRP).
import { ref } from 'vue'
import { formatWon } from '../lib/format'

const props = defineProps({
  tenantName: { type: String, default: '' },
  unitNo: { type: String, default: '' },
  // 대표 회차: { id, round_no, amount, status }
  payment: { type: Object, required: true },
  saving: { type: Boolean, default: false },
  error: { type: String, default: '' },
})

const emit = defineEmits(['confirm', 'cancel'])

const STATES = ['대기', '미납', '완납']
const STATE_CLASS = { 대기: 'wait', 미납: 'miss', 완납: 'paid' }
const selected = ref(props.payment.status)
</script>

<template>
  <div class="backdrop" @click.self="!saving && emit('cancel')">
    <div class="sheet" role="dialog" aria-modal="true">
      <div class="head">
        <span class="ttl">수동 수납 처리</span>
        <span class="sub">{{ tenantName }} · {{ unitNo }} · {{ payment.round_no }}회차</span>
      </div>

      <div class="amt">{{ formatWon(payment.amount) }}</div>

      <!-- 상태 선택: 대기/미납/완납 세그먼트 -->
      <div class="seg">
        <button
          v-for="s in STATES"
          :key="s"
          type="button"
          class="seg-btn"
          :class="[STATE_CLASS[s], { on: selected === s }]"
          :disabled="saving"
          @click="selected = s"
        >
          {{ s }}
        </button>
      </div>

      <p v-if="error" class="err">{{ error }}</p>

      <div class="foot">
        <button type="button" class="btn ghost" :disabled="saving" @click="emit('cancel')">취소</button>
        <button type="button" class="btn primary" :disabled="saving" @click="emit('confirm', selected)">
          {{ saving ? '저장 중…' : '저장' }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.backdrop {
  position: absolute;
  inset: 0;
  z-index: 12;
  background: rgba(31, 31, 36, 0.32);
  display: flex;
  align-items: flex-end;
}
.sheet {
  width: 100%;
  background: #fff;
  border-radius: 16px 16px 0 0;
  padding: 18px 16px calc(16px + env(safe-area-inset-bottom));
  box-shadow: 0 -4px 20px rgba(31, 31, 36, 0.12);
}
.head {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.head .ttl {
  font-size: 15px;
  font-weight: 800;
  color: var(--ink);
}
.head .sub {
  font-size: 11px;
  color: var(--ink-mute);
  font-weight: 600;
}
.amt {
  font-size: 22px;
  font-weight: 800;
  color: var(--ink);
  margin: 12px 0 14px;
}
.seg {
  display: flex;
  gap: 8px;
}
.seg-btn {
  flex: 1;
  border: 1px solid var(--line);
  background: #fff;
  border-radius: 10px;
  padding: 11px 0;
  font-size: 13px;
  font-weight: 800;
  font-family: inherit;
  color: var(--ink-mute);
  cursor: pointer;
}
.seg-btn:disabled {
  cursor: default;
}
/* 선택된 상태만 상태색으로 채운다(대기=gray / 미납=danger / 완납=ok). */
.seg-btn.on.wait {
  background: var(--gray-1);
  border-color: var(--gray-3);
  color: var(--ink-soft);
}
.seg-btn.on.miss {
  background: var(--danger-soft);
  border-color: var(--danger);
  color: var(--danger);
}
.seg-btn.on.paid {
  background: var(--ok-soft);
  border-color: var(--ok);
  color: var(--ok);
}
.err {
  color: var(--danger);
  font-size: 12px;
  font-weight: 600;
  margin: 12px 0 0;
}
.foot {
  display: flex;
  gap: 9px;
  margin-top: 16px;
}
.btn {
  flex: 1;
  border: none;
  border-radius: var(--r-button);
  padding: 13px 0;
  font-size: 13.5px;
  font-weight: 800;
  font-family: inherit;
  cursor: pointer;
}
.btn:disabled {
  opacity: 0.6;
  cursor: default;
}
.btn.ghost {
  background: var(--gray-1);
  color: var(--ink-soft);
}
.btn.primary {
  background: var(--accent);
  color: #fff;
}
</style>
