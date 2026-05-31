<script setup>
// 화면 13·14 — Flow C AI 수선비 분담 (PRD 4.3).
// 한 화면 안에서 step 만 전환한다: input(13, 수선 정보 입력) → loading(분석) → result(14, 분담 결과·근거).
// 진입은 지출 탭 수리비 행의 'AI 분담 ▸'(ExpensesTab → BuildingDetail → App). expense 를 prop 으로 받는다.
// AI 산출은 FastAPI 경유(lib/repair). 항목·비용은 expense 에서 prefill, 원인/연수는 사용자 입력(핵심 변수).
// 대표 시나리오(냉장고/노후·자연마모/7년 → 70:30)는 백엔드 고정이라 키 없이도 시연 안정.
import { ref } from 'vue'
import { formatWon } from '../lib/format'
import { requestRepairAllocation } from '../lib/repair'
import WheelPicker from '../components/WheelPicker.vue'

const props = defineProps({
  // 지출 항목: { id, title, amount, ... } — 수선 항목·비용 prefill 소스.
  expense: { type: Object, required: true },
})

// back: 화면 13에서 뒤로 → 건물 상세(지출 탭) 복귀.
const emit = defineEmits(['back'])

const CAUSES = ['노후·자연마모', '사용 부주의']
// 사용 연수 휠 옵션(0~30년). 기본 7년(대표 시나리오).
const YEAR_OPTIONS = Array.from({ length: 31 }, (_, n) => ({ value: n, label: `${n}년` }))

const step = ref('input') // 'input' | 'loading' | 'result'
const cause = ref('노후·자연마모')
const usageYears = ref(7)
const showYearWheel = ref(false)
const error = ref('')
const result = ref(null) // { landlord_ratio, tenant_ratio, landlord_amount, tenant_amount, basis_lh, basis_court }

function onYearConfirm(value) {
  usageYears.value = value
  showYearWheel.value = false
}

// 분석 로딩이 너무 빨리 지나가지 않도록 최소 노출 시간(와이어프레임 "분석 1~2초").
function minDelay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function calculate() {
  if (step.value === 'loading') return // 연속 클릭 방지
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
  } catch (e) {
    error.value = e?.message || '분담 비율 산출에 실패했습니다.'
    step.value = 'input' // 입력 화면으로 돌려 재시도 가능하게
  }
}

// 헤더 뒤로: 결과 화면이면 입력으로, 입력 화면이면 상세로 나간다.
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
    <!-- 상단 바: 단계별 타이틀 -->
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

      <label class="flab">사용 연수 / 설치</label>
      <button type="button" class="fin pick" @click="showYearWheel = true">
        설치 후 {{ usageYears }}년 경과
      </button>

      <p v-if="error" class="err">{{ error }}</p>
    </div>

    <!-- 분석 로딩 -->
    <div v-else-if="step === 'loading'" class="loading">
      <div class="spinner" aria-hidden="true"></div>
      <p>AI가 LH 가이드라인·판례로 분석 중…</p>
    </div>

    <!-- 화면 14 — AI 분담 결과 · 근거 -->
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
        <div class="row">
          <span class="k">총 수선비</span><span class="v">{{ formatWon(expense.amount) }}</span>
        </div>
        <div class="row">
          <span class="k">임대인 부담</span>
          <span class="v land">{{ formatWon(result.landlord_amount) }}</span>
        </div>
        <div class="row">
          <span class="k">임차인 부담</span>
          <span class="v">{{ formatWon(result.tenant_amount) }}</span>
        </div>
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

    <!-- 하단 고정 액션바 (입력 단계에서만) -->
    <div v-if="step === 'input'" class="formfoot">
      <button type="button" class="cta" @click="calculate">AI 분담 비율 계산하기</button>
    </div>

    <!-- 사용 연수 휠 피커(재사용) -->
    <WheelPicker
      v-if="showYearWheel"
      :options="YEAR_OPTIONS"
      :model-value="usageYears"
      title="사용 연수 / 설치"
      desc="설치 후 경과한 연수를 선택해 주세요. 사용 연수가 길수록 임대인 부담 비중이 올라갑니다."
      @confirm="onYearConfirm"
      @cancel="showYearWheel = false"
    />
  </div>
</template>

<style scoped>
.repair {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
  background: #fff;
}

/* 상단 바 */
.tbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  border-bottom: 1px solid var(--line);
}
.tbar .ttl {
  font-size: 15px;
  font-weight: 800;
  color: var(--ink);
}
.back {
  width: 24px;
  height: 24px;
  border: none;
  background: none;
  padding: 0;
  cursor: pointer;
  color: var(--gray-6);
}
.back svg {
  width: 100%;
  height: 100%;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
}

/* 본문(스크롤 영역) */
.body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 16px 16px 22px;
}

.intro {
  background: var(--accent-soft);
  border-radius: var(--r-card);
  padding: 11px 12px;
  font-size: 11.5px;
  line-height: 1.6;
  color: var(--accent-deep);
  font-weight: 600;
  margin: 0 0 16px;
}
.intro b {
  font-weight: 800;
}

/* 입력 필드 */
.flab {
  display: block;
  font-size: 12px;
  font-weight: 700;
  color: var(--gray-6);
  margin: 14px 0 6px;
}
.flab:first-of-type {
  margin-top: 0;
}
.fin {
  display: flex;
  align-items: center;
  width: 100%;
  border: 1px solid var(--line);
  border-radius: var(--r-input);
  padding: 12px 13px;
  font-size: 13px;
  font-family: inherit;
  color: var(--ink);
  background: #fff;
  text-align: left;
}
/* prefill(읽기전용) 필드는 옅은 배경으로 비입력임을 시사 */
.fin.filled {
  background: var(--gray-1);
  font-weight: 700;
}
.fin.pick {
  cursor: pointer;
  font-weight: 700;
  justify-content: space-between;
}

/* 발생 원인 세그먼트(단일 accent — 선택만 강조) */
.seg {
  display: flex;
  gap: 8px;
}
.seg-btn {
  flex: 1;
  border: 1px solid var(--line);
  background: #fff;
  border-radius: var(--r-input);
  padding: 11px 0;
  font-size: 12.5px;
  font-weight: 700;
  font-family: inherit;
  color: var(--gray-5);
  cursor: pointer;
}
.seg-btn.on {
  background: var(--accent-soft);
  border-color: var(--accent);
  color: var(--accent-deep);
  font-weight: 800;
}

.err {
  color: var(--danger);
  font-size: 12px;
  font-weight: 600;
  margin: 14px 0 0;
}

/* 로딩 */
.loading {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  color: var(--gray-5);
  font-size: 12.5px;
  font-weight: 600;
}
.spinner {
  width: 34px;
  height: 34px;
  border: 3px solid var(--accent-soft);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

/* 결과 — 비율 막대 */
.rh {
  font-size: 13px;
  font-weight: 800;
  color: var(--ink);
  margin-bottom: 9px;
}
.bar {
  display: flex;
  height: 36px;
  border-radius: var(--r-input);
  overflow: hidden;
  font-size: 11.5px;
  font-weight: 800;
}
.bar .seg-l {
  background: var(--accent);
  color: #fff;
  display: flex;
  align-items: center;
  padding-left: 14px;
  white-space: nowrap;
}
.bar .seg-t {
  background: var(--accent-soft);
  color: var(--accent-deep);
  display: flex;
  align-items: center;
  justify-content: flex-end;
  padding-right: 12px;
  white-space: nowrap;
}

/* 결과 — 금액 요약 */
.sumbox {
  margin-top: 12px;
  border: 1px solid var(--line);
  border-radius: var(--r-card);
  padding: 4px 12px;
}
.sumbox .row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 9px 0;
  border-bottom: 1px solid var(--line);
}
.sumbox .row:last-child {
  border-bottom: none;
}
.sumbox .k {
  font-size: 12px;
  color: var(--gray-6);
  font-weight: 600;
}
.sumbox .v {
  font-size: 13.5px;
  font-weight: 800;
  color: var(--ink);
}
.sumbox .v.land {
  color: var(--accent-deep);
}

/* 결과 — 산출 근거 */
.sub-h {
  font-size: 13px;
  font-weight: 800;
  color: var(--ink);
  margin: 16px 0 7px;
}
.basis {
  border: 1px solid var(--line);
  border-radius: var(--r-card);
  padding: 10px 12px;
  margin-bottom: 8px;
}
.basis .tag {
  display: inline-block;
  font-size: 9.5px;
  font-weight: 800;
  padding: 3px 8px;
  border-radius: var(--r-tag);
}
.basis .tag.lh {
  color: var(--accent-deep);
  background: var(--accent-soft);
}
.basis .tag.court {
  color: var(--gray-6);
  background: var(--gray-1);
}
.basis p {
  font-size: 11.5px;
  line-height: 1.6;
  color: var(--gray-7);
  margin: 7px 0 0;
}

/* 결과 — 면책 문구(필수) */
.disclaimer {
  font-size: 10.5px;
  line-height: 1.55;
  color: var(--gray-5);
  margin: 12px 0 0;
  padding: 10px 12px;
  background: var(--gray-1);
  border-radius: var(--r-input);
}

/* 하단 고정 액션바 */
.formfoot {
  padding: 12px 16px calc(12px + env(safe-area-inset-bottom));
  border-top: 1px solid var(--line);
}
.cta {
  width: 100%;
  border: none;
  border-radius: var(--r-button);
  background: var(--accent);
  color: #fff;
  padding: 14px;
  font-size: 14px;
  font-weight: 800;
  font-family: inherit;
  cursor: pointer;
}
</style>
