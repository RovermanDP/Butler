<script setup>
import { reactive, ref, computed, nextTick } from 'vue'
import { addOneYear } from '../lib/contractDates'
import { monthlyTotal } from '../lib/contractAmount'
import { formatWon } from '../lib/format'
import DatePickerModal from '../components/DatePickerModal.vue'

// 화면 10a~10h — Flow E 세입자 등록 위저드 · Step1(세입자 정보) + Step2(계약 정보).
// 한 '세입자 등록' 화면 안에서 스텝만 전환한다(tbar·stepdots·하단 액션바 chrome 공유).
//   Step1(10a~10d): 개인/사업자 토글로 하단 섹션 분기(PRD 4.5 E-2).
//   Step2(10e~10h): 월세/전세 토글로 월세 row 동적 추가·제거 + 매월 입금 예정 총액 자동 합산(E-3).
// 이 세션 범위 = Step1·Step2. [다음]은 Step3(납부 정보) 진입점만 잡아두고 안내한다.
// 결정적 계산은 LLM이 아닌 lib 으로 분리(SRP·OSoT): 날짜=contractDates, 매월 총액=contractAmount.
const props = defineProps({
  // 건물 드롭다운 소스(App 의 buildings 단일 소스 그대로 전달).
  buildings: { type: Array, default: () => [] },
  // 진입 건물(정보 탭 FAB)에서 왔다면 미리 선택해 둔다.
  preselectBuildingId: { type: String, default: '' },
})

const emit = defineEmits(['back', 'next'])

// 토글 전환 시에도 공통 입력값은 유지되도록 모든 스텝의 입력을 한 reactive 폼에 모은다
// (개인/사업자·월세/전세 전환 시 전용 필드만 렌더 분기, 입력값은 보존).
const form = reactive({
  buildingId: props.preselectBuildingId || '',
  unitNo: '',
  start: '', // 'YYYY-MM-DD'
  end: '', // 종료일(시작일 +1년 자동, 수동 수정 가능)
  endAuto: false, // true면 '자동 · +1년' 뱃지 노출(수동 수정 시 해제)
  tenantType: '개인', // '개인' | '사업자'
  memo: '',
  contractFileName: '', // 임대차 계약서 업로드 — 선택 파일명(실제 Storage 업로드는 최종 저장 단계)
  // 개인 경로: 계약자1 + 공동계약자
  contractors: [{ name: '', phone: '' }],
  // 사업자 경로
  bizName: '',
  managerName: '',
  bizPhone: '',
  // Step2 계약 정보 — 금액은 콤마 없는 숫자 문자열('')로 보관, 합산 시 Number 로 변환한다.
  leaseType: '월세', // '월세' | '전세' (월세=월세 필수·보증금 선택 / 전세=보증금 필수·월세 row 제거)
  deposit: '',
  monthlyRent: '',
  maintenanceFee: '',
  etcFee1: '',
  etcFee2: '',
  // 항목별 부가세 포함 플래그 — 켜지면 매월 총액 합산 시 ×1.1.
  rentVat: false,
  maintenanceVat: false,
  etc1Vat: false,
  etc2Vat: false,
})

// 위저드 스텝(1=세입자 정보, 2=계약 정보). 본문 스크롤 위치 리셋용 ref 도 함께 둔다.
const step = ref(1)
const bodyEl = ref(null)

// 계약기간 캘린더 모달 대상: null | 'start' | 'end'
const picker = ref(null)
const submitAttempted = ref(false)
const nextNotice = ref('') // Step3 미구현 안내 토스트
let noticeTimer = null

const selectedBuilding = computed(() =>
  props.buildings.find((b) => b.id === form.buildingId) ?? null,
)

// 세대/호수 옵션: 건물 메타(unit_count)에서 파생. PoC 단순화 — 101호부터 순번.
const unitOptions = computed(() => {
  const n = Number(selectedBuilding.value?.unit_count) || 0
  return Array.from({ length: n }, (_, i) => `${101 + i}호`)
})

// 건물을 바꾸면 이전 건물의 호수 선택은 무효화한다(잘못된 조합 방어).
function onBuildingChange() {
  if (!unitOptions.value.includes(form.unitNo)) form.unitNo = ''
}

function setType(type) {
  form.tenantType = type // 공통 필드 유지, 섹션만 분기
}

// 캘린더 확인: 시작일 → 종료일 +1년 자동 / 종료일 직접 선택 → 수동(뱃지 해제)
function onPickConfirm(iso) {
  if (picker.value === 'start') {
    form.start = iso
    form.end = addOneYear(iso)
    form.endAuto = true
  } else if (picker.value === 'end') {
    form.end = iso
    form.endAuto = false
  }
  picker.value = null
}

function addContractor() {
  form.contractors.push({ name: '', phone: '' })
}

function removeContractor(index) {
  if (index > 0) form.contractors.splice(index, 1)
}

function onFilePick(event) {
  const file = event.target.files?.[0]
  form.contractFileName = file ? file.name : ''
}

// ===== Step2 계약 정보 =====
function setLease(type) {
  form.leaseType = type // 공통 금액 필드(관리비/기타비용) 유지, 월세 row만 렌더 분기
}

// 금액 입력 행 구성: 월세(월세계약 한정)·관리비·기타1·기타2. 각 행은 부가세 토글을 가진다.
// 보증금은 부가세·합산 대상이 아니므로 이 목록과 별도로 렌더한다.
const moneyRows = computed(() => {
  const rows = []
  if (form.leaseType === '월세') rows.push({ key: 'monthlyRent', vatKey: 'rentVat', label: '월세', req: true })
  rows.push({ key: 'maintenanceFee', vatKey: 'maintenanceVat', label: '관리비' })
  rows.push({ key: 'etcFee1', vatKey: 'etc1Vat', label: '기타비용1' })
  rows.push({ key: 'etcFee2', vatKey: 'etc2Vat', label: '기타비용2' })
  return rows
})

// 금액 입력: 숫자만 보관(form), 화면에는 천단위 콤마로 표시한다.
function moneyDisplay(key) {
  const n = Number(form[key])
  return n > 0 ? n.toLocaleString('ko-KR') : ''
}
function onMoney(event, key) {
  const digits = event.target.value.replace(/[^\d]/g, '').slice(0, 12) // 비숫자 제거 + 과도한 자리수 방어
  form[key] = digits
  event.target.value = digits ? Number(digits).toLocaleString('ko-KR') : ''
}

// 매월 입금 예정 총액(부가세 반영) — 계산은 lib/contractAmount 단일 출처를 호출만 한다.
const total = computed(() =>
  monthlyTotal({
    leaseType: form.leaseType,
    monthlyRent: form.monthlyRent,
    rentVat: form.rentVat,
    maintenanceFee: form.maintenanceFee,
    maintenanceVat: form.maintenanceVat,
    etcFee1: form.etcFee1,
    etc1Vat: form.etc1Vat,
    etcFee2: form.etcFee2,
    etc2Vat: form.etc2Vat,
  }),
)

// Step2 필수값: 월세계약=월세 필수 / 전세계약=보증금 필수(월세는 검증 대상 아님).
const step2Errors = computed(() => {
  const e = {}
  if (form.leaseType === '월세') {
    if (!(Number(form.monthlyRent) > 0)) e.monthlyRent = '월세를 입력해주세요'
  } else {
    if (!(Number(form.deposit) > 0)) e.deposit = '보증금을 입력해주세요'
  }
  return e
})
const isStep2Valid = computed(() => Object.keys(step2Errors.value).length === 0)
function showErr2(key) {
  return submitAttempted.value && !!step2Errors.value[key]
}

// 필수값 검증 — 토글 분기에 따라 다른 필드를 본다(단일 출처).
const errors = computed(() => {
  const e = {}
  if (!form.buildingId) e.buildingId = '건물을 선택해주세요'
  if (!form.unitNo) e.unitNo = '세대/호수를 선택해주세요'
  // 종료일 수동 수정이 허용되므로 시작 이전/같은 날 방어(역전 계약기간 → Step2·회차 생성 깨짐).
  if (!form.start || !form.end) e.period = '계약기간을 선택해주세요'
  else if (form.end <= form.start) e.period = '종료일은 시작일 이후로 선택해주세요'
  if (form.tenantType === '개인') {
    if (!form.contractors[0].name.trim()) e.name = '계약자명을 입력해주세요'
    if (!form.contractors[0].phone.trim()) e.phone = '휴대폰 번호를 입력해주세요'
  } else {
    if (!form.bizName.trim()) e.bizName = '사업자명을 입력해주세요'
    if (!form.bizPhone.trim()) e.bizPhone = '휴대폰 번호를 입력해주세요'
  }
  return e
})

const isValid = computed(() => Object.keys(errors.value).length === 0)

function showErr(key) {
  return submitAttempted.value && !!errors.value[key]
}

// 스텝 전환 시 본문을 맨 위로 — 긴 폼에서 다음 스텝의 상단부터 보이게 한다.
function scrollBodyTop() {
  nextTick(() => bodyEl.value?.scrollTo({ top: 0 }))
}

// 상위로 넘길 payload — 라이브 폼은 토글 왕복 시 값 복원 UX 때문에 그대로 두되,
// 전세 계약은 월세 항목이 폼에서 빠지므로 payload에서도 제거한다(PRD: 전세 monthly_rent=null).
// 숨겨진 월세 잔존값이 Step3/저장 단계에서 전세 계약에 잘못 실리는 것을 방지.
function buildPayload() {
  const snapshot = JSON.parse(JSON.stringify(form))
  if (snapshot.leaseType === '전세') {
    snapshot.monthlyRent = ''
    snapshot.rentVat = false
  }
  return snapshot
}

// [다음]: Step1 → 검증 후 Step2 진입 / Step2 → 검증 후 Step3 진입점 안내(차기 세션).
function onNext() {
  submitAttempted.value = true
  if (step.value === 1) {
    if (!isValid.value) return
    step.value = 2
    submitAttempted.value = false // 다음 스텝에서 에러 표시는 재시도부터
    scrollBodyTop()
    return
  }
  if (!isStep2Valid.value) return
  // Step3(납부 정보)는 다음 세션 범위 — 진입점만 잡아두고 누적 입력값(정규화)을 상위로 넘긴다.
  emit('next', buildPayload())
  nextNotice.value = 'Step 2 입력 완료 — Step 3(납부 정보)는 다음 단계에서 제공됩니다'
  clearTimeout(noticeTimer)
  noticeTimer = setTimeout(() => (nextNotice.value = ''), 2800)
}

// [뒤로]/상단 ‹: Step2 → Step1 복귀 / Step1 → 위저드 종료(진입 직전 화면).
function onBack() {
  if (step.value === 2) {
    step.value = 1
    submitAttempted.value = false
    scrollBodyTop()
    return
  }
  emit('back')
}
</script>

<template>
  <div class="scr">
    <div class="tbar">
      <button class="ico back" type="button" aria-label="뒤로" @click="onBack">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <span class="ttl">세입자 등록</span>
      <span class="ico"></span>
    </div>

    <div ref="bodyEl" class="body">
      <!-- Step 헤더 + 진행 도트 (스텝에 따라 라벨·활성 도트 전환) -->
      <div class="step-head">
        <div>
          <span class="step-tag">{{ step === 1 ? 'Step.01' : 'Step.02' }}</span>
          <div class="step-title">{{ step === 1 ? '세입자 정보' : '계약 정보' }}</div>
        </div>
        <div class="stepdots">
          <i :class="{ on: step === 1 }"></i><i :class="{ on: step === 2 }"></i><i></i>
        </div>
      </div>
      <div class="divider full"></div>

      <!-- ===================== Step 1 · 세입자 정보 ===================== -->
      <template v-if="step === 1">
      <!-- 건물 -->
      <label class="flab"><span class="req"></span>건물</label>
      <select
        v-model="form.buildingId"
        class="fin select"
        :class="{ value: form.buildingId, err: showErr('buildingId') }"
        @change="onBuildingChange"
      >
        <option value="" disabled>건물 선택</option>
        <option v-for="b in buildings" :key="b.id" :value="b.id">{{ b.name }}</option>
      </select>
      <p v-if="showErr('buildingId')" class="ferr">{{ errors.buildingId }}</p>

      <!-- 세대 / 호수 -->
      <label class="flab"><span class="req"></span>세대 / 호수</label>
      <select
        v-model="form.unitNo"
        class="fin select"
        :class="{ value: form.unitNo, err: showErr('unitNo') }"
        :disabled="!form.buildingId"
      >
        <option value="" disabled>{{ form.buildingId ? '호수 선택' : '건물을 먼저 선택' }}</option>
        <option v-for="u in unitOptions" :key="u" :value="u">{{ u }}</option>
      </select>
      <p v-if="showErr('unitNo')" class="ferr">{{ errors.unitNo }}</p>

      <!-- 계약기간 -->
      <label class="flab"><span class="req"></span>계약기간</label>
      <div class="period">
        <button
          type="button"
          class="fin period-box"
          :class="{ filled: form.start, err: showErr('period') }"
          @click="picker = 'start'"
        >
          {{ form.start || '선택' }}
        </button>
        <span class="dash">—</span>
        <button
          type="button"
          class="fin period-box"
          :class="{ filled: form.end, err: showErr('period') }"
          :disabled="!form.start"
          @click="picker = 'end'"
        >
          <span v-if="form.endAuto" class="auto-1y">자동 · +1년</span>
          {{ form.end || '선택' }}
        </button>
      </div>
      <p v-if="showErr('period')" class="ferr">{{ errors.period }}</p>

      <!-- 개인 / 사업자 토글 -->
      <div class="seg">
        <button type="button" class="segbtn" :class="{ on: form.tenantType === '개인' }" @click="setType('개인')">
          개인
        </button>
        <button type="button" class="segbtn" :class="{ on: form.tenantType === '사업자' }" @click="setType('사업자')">
          사업자
        </button>
      </div>

      <!-- ===== 개인 분기 (계약자1 + 공동계약자) ===== -->
      <template v-if="form.tenantType === '개인'">
        <div v-for="(c, i) in form.contractors" :key="i">
          <div class="section-h" :style="i === 0 ? 'margin-top:18px' : 'margin-top:22px'">
            <span class="ci-icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <path d="M8.5 5H7C5.9 5 5 5.9 5 7V18C5 19.1 5.9 20 7 20H17C18.1 20 19 19.1 19 18V7C19 5.9 18.1 5 17 5H15.5" />
                <path d="M9 4.2H15V6.2H9Z" />
                <path d="M8.8 12.8L10.8 14.8L15 10.5" />
              </svg>
            </span>
            <b>계약자{{ i + 1 }}</b>
            <button v-if="i === 0" type="button" class="add-circle" aria-label="공동계약자 추가" @click="addContractor">+</button>
            <button v-else type="button" class="rm-circle" aria-label="계약자 삭제" @click="removeContractor(i)">−</button>
          </div>
          <div class="divider"></div>

          <label class="flab"><span class="req"></span>계약자명</label>
          <input
            v-model="c.name"
            class="fin input"
            :class="{ filled: c.name.trim(), err: i === 0 && showErr('name') }"
            type="text"
            placeholder="예) 홍길동"
          />
          <p v-if="i === 0 && showErr('name')" class="ferr">{{ errors.name }}</p>

          <label class="flab"><span class="req"></span>휴대폰 번호</label>
          <input
            v-model="c.phone"
            class="fin input"
            :class="{ filled: c.phone.trim(), err: i === 0 && showErr('phone') }"
            type="tel"
            inputmode="numeric"
            placeholder="예) 010-1234-5678"
          />
          <p v-if="i === 0 && showErr('phone')" class="ferr">{{ errors.phone }}</p>
        </div>
      </template>

      <!-- ===== 사업자 분기 (단일 엔티티 · + 버튼 없음) ===== -->
      <template v-else>
        <div class="section-h" style="margin-top:18px">
          <span class="ci-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M8.5 5H7C5.9 5 5 5.9 5 7V18C5 19.1 5.9 20 7 20H17C18.1 20 19 19.1 19 18V7C19 5.9 18.1 5 17 5H15.5" />
              <path d="M9 4.2H15V6.2H9Z" />
              <path d="M8.8 12.8L10.8 14.8L15 10.5" />
            </svg>
          </span>
          <b>사업자 정보</b>
        </div>
        <div class="divider"></div>

        <label class="flab"><span class="req"></span>사업자명</label>
        <input
          v-model="form.bizName"
          class="fin input"
          :class="{ filled: form.bizName.trim(), err: showErr('bizName') }"
          type="text"
          placeholder="예) (주)버틀러"
        />
        <p v-if="showErr('bizName')" class="ferr">{{ errors.bizName }}</p>

        <label class="flab">담당자명</label>
        <input v-model="form.managerName" class="fin input" :class="{ filled: form.managerName.trim() }" type="text" placeholder="예) 김담당 (선택)" />

        <label class="flab"><span class="req"></span>휴대폰 번호</label>
        <input
          v-model="form.bizPhone"
          class="fin input"
          :class="{ filled: form.bizPhone.trim(), err: showErr('bizPhone') }"
          type="tel"
          inputmode="numeric"
          placeholder="예) 010-1234-5678"
        />
        <p v-if="showErr('bizPhone')" class="ferr">{{ errors.bizPhone }}</p>
      </template>

      <!-- 메모(공통·선택) -->
      <label class="flab">메모</label>
      <textarea
        v-model="form.memo"
        class="fin input area"
        :class="{ filled: form.memo.trim() }"
        rows="2"
        placeholder="ex) 반려 동물 유무, 차량 소유 여부 등"
      ></textarea>

      <!-- 임대차 계약서 업로드(공통·선택 · Storage 저장은 최종 단계) -->
      <div class="section-h" style="margin-top:18px">
        <span class="ci-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M8.5 5H7C5.9 5 5 5.9 5 7V18C5 19.1 5.9 20 7 20H17C18.1 20 19 19.1 19 18V7C19 5.9 18.1 5 17 5H15.5" />
            <path d="M9 4.2H15V6.2H9Z" />
            <path d="M8.8 12.8L10.8 14.8L15 10.5" />
          </svg>
        </span>
        <b>임대차 계약서 업로드</b>
      </div>
      <div class="divider"></div>
      <label class="uploadbox">
        <input type="file" class="file-hidden" accept=".pdf,image/*" @change="onFilePick" />
        <span class="up-ico" aria-hidden="true">
          <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M12 4V14" /><path d="M8 10L12 14L16 10" /><path d="M5 18H19" />
          </svg>
        </span>
        {{ form.contractFileName || '계약서를 업로드 해보세요!' }}
      </label>
      </template>

      <!-- ===================== Step 2 · 계약 정보 (10e~10h) ===================== -->
      <template v-else>
        <!-- 계약형태 토글 (월세 기본 / 전세) -->
        <label class="flab"><span class="req"></span>계약형태</label>
        <div class="seg">
          <button type="button" class="segbtn" :class="{ on: form.leaseType === '월세' }" @click="setLease('월세')">
            월세
          </button>
          <button type="button" class="segbtn" :class="{ on: form.leaseType === '전세' }" @click="setLease('전세')">
            전세
          </button>
        </div>

        <!-- 보증금 — 월세: 선택 / 전세: 필수● (부가세·합산 대상 아님) -->
        <label class="flab"><span v-if="form.leaseType === '전세'" class="req"></span>보증금</label>
        <div class="fin money-row" :class="{ filled: form.deposit, err: showErr2('deposit') }">
          <input
            class="money-in"
            type="text"
            inputmode="numeric"
            placeholder="보증금을 입력해주세요"
            :value="moneyDisplay('deposit')"
            @input="onMoney($event, 'deposit')"
          />
          <span class="won">원</span>
        </div>
        <p v-if="showErr2('deposit')" class="ferr">{{ step2Errors.deposit }}</p>

        <!-- 월세(월세계약 한정)·관리비·기타비용1·2 — 각 행에 부가세 토글 -->
        <template v-for="row in moneyRows" :key="row.key">
          <label class="flab"><span v-if="row.req" class="req"></span>{{ row.label }}</label>
          <div class="fin money-row" :class="{ filled: form[row.key], err: row.req && showErr2(row.key) }">
            <input
              class="money-in"
              type="text"
              inputmode="numeric"
              placeholder="금액을 입력해주세요"
              :value="moneyDisplay(row.key)"
              @input="onMoney($event, row.key)"
            />
            <span class="won">원</span>
            <button
              type="button"
              class="vat-toggle"
              :class="{ on: form[row.vatKey] }"
              :aria-pressed="form[row.vatKey]"
              @click="form[row.vatKey] = !form[row.vatKey]"
            >
              <i class="vat-box" aria-hidden="true">✓</i>부가세
            </button>
          </div>
          <p v-if="row.req && showErr2(row.key)" class="ferr">{{ step2Errors[row.key] }}</p>
        </template>

        <!-- 매월 입금 예정 총액 — 부가세 반영 자동 합산(읽기 전용 결과) -->
        <label class="flab total-lab">매월 입금 예정 총액</label>
        <div class="total-box">{{ formatWon(total) }}</div>
      </template>
    </div>

    <!-- 하단 고정 액션바 -->
    <div class="formfoot">
      <button class="ff-back" type="button" aria-label="뒤로" @click="onBack">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <button class="ff-next" type="button" @click="onNext">다음</button>
    </div>

    <!-- Step3 안내 토스트 -->
    <Transition name="notice">
      <div v-if="nextNotice" class="next-notice">{{ nextNotice }}</div>
    </Transition>

    <!-- 계약기간 캘린더 모달 -->
    <DatePickerModal
      v-if="picker"
      :value="picker === 'start' ? form.start : form.end"
      :title="picker === 'start' ? '계약 시작일 선택' : '계약 종료일 선택'"
      @confirm="onPickConfirm"
      @cancel="picker = null"
    />
  </div>
</template>

<style scoped>
.scr {
  flex: 1;
  display: flex;
  flex-direction: column;
  color: var(--ink);
  overflow: hidden;
  position: relative;
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
  padding: 10px 15px 22px;
}

/* Step 헤더 */
.step-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
}
.step-tag {
  font-size: 10px;
  font-weight: 800;
  color: var(--accent-deep);
  background: var(--accent-soft);
  padding: 2px 7px;
  border-radius: var(--r-tag);
}
.step-title {
  font-size: 16px;
  font-weight: 800;
  margin-top: 8px;
}
.stepdots {
  display: flex;
  align-items: center;
  gap: 7px;
  margin-top: 6px;
}
.stepdots i {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: var(--gray-3);
  display: block;
}
.stepdots i.on {
  background: var(--accent);
}
.divider {
  border-bottom: 1px solid var(--gray-2);
  margin: 10px 0 0;
}
.divider.full {
  margin: 11px -15px 0;
}

/* 필드 라벨 / 입력 (BuildingRegister 패턴 재사용) */
.flab {
  font-size: 12.5px;
  font-weight: 800;
  margin: 15px 0 7px;
  display: flex;
  align-items: center;
  gap: 4px;
}
.flab .req {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--accent);
}
.fin {
  background: var(--gray-1);
  border-radius: var(--r-input);
  padding: 12px;
  font-size: 13px;
  color: var(--ink);
  display: flex;
  align-items: center;
}
.input {
  width: 100%;
  border: 1px solid transparent;
  outline: none;
  font-family: inherit;
}
.input::placeholder {
  color: var(--gray-4);
}
.input.filled {
  background: #fff;
  border-color: var(--accent);
  font-weight: 700;
}
.input.err {
  border-color: var(--danger);
  background: var(--danger-soft);
}
.area {
  min-height: 58px;
  resize: none;
  line-height: 1.5;
}
.select {
  appearance: none;
  width: 100%;
  border: 1px solid transparent;
  justify-content: center;
  text-align: center;
  text-align-last: center;
  color: var(--gray-4);
  font-family: inherit;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23A8A8B3' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
  background-size: 16px;
  padding-right: 34px;
}
.select.value {
  color: var(--ink);
  font-weight: 700;
}
.select.err {
  border-color: var(--danger);
  background-color: var(--danger-soft);
}
.select:disabled {
  opacity: 0.6;
}

/* 계약기간 두 박스 + 자동 +1년 뱃지 */
.period {
  display: flex;
  align-items: center;
  gap: 8px;
}
.period-box {
  flex: 1;
  justify-content: flex-start;
  border: 1px solid transparent;
  cursor: pointer;
  font-family: inherit;
  font-size: 12px;
  color: var(--gray-4);
  position: relative;
  white-space: nowrap;
}
.period-box.filled {
  background: #fff;
  border-color: var(--accent);
  color: var(--ink);
  font-weight: 700;
}
.period-box.err {
  border-color: var(--danger);
  background: var(--danger-soft);
}
.period-box:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
.period .dash {
  color: var(--gray-4);
}
.auto-1y {
  position: absolute;
  top: -10px;
  right: 6px;
  font-size: 9px;
  font-weight: 800;
  color: #fff;
  background: var(--ok);
  padding: 3px 8px;
  border-radius: 7px;
  white-space: nowrap;
  box-shadow: 0 4px 10px -3px rgba(26, 156, 102, 0.5);
}

/* 개인/사업자 세그먼트 토글 */
.seg {
  display: flex;
  gap: 9px;
  margin-top: 14px;
}
.segbtn {
  flex: 1;
  text-align: center;
  border-radius: 12px;
  padding: 11px 0;
  font-size: 13px;
  font-weight: 800;
  background: var(--gray-1);
  color: var(--gray-5);
  border: none;
  cursor: pointer;
  font-family: inherit;
}
.segbtn.on {
  background: var(--accent-soft);
  color: var(--accent-deep);
}

/* Step2 금액 입력 행 — 입력 + 단위(원) + 부가세 토글이 한 줄에 들어간다. */
.money-row {
  gap: 8px;
  border: 1px solid transparent;
  padding: 4px 12px;
}
.money-row.filled {
  background: #fff;
  border-color: var(--accent);
}
.money-row.err {
  border-color: var(--danger);
  background: var(--danger-soft);
}
.money-in {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  background: transparent;
  font-family: inherit;
  font-size: 13px;
  color: var(--ink);
  padding: 9px 0;
  text-align: right;
}
.money-row.filled .money-in {
  font-weight: 700;
}
.money-in::placeholder {
  color: var(--gray-4);
  font-weight: 400;
  text-align: left;
}
.money-row .won {
  font-size: 12px;
  color: var(--gray-5);
  flex: 0 0 auto;
}
.vat-toggle {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  flex: 0 0 auto;
  border: none;
  background: none;
  cursor: pointer;
  font-family: inherit;
  font-size: 10.5px;
  font-weight: 700;
  color: var(--gray-5);
  padding: 0 0 0 4px;
}
.vat-toggle.on {
  color: var(--accent-deep);
}
.vat-box {
  width: 15px;
  height: 15px;
  border-radius: 4px;
  background: var(--gray-3);
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  font-weight: 800;
  line-height: 1;
  font-style: normal;
}
.vat-toggle.on .vat-box {
  background: var(--accent);
}

/* 매월 입금 예정 총액 — 합산 결과 강조 박스(accent soft) */
.total-lab {
  margin-top: 18px;
}
.total-box {
  background: var(--accent-soft);
  color: var(--accent-deep);
  border-radius: var(--r-input);
  padding: 15px 14px;
  font-size: 16px;
  font-weight: 800;
}

/* 섹션 헤더(계약자/사업자/업로드) */
.section-h {
  display: flex;
  align-items: center;
  gap: 8px;
}
.section-h b {
  color: var(--accent);
  font-size: 14px;
  font-weight: 800;
}
.section-h .ci-icon {
  width: 22px;
  height: 22px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
}
.section-h .ci-icon svg {
  width: 21px;
  height: 21px;
  stroke: var(--accent);
  stroke-width: 1.8;
  fill: none;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.section-h .add-circle,
.section-h .rm-circle {
  margin-left: auto;
  width: 22px;
  height: 22px;
  border-radius: 50%;
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 15px;
  font-weight: 800;
  flex: 0 0 auto;
  border: none;
  cursor: pointer;
  line-height: 1;
}
.section-h .add-circle {
  background: var(--accent);
}
.section-h .rm-circle {
  background: var(--gray-4);
}

/* 계약서 업로드 박스 */
.uploadbox {
  margin-top: 13px;
  background: var(--accent-soft);
  color: var(--accent-deep);
  border-radius: 12px;
  padding: 14px;
  text-align: center;
  font-weight: 800;
  font-size: 12.5px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  cursor: pointer;
}
.file-hidden {
  display: none;
}
.uploadbox .up-ico svg {
  width: 16px;
  height: 16px;
  stroke: var(--accent-deep);
  stroke-width: 1.9;
  fill: none;
  stroke-linecap: round;
  stroke-linejoin: round;
  display: block;
}

.ferr {
  margin: 6px 2px 0;
  font-size: 11px;
  font-weight: 600;
  color: var(--danger);
}

/* 하단 고정 액션바 */
.formfoot {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-top: 1px solid var(--line);
  background: #fff;
}
.formfoot .ff-back {
  width: 46px;
  height: 46px;
  border-radius: 12px;
  background: var(--accent-soft);
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  border: none;
  cursor: pointer;
}
.formfoot .ff-back svg {
  width: 18px;
  height: 18px;
  stroke: var(--accent-deep);
  stroke-width: 2;
  fill: none;
  stroke-linecap: round;
  stroke-linejoin: round;
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

/* Step2 안내 토스트 */
.next-notice {
  position: absolute;
  left: 16px;
  right: 16px;
  bottom: 76px;
  z-index: 9;
  background: var(--accent-soft);
  color: var(--accent-deep);
  border-radius: 12px;
  padding: 12px 14px;
  font-size: 12.5px;
  font-weight: 700;
  text-align: center;
}
.notice-enter-active,
.notice-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.notice-enter-from,
.notice-leave-to {
  opacity: 0;
  transform: translateY(8px);
}
</style>
