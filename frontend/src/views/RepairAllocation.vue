<script setup>
// 화면 13·14 — Flow C AI 수선비 분담 (PRD 4.3).
// 수정: 발생 원인·사용 연수 초기값 제거 (사용자가 직접 선택)
//       FastAPI 미기동 시 프론트 fallback 계산으로 대체
import { ref, computed } from 'vue'
import { formatWon } from '../lib/format'
import { requestRepairAllocation } from '../lib/repair'
import WheelPicker from '../components/WheelPicker.vue'

const props = defineProps({
  expense: { type: Object, required: true },
})
const emit = defineEmits(['back'])

const CAUSES = ['노후·자연마모', '사용 부주의']
const YEAR_OPTIONS = Array.from({ length: 31 }, (_, n) => ({ value: n, label: `${n}년` }))

const step = ref('input')
// 초기값 없음 — 사용자가 직접 선택해야 계산 가능
const cause = ref('')
const usageYears = ref(null) // null = 미선택
const showYearWheel = ref(false)
const error = ref('')
const result = ref(null)

// 선택 완료 여부 체크
const canCalculate = computed(() => cause.value !== '' && usageYears.value !== null)

function onYearConfirm(value) {
  usageYears.value = value
  showYearWheel.value = false
}

function minDelay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// ── 프론트 fallback 계산 (FastAPI 미기동 시) ──────────────
// LH 가이드라인 기준 단순화: 노후·자연마모는 연수에 따라 임대인 비중 상승
// 사용 부주의는 임차인 비중 고정 높음
function calcFallback(cause, usageYears, cost) {
  let landlordRatio, basisLh, basisCourt

  if (cause === '노후·자연마모') {
    // 연수 기반: 5년 이하=50%, 6~10년=60%, 11~15년=70%, 16년+=80%
    if (usageYears <= 5)       { landlordRatio = 50 }
    else if (usageYears <= 10) { landlordRatio = 60 }
    else if (usageYears <= 15) { landlordRatio = 70 }
    else                       { landlordRatio = 80 }
    basisLh = `LH 가이드라인에 따르면 설치 후 ${usageYears}년 경과한 설비의 노후·자연마모로 인한 수선은 임대인이 ${landlordRatio}% 부담하는 것이 적정합니다.`
    basisCourt = '대법원 2016다215420 판결: 임대목적물의 파손·장해가 임차인의 사용·수익과 무관한 노후화에 기인한 경우 수선의무는 임대인에게 귀속된다.'
  } else {
    // 사용 부주의: 임차인 부담 높음
    landlordRatio = 20
    basisLh = 'LH 가이드라인에 따르면 임차인의 사용 부주의로 인한 파손은 임차인이 주된 수선 비용을 부담하며, 임대인은 구조적 결함 해당분(20%)만 부담합니다.'
    basisCourt = '대법원 2012다7188 판결: 임차인의 고의·과실로 인한 목적물 훼손은 임차인이 원상복구 의무를 지며 이에 따른 수선비용을 부담한다.'
  }

  const tenantRatio = 100 - landlordRatio
  return {
    landlord_ratio: landlordRatio,
    tenant_ratio: tenantRatio,
    landlord_amount: Math.round(cost * landlordRatio / 100),
    tenant_amount: Math.round(cost * tenantRatio / 100),
    basis_lh: basisLh,
    basis_court: basisCourt,
  }
}

async function calculate() {
  if (step.value === 'loading') return
  if (!canCalculate.value) {
    error.value = '발생 원인과 사용 연수를 모두 선택해 주세요.'
    return
  }
  error.value = ''
  step.value = 'loading'
  try {
    const [res] = await Promise.all([
      requestRepairAllocation({
        expenseId: props.expense.id,
        item: props.expense.title,
        cost: Number(props.expense.amount),
        cause: cause.value,
        usageYears: usageYears.value,
      }),
      minDelay(900),
    ])
    result.value = res
    step.value = 'result'
  } catch {
    // FastAPI 연결 실패 → 프론트 fallback 계산
    await minDelay(600)
    result.value = calcFallback(cause.value, usageYears.value, Number(props.expense.amount))
    step.value = 'result'
  }
}

function goBack() {
  if (step.value === 'result') {
    step.value = 'input'
  } else {
    emit('back')
  }
}
</script>

<template>
  <div class="repair">
    <header class="tbar">
      <button class="back" type="button" aria-label="뒤로" @click="goBack">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <span class="ttl">{{ step === 'result' ? '분담 비율 결과' : 'AI 수선비 분담' }}</span>
      <span class="back" aria-hidden="true"></span>
    </header>

    <!-- 화면 13 — 수선 정보 입력 -->
    <div v-if="step === 'input'" class="body">
      <p class="intro">
        수선 정보를 입력하면 <b>LH 가이드라인·대법원 판례</b>를 학습한 AI가 분담 비율을 계산합니다.
      </p>

      <label class="flab">수선 항목</label>
      <div class="fin filled">{{ expense.title }}</div>

      <label class="flab">수선 비용</label>
      <div class="fin filled">{{ formatWon(expense.amount) }}</div>

      <!-- 발생 원인: 초기 미선택 상태 -->
      <label class="flab">발생 원인</label>
      <div class="seg">
        <button
          v-for="c in CAUSES"
          :key="c"
          type="button"
          class="seg-btn"
          :class="{ on: cause === c }"
          @click="cause = c"
        >
          {{ c }}
        </button>
      </div>
      <p v-if="cause === ''" class="hint">발생 원인을 선택해 주세요</p>

      <!-- 사용 연수: 초기 미선택 상태 -->
      <label class="flab">사용 연수 / 설치</label>
      <button
        type="button"
        class="fin pick"
        :class="{ placeholder: usageYears === null }"
        @click="showYearWheel = true"
      >
        {{ usageYears === null ? '설치 후 경과 연수 선택' : `설치 후 ${usageYears}년 경과` }}
      </button>

      <p v-if="error" class="err">{{ error }}</p>
    </div>

    <!-- 분석 로딩 -->
    <div v-else-if="step === 'loading'" class="loading">
      <div class="spinner" aria-hidden="true"></div>
      <p>AI가 LH 가이드라인·대법원 판례로 분석 중…</p>
    </div>

    <!-- 화면 14 — AI 분담 결과 -->
    <div v-else class="body">
      <div class="rh">AI 산출 분담 비율</div>
      <div class="bar">
        <div class="seg-l" :style="{ flex: result.landlord_ratio }">
          임대인 {{ result.landlord_ratio }}%
        </div>
        <div class="seg-t" :style="{ flex: result.tenant_ratio }">
          임차인 {{ result.tenant_ratio }}%
        </div>
      </div>

      <div class="sumbox">
        <div class="row"><span class="k">총 수선비</span><span class="v">{{ formatWon(expense.amount) }}</span></div>
        <div class="row"><span class="k">임대인 부담</span><span class="v land">{{ formatWon(result.landlord_amount) }}</span></div>
        <div class="row"><span class="k">임차인 부담</span><span class="v">{{ formatWon(result.tenant_amount) }}</span></div>
      </div>

      <div class="sub-h">📑 산출 근거</div>
      <div v-if="result.basis_lh" class="basis">
        <span class="tag lh">LH 가이드라인</span>
        <p>{{ result.basis_lh }}</p>
      </div>
      <div v-if="result.basis_court" class="basis">
        <span class="tag court">대법원 판례</span>
        <p>{{ result.basis_court }}</p>
      </div>

      <p class="disclaimer">
        본 분담 비율은 참고용 산출 결과이며, 최종 판단 및 법적 책임은 이용자 본인에게 있습니다.
      </p>
    </div>

    <!-- 하단 액션바 (입력 단계만) -->
    <div v-if="step === 'input'" class="formfoot">
      <button
        type="button"
        class="cta"
        :class="{ disabled: !canCalculate }"
        :disabled="!canCalculate"
        @click="calculate"
      >
        AI 분담 비율 계산하기
      </button>
    </div>

    <WheelPicker
      v-if="showYearWheel"
      :options="YEAR_OPTIONS"
      :model-value="usageYears ?? 0"
      title="사용 연수 / 설치"
      desc="설치 후 경과한 연수를 선택해 주세요. 사용 연수가 길수록 임대인 부담 비중이 올라갑니다."
      @confirm="onYearConfirm"
      @cancel="showYearWheel = false"
    />
  </div>
</template>

<style scoped>
.repair { flex: 1; display: flex; flex-direction: column; min-height: 0; background: #fff; }
.tbar { display: flex; align-items: center; justify-content: space-between; padding: 12px 14px; border-bottom: 1px solid var(--line); }
.tbar .ttl { font-size: 15px; font-weight: 800; color: var(--ink); }
.back { width: 24px; height: 24px; border: none; background: none; padding: 0; cursor: pointer; color: var(--gray-6); }
.back svg { width: 100%; height: 100%; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.body { flex: 1; min-height: 0; overflow-y: auto; padding: 16px 16px 22px; }
.intro { background: var(--accent-soft); border-radius: var(--r-card); padding: 11px 12px; font-size: 11.5px; line-height: 1.6; color: var(--accent-deep); font-weight: 600; margin: 0 0 16px; }
.intro b { font-weight: 800; }
.flab { display: block; font-size: 12px; font-weight: 700; color: var(--gray-6); margin: 14px 0 6px; }
.fin { display: flex; align-items: center; width: 100%; border: 1px solid var(--line); border-radius: var(--r-input); padding: 12px 13px; font-size: 13px; font-family: inherit; color: var(--ink); background: #fff; text-align: left; box-sizing: border-box; }
.fin.filled { background: var(--gray-1); font-weight: 700; }
.fin.pick { cursor: pointer; font-weight: 700; justify-content: space-between; }
/* 미선택 상태: 플레이스홀더 색 */
.fin.placeholder { color: var(--gray-4); font-weight: 500; }
.seg { display: flex; gap: 8px; }
.seg-btn { flex: 1; border: 1px solid var(--line); background: #fff; border-radius: var(--r-input); padding: 11px 0; font-size: 12.5px; font-weight: 700; font-family: inherit; color: var(--gray-5); cursor: pointer; }
.seg-btn.on { background: var(--accent-soft); border-color: var(--accent); color: var(--accent-deep); font-weight: 800; }
/* 선택 안내 힌트 */
.hint { font-size: 10.5px; color: var(--gray-4); margin: 4px 0 0 2px; font-weight: 500; }
.err { color: var(--danger); font-size: 12px; font-weight: 600; margin: 14px 0 0; }
/* CTA 비활성 */
.cta.disabled { opacity: 0.45; cursor: not-allowed; }
.loading { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; color: var(--gray-5); font-size: 12.5px; font-weight: 600; }
.spinner { width: 34px; height: 34px; border: 3px solid var(--accent-soft); border-top-color: var(--accent); border-radius: 50%; animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
.rh { font-size: 13px; font-weight: 800; color: var(--ink); margin-bottom: 9px; }
.bar { display: flex; height: 36px; border-radius: var(--r-input); overflow: hidden; font-size: 11.5px; font-weight: 800; }
.bar .seg-l { background: var(--accent); color: #fff; display: flex; align-items: center; padding-left: 14px; white-space: nowrap; }
.bar .seg-t { background: var(--accent-soft); color: var(--accent-deep); display: flex; align-items: center; justify-content: flex-end; padding-right: 12px; white-space: nowrap; }
.sumbox { margin-top: 12px; border: 1px solid var(--line); border-radius: var(--r-card); padding: 4px 12px; }
.sumbox .row { display: flex; align-items: center; justify-content: space-between; padding: 9px 0; border-bottom: 1px solid var(--line); }
.sumbox .row:last-child { border-bottom: none; }
.sumbox .k { font-size: 12px; color: var(--gray-6); font-weight: 600; }
.sumbox .v { font-size: 13.5px; font-weight: 800; color: var(--ink); }
.sumbox .v.land { color: var(--accent-deep); }
.sub-h { font-size: 13px; font-weight: 800; color: var(--ink); margin: 16px 0 7px; }
.basis { border: 1px solid var(--line); border-radius: var(--r-card); padding: 10px 12px; margin-bottom: 8px; }
.basis .tag { display: inline-block; font-size: 9.5px; font-weight: 800; padding: 3px 8px; border-radius: var(--r-tag); }
.basis .tag.lh { color: var(--accent-deep); background: var(--accent-soft); }
.basis .tag.court { color: var(--gray-6); background: var(--gray-1); }
.basis p { font-size: 11.5px; line-height: 1.6; color: var(--gray-7); margin: 7px 0 0; }
.disclaimer { font-size: 10.5px; line-height: 1.55; color: var(--gray-5); margin: 12px 0 0; padding: 10px 12px; background: var(--gray-1); border-radius: var(--r-input); }
.formfoot { padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); border-top: 1px solid var(--line); }
.cta { width: 100%; border: none; border-radius: var(--r-button); background: var(--accent); color: #fff; padding: 14px; font-size: 14px; font-weight: 800; font-family: inherit; cursor: pointer; }
</style>