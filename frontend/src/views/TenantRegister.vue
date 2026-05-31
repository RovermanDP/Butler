<script setup>
import { reactive, ref, computed, nextTick, watch } from 'vue'
import { addOneYear, formatKoYmd, formatShortDate } from '../lib/contractDates'
import { monthlyTotal } from '../lib/contractAmount'
import { firstPaymentDate, generateSchedule, pastUnpaidCount, PAST_UNPAID_OPTIONS } from '../lib/payment'
import { formatWon } from '../lib/format'
import { registerTenant } from '../lib/tenants'
import DatePickerModal from '../components/DatePickerModal.vue'
import WheelPicker from '../components/WheelPicker.vue'
import ProofSheet from '../components/ProofSheet.vue'
import PaymentScheduleModal from '../components/PaymentScheduleModal.vue'

// 화면 10a~10m — Flow E 세입자 등록 위저드 · Step1(세입자 정보)+Step2(계약 정보)+Step3(납부 정보).
// 한 '세입자 등록' 화면 안에서 스텝만 전환한다(tbar·stepdots·하단 액션바 chrome 공유).
//   Step1(10a~10d): 개인/사업자 토글로 하단 섹션 분기(PRD 4.5 E-2).
//   Step2(10e~10h): 월세/전세 토글로 월세 row 동적 추가·제거 + 매월 입금 예정 총액 자동 합산(E-3).
//   Step3(10i~10m): 납부일 휠·선불/후불 첫 납부일 자동·입금자명·과거 미납 휠·납부 회차표(확인완료 잠김)·증빙 5종 모달(E-4).
// 완료(10n/10o): Step3 [다음] → Supabase 적재(lib/tenants) → 등록 완료 화면(요약·안내) → 완료/추가 등록하기(E-5).
// 결정적 계산은 LLM이 아닌 lib 으로 분리(SRP·OSoT): 날짜=contractDates, 매월 총액=contractAmount, 첫 납부일·회차=payment.
const props = defineProps({
  // 건물 드롭다운 소스(App 의 buildings 단일 소스 그대로 전달).
  buildings: { type: Array, default: () => [] },
  // 진입 건물(정보 탭 FAB)에서 왔다면 미리 선택해 둔다.
  preselectBuildingId: { type: String, default: '' },
})

// back: 위저드 종료(진입 직전 화면) / done: 등록 완료 → 건물 상세(Flow B 집계 갱신).
const emit = defineEmits(['back', 'done'])

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
  contractFileName: '', // 임대차 계약서 업로드 — 선택 파일명(표시용)
  contractFile: null, // 실제 File 객체(완료 단계에서 Storage 업로드)
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
  // Step3 납부 정보 — 첫 납부일·회차는 결정적 계산(lib/payment)으로 파생한다.
  paymentDay: 1, // 납부일 1~31 (월별 말일 보정)
  paymentTiming: '선불', // '선불'(당월) | '후불'(익월)
  depositorSame: true, // '계약자 명과 동일' 체크 — true면 입금자명 = 대표 계약자명
  depositorName: '', // 직접 입력 입금자명(depositorSame=false 일 때만 사용)
  pastUnpaid: '미납없음', // '미납없음' | '1개월' | '2개월' (선택분만큼 과거 회차 미납 시드)
  scheduleConfirmed: false, // 납부 내역 회차표 '확인 완료' → 잠김
  // 증빙 발급 설정(proof_kind 5종) + 선택값별 하위 필드. ⚠ expenses.proof_type 와 별개 개념.
  proofKind: '', // '' = 미선택('선택' 표시) / 5종 중 하나
  proofPhone: '', // 현금영수증(개인소득공제용)
  proofBizRegNo: '', // 현금영수증(사업자증빙용)
  proofEmail: '', // 세금계산서 / 계산서
  proofLicenseFileName: '', // 세금계산서 / 계산서 — 사업자등록증 파일명(표시용)
  proofLicenseFile: null, // 실제 File 객체(완료 단계에서 Storage 업로드)
})

// 폼 초기 스냅샷 — '추가 등록하기'에서 동일 폼을 깨끗이 되돌릴 때 쓴다(건물 선택은 호출부에서 유지).
const FORM_DEFAULTS = JSON.parse(JSON.stringify({ ...form, contractFile: null, proofLicenseFile: null }))

// 위저드 스텝(1=세입자 정보, 2=계약 정보, 3=납부 정보). 본문 스크롤 위치 리셋용 ref 도 함께 둔다.
const step = ref(1)
const bodyEl = ref(null)

// 완료(10n/10o) 상태 — 저장 성공 시 done=true 로 등록 완료 화면으로 전환한다.
const done = ref(false)
const saving = ref(false) // 저장 진행 중(중복 제출·연속 클릭 방어, 버튼 비활성)
const result = ref(null) // 완료 화면 요약(저장 시점 스냅샷 — 이후 폼이 리셋돼도 화면 유지)

// 계약기간 캘린더 모달 대상: null | 'start' | 'end'
const picker = ref(null)
const submitAttempted = ref(false)
const nextNotice = ref('') // 저장 실패 안내 토스트(danger)
let noticeTimer = null

// Step3 오버레이 상태: 휠 피커 대상(null|'day'|'unpaid')·회차표·증빙 모달.
const wheelTarget = ref(null)
const showSchedule = ref(false)
const showProof = ref(false)
// 과거 미납 선택 시 알림톡(mock) 발송 안내 토스트(스텝3 전용).
const payNotice = ref('')
let payNoticeTimer = null

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
  const file = event.target.files?.[0] ?? null
  form.contractFile = file
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

// ===== Step3 납부 정보 =====
// 대표 계약자명 — 개인=계약자1, 사업자=사업자명. 입금자명 기본값/‘계약자 명과 동일’의 출처.
const primaryName = computed(() =>
  (form.tenantType === '개인' ? form.contractors[0]?.name : form.bizName)?.trim() || '',
)
// 화면에 보이는 입금자명: ‘동일’ 체크면 대표 계약자명, 아니면 직접 입력값.
const depositorDisplay = computed(() => (form.depositorSame ? primaryName.value : form.depositorName))

// 첫 납부일(선불=당월/후불=익월, 말일 보정) — 결정적 계산은 lib/payment 단일 출처를 호출만 한다.
const firstPay = computed(() => firstPaymentDate(form.paymentDay, form.paymentTiming))
const firstPayLabel = computed(() => formatKoYmd(firstPay.value))

// 납부 회차표 — 첫 납부일~계약 종료일, 매월 1회차. 과거 미납 선택분은 가장 이른 회차를 ‘미납’ 시드.
const schedule = computed(() =>
  generateSchedule({
    firstPayment: firstPay.value,
    contractEnd: form.end,
    amount: total.value,
    paymentDay: form.paymentDay,
    unpaidCount: pastUnpaidCount(form.pastUnpaid),
  }),
)

// 납부일 휠 옵션 1~31 / 과거 미납 휠 옵션(미납없음/1·2개월). value 는 lib 가 쓰는 원본값.
const dayOptions = Array.from({ length: 31 }, (_, i) => ({ value: i + 1, label: `${i + 1} 일` }))
const unpaidOptions = PAST_UNPAID_OPTIONS.map((v) => ({ value: v, label: v }))

// 납부 파라미터(납부일·선불후불·과거미납)가 바뀌면 회차표가 달라지므로 ‘확인 완료’ 잠김을 해제한다.
// (확인했던 표와 실제 회차가 어긋나는 것을 방지 — 변경 후 재확인을 요구.)
function invalidateSchedule() {
  form.scheduleConfirmed = false
}

function setTiming(timing) {
  if (form.paymentTiming === timing) return
  form.paymentTiming = timing
  invalidateSchedule()
}

// 휠 확인 — 대상에 따라 납부일/과거 미납을 반영. 과거 미납 선택 시 알림톡(mock) 안내.
function onWheelConfirm(value) {
  if (wheelTarget.value === 'day') {
    if (form.paymentDay !== value) {
      form.paymentDay = value
      invalidateSchedule()
    }
  } else if (wheelTarget.value === 'unpaid') {
    if (form.pastUnpaid !== value) {
      form.pastUnpaid = value
      invalidateSchedule()
      if (pastUnpaidCount(value) > 0) notifyMockUnpaid(value)
    }
  }
  wheelTarget.value = null
}

// 과거 미납 선택 → 세입자 알림톡(mock) 발송 안내(PRD 3장: 미납 회차 시드 + 알림톡 mock).
// 실제 notifications insert 는 등록 완료(저장) 단계에서 schedule 의 미납 회차를 근거로 수행한다.
function notifyMockUnpaid(value) {
  payNotice.value = `미납 ${value} 안내 알림톡을 세입자에게 발송했어요 (mock)`
  clearTimeout(payNoticeTimer)
  payNoticeTimer = setTimeout(() => (payNotice.value = ''), 2800)
}

// ‘계약자 명과 동일’ 토글 — 해제 시 현재 대표 계약자명을 채워 바로 수정 가능하게 한다.
function toggleDepositorSame() {
  form.depositorSame = !form.depositorSame
  if (!form.depositorSame && !form.depositorName.trim()) form.depositorName = primaryName.value
}

// 회차표는 매월 총액(Step2)·계약 종료일(Step1)에서도 파생되므로, 확인 후 그 값이 바뀌면
// 잠김을 풀어 재확인을 요구한다(확인했던 표와 실제 회차가 어긋나는 것을 방지).
watch([total, () => form.end], () => {
  if (form.scheduleConfirmed) form.scheduleConfirmed = false
})

function openSchedule() {
  if (form.scheduleConfirmed) return // 확인 완료 후 잠김(재선택 불가)
  showSchedule.value = true
}

function onScheduleConfirm() {
  // 방어: 회차가 0건이면 잠그지 않는다(모달 버튼도 비활성이지만 부모에서도 이중 차단).
  if (schedule.value.length === 0) return
  form.scheduleConfirmed = true
  showSchedule.value = false
}

// 증빙 종류 선택 — 종류가 바뀌면 이전 종류의 하위 필드를 비워 잘못된 값이 남지 않게 한다(분기 누락 방어).
function onProofSelect(kind) {
  if (form.proofKind !== kind) {
    form.proofKind = kind
    form.proofPhone = ''
    form.proofBizRegNo = ''
    form.proofEmail = ''
    form.proofLicenseFileName = ''
    form.proofLicenseFile = null
  }
  showProof.value = false
}

function onLicensePick(event) {
  const file = event.target.files?.[0] ?? null
  form.proofLicenseFile = file
  form.proofLicenseFileName = file ? file.name : ''
}

// 증빙 종류별 하위 필수 필드 — 분기 누락 없이 한 곳에서 정의(OSoT).
const proofNeedsPhone = computed(() => form.proofKind === '현금영수증(개인소득공제용)')
const proofNeedsBizReg = computed(() => form.proofKind === '현금영수증(사업자증빙용)')
const proofNeedsEmail = computed(() => form.proofKind === '세금계산서' || form.proofKind === '계산서')

// Step3 필수값 검증 — 입금자명·납부 내역 확인·증빙 종류(+하위 필드).
// 증빙은 CLAUDE.md DB 제약("증빙 종류별 하위 필드 필수")을 프론트에서도 동일하게 막는다.
//   세금계산서/계산서(10m-d·e)는 이메일 + 사업자등록증 업로드가 모두 하위 필수 필드.
const step3Errors = computed(() => {
  const e = {}
  if (!depositorDisplay.value.trim()) e.depositor = '입금자명을 입력해주세요'
  if (!form.scheduleConfirmed) e.schedule = '납부 내역을 확인해주세요'
  if (!form.proofKind) e.proof = '증빙 종류를 선택해주세요'
  else if (proofNeedsPhone.value && !form.proofPhone.trim()) e.proof = '휴대폰 번호를 입력해주세요'
  else if (proofNeedsBizReg.value && !form.proofBizRegNo.trim()) e.proof = '사업자 등록 번호를 입력해주세요'
  else if (proofNeedsEmail.value && !form.proofEmail.trim()) e.proof = '이메일 주소를 입력해주세요'
  else if (proofNeedsEmail.value && !form.proofLicenseFileName) e.proof = '사업자 등록증을 업로드해주세요'
  return e
})
const isStep3Valid = computed(() => Object.keys(step3Errors.value).length === 0)
function showErr3(key) {
  return submitAttempted.value && !!step3Errors.value[key]
}
// 증빙 하위 필드별 시각 에러 — 같은 'proof' 에러라도 비어 있는 필드에만 빨간 테두리를 준다(원인 명확화).
const proofPhoneErr = computed(() => submitAttempted.value && proofNeedsPhone.value && !form.proofPhone.trim())
const proofBizRegErr = computed(() => submitAttempted.value && proofNeedsBizReg.value && !form.proofBizRegNo.trim())
const proofEmailErr = computed(() => submitAttempted.value && proofNeedsEmail.value && !form.proofEmail.trim())
const proofLicenseErr = computed(
  () => submitAttempted.value && proofNeedsEmail.value && !!form.proofEmail.trim() && !form.proofLicenseFileName,
)

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
// File 객체는 JSON 직렬화로 깨지므로 일단 빼고 클론한 뒤 원본 참조를 다시 붙인다.
function buildPayload() {
  const snapshot = JSON.parse(JSON.stringify({ ...form, contractFile: null, proofLicenseFile: null }))
  if (snapshot.leaseType === '전세') {
    snapshot.monthlyRent = ''
    snapshot.rentVat = false
  }
  // 입금자명은 ‘동일’ 체크 여부를 흡수해 최종값 하나로 정규화(저장 단계에서 분기 불필요).
  snapshot.depositorName = depositorDisplay.value
  // 결정적 파생값을 함께 실어 보낸다(저장 단계가 재계산 없이 그대로 persist):
  //   첫 납부일·매월 총액·payments 회차(미납 시드 포함).
  snapshot.firstPaymentDate = firstPay.value
  snapshot.monthlyTotal = total.value
  snapshot.schedule = schedule.value
  // 업로드 대상 File 은 원본 참조로 부착(Storage 업로드는 lib/tenants).
  snapshot.contractFile = form.contractFile
  snapshot.proofLicenseFile = form.proofLicenseFile
  return snapshot
}

// 완료 화면(10n/10o) 요약 — 저장 직전 폼 값으로 스냅샷(이후 ‘추가 등록’ 으로 폼이 리셋돼도 화면 유지).
function buildSummary() {
  return {
    tenantName: primaryName.value,
    buildingName: selectedBuilding.value?.name ?? '',
    unitNo: form.unitNo,
    term: `${formatShortDate(form.start)} ~ ${formatShortDate(form.end)}`,
    leaseType: form.leaseType,
    deposit: Number(form.deposit) || 0,
    monthlyRent: form.leaseType === '월세' ? Number(form.monthlyRent) || 0 : null,
    maintenanceFee: Number(form.maintenanceFee) || 0,
    etcFee1: Number(form.etcFee1) || 0,
    etcFee2: Number(form.etcFee2) || 0,
    warnings: [],
  }
}

// Step3 [다음] → Supabase 적재 후 완료 화면 전환. 실패는 삼키지 않고 토스트로 노출, 재시도 가능.
async function submitRegistration() {
  if (saving.value) return // 연속 클릭/중복 제출 방어
  saving.value = true
  try {
    const res = await registerTenant(buildPayload())
    const summary = buildSummary()
    summary.warnings = res.warnings ?? [] // (선택)파일 업로드·알림톡 mock 부수 실패 안내
    result.value = summary
    done.value = true
    scrollBodyTop()
  } catch (e) {
    nextNotice.value = e.message || '등록에 실패했습니다. 다시 시도해주세요'
    clearTimeout(noticeTimer)
    noticeTimer = setTimeout(() => (nextNotice.value = ''), 3600)
  } finally {
    saving.value = false
  }
}

// [다음]: Step1·2 → 검증 후 다음 스텝 / Step3 → 검증 후 Supabase 적재(완료 화면 전환).
function onNext() {
  if (saving.value) return
  submitAttempted.value = true
  if (step.value === 1) {
    if (!isValid.value) return
    step.value = 2
    submitAttempted.value = false // 다음 스텝에서 에러 표시는 재시도부터
    scrollBodyTop()
    return
  }
  if (step.value === 2) {
    if (!isStep2Valid.value) return
    step.value = 3
    submitAttempted.value = false
    scrollBodyTop()
    return
  }
  if (!isStep3Valid.value) return
  submitRegistration()
}

// 완료 화면 [완료] → 건물 상세로(집계 갱신은 App). [추가 등록하기] → 같은 건물에 새 세입자 등록(폼 리셋).
function onDone() {
  emit('done', form.buildingId)
}

function onRegisterMore() {
  const keepBuildingId = form.buildingId // 같은 건물에 연속 등록하는 흐름이 자연스럽다
  Object.assign(form, JSON.parse(JSON.stringify(FORM_DEFAULTS)))
  form.buildingId = keepBuildingId
  form.contractors = [{ name: '', phone: '' }] // 중첩 배열은 새 참조로 확실히 초기화
  form.contractFile = null
  form.proofLicenseFile = null
  result.value = null
  done.value = false
  step.value = 1
  submitAttempted.value = false
  scrollBodyTop()
}

// [뒤로]/상단 ‹: Step3 → Step2 / Step2 → Step1 / Step1 → 위저드 종료(진입 직전 화면).
function onBack() {
  if (step.value === 3) {
    step.value = 2
    submitAttempted.value = false
    scrollBodyTop()
    return
  }
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
    <div class="tbar" :class="{ center: done }">
      <button v-if="!done" class="ico back" type="button" aria-label="뒤로" @click="onBack">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <span class="ttl">{{ done ? '등록 완료' : '세입자 등록' }}</span>
      <span v-if="!done" class="ico"></span>
    </div>

    <div ref="bodyEl" class="body">
      <!-- ===================== 위저드(Step 1~3) ===================== -->
      <template v-if="!done">
      <!-- Step 헤더 + 진행 도트 (스텝에 따라 라벨·활성 도트 전환) -->
      <div class="step-head">
        <div>
          <span class="step-tag">Step.0{{ step }}</span>
          <div class="step-title">{{ ['', '세입자 정보', '계약 정보', '납부 정보'][step] }}</div>
        </div>
        <div class="stepdots">
          <i :class="{ on: step === 1 }"></i><i :class="{ on: step === 2 }"></i><i :class="{ on: step === 3 }"></i>
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
      <template v-else-if="step === 2">
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

      <!-- ===================== Step 3 · 납부 정보 (10i~10m) ===================== -->
      <template v-else>
        <!-- 납부일 — 탭 → 휠 피커(1~31일, 말일 보정) -->
        <label class="flab fl-hint"><span class="req"></span>납부일<span class="taphint">👈 탭 → 휠 피커</span></label>
        <button type="button" class="fin tapfield filled" @click="wheelTarget = 'day'">
          {{ form.paymentDay }} 일<span class="caret">⌄</span>
        </button>

        <!-- 계약 조건(선불/후불) → 첫 납부일 자동 표기 -->
        <label class="flab"><span class="req"></span>계약 조건</label>
        <div class="seg">
          <button type="button" class="segbtn" :class="{ on: form.paymentTiming === '선불' }" @click="setTiming('선불')">
            선불
          </button>
          <button type="button" class="segbtn" :class="{ on: form.paymentTiming === '후불' }" @click="setTiming('후불')">
            후불
          </button>
        </div>
        <div class="firstpay"><span class="ar">→</span>{{ firstPayLabel }}</div>
        <div class="hint-row"><span class="ex">!</span>선불/후불에 따라 세입자가 안내 받을 첫 납부일자에요</div>

        <!-- 입금자명 — 기본 = 대표 계약자명('계약자 명과 동일' 체크). 해제 시 직접 입력. -->
        <label class="flab"><span class="req"></span>입금자명</label>
        <div v-if="form.depositorSame" class="namebox">
          <span class="nm">{{ primaryName || '계약자명을 먼저 입력해주세요' }}</span>
          <button type="button" class="same-check on" @click="toggleDepositorSame">
            <span class="cb">✓</span>계약자 명과 동일
          </button>
        </div>
        <template v-else>
          <div class="fin name-edit" :class="{ filled: form.depositorName.trim(), err: showErr3('depositor') }">
            <input
              v-model="form.depositorName"
              class="name-in"
              type="text"
              placeholder="입금자명을 입력해주세요"
            />
            <button type="button" class="same-check" @click="toggleDepositorSame">
              <span class="cb off"></span>계약자 명과 동일
            </button>
          </div>
          <p v-if="showErr3('depositor')" class="ferr">{{ step3Errors.depositor }}</p>
        </template>
        <div class="hint-row"><span class="ex">!</span>입금자 명이 다를 경우 자동 수납되지 않아요</div>

        <!-- 과거 미납 내역 — 탭 → 휠 피커. 선택 시 미납 회차 시드 + 알림톡(mock). -->
        <label class="flab fl-hint"><span class="req"></span>과거 미납 내역<span class="taphint">👈 탭 → 휠 피커</span></label>
        <button type="button" class="fin tapfield filled" @click="wheelTarget = 'unpaid'">
          {{ form.pastUnpaid }}<span class="caret">⌄</span>
        </button>

        <!-- 납부 내역 — '확인하기' → 회차표. 확인 완료 시 잠김(재선택 불가). -->
        <label class="flab fl-hint"><span class="req"></span>납부 내역<span class="taphint">👈 탭 → 납부 내역 확인</span></label>
        <button
          v-if="!form.scheduleConfirmed"
          type="button"
          class="fin tapfield"
          :class="{ err: showErr3('schedule') }"
          @click="openSchedule"
        >
          확인하기<span class="caret">⌄</span>
        </button>
        <div v-else class="fin confirmed">확인완료 <span class="ck">✓</span></div>
        <p v-if="showErr3('schedule')" class="ferr">{{ step3Errors.schedule }}</p>

        <!-- 증빙 관리 — '선택' → 증빙 모달(5종). 선택값에 따라 하위 필드 분기. -->
        <label class="flab fl-hint"><span class="req"></span>증빙 관리<span class="taphint">👈 탭 → 증빙 모달</span></label>
        <button
          type="button"
          class="fin tapfield"
          :class="{ filled: form.proofKind, err: showErr3('proof') && !form.proofKind }"
          @click="showProof = true"
        >
          {{ form.proofKind || '선택' }}<span class="caret">⌄</span>
        </button>

        <!-- 증빙 종류별 하위 필드 분기(10m-b~e) -->
        <template v-if="proofNeedsPhone">
          <input
            v-model="form.proofPhone"
            class="fin input proof-sub"
            :class="{ filled: form.proofPhone.trim(), err: proofPhoneErr }"
            type="tel"
            inputmode="numeric"
            placeholder="휴대폰 번호"
          />
        </template>
        <template v-else-if="proofNeedsBizReg">
          <input
            v-model="form.proofBizRegNo"
            class="fin input proof-sub"
            :class="{ filled: form.proofBizRegNo.trim(), err: proofBizRegErr }"
            type="text"
            inputmode="numeric"
            placeholder="사업자 등록 번호"
          />
        </template>
        <template v-else-if="proofNeedsEmail">
          <input
            v-model="form.proofEmail"
            class="fin input proof-sub"
            :class="{ filled: form.proofEmail.trim(), err: proofEmailErr }"
            type="email"
            placeholder="이메일 주소"
          />
          <label class="flab"><span class="req"></span>사업자 등록증</label>
          <label class="uploadbox" :class="{ err: proofLicenseErr, done: form.proofLicenseFileName }">
            <input type="file" class="file-hidden" accept=".pdf,image/*" @change="onLicensePick" />
            <span class="up-ico" aria-hidden="true">
              <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <path d="M12 4V14" /><path d="M8 10L12 14L16 10" /><path d="M5 18H19" />
              </svg>
            </span>
            {{ form.proofLicenseFileName || '사업자 등록증을 업로드해주세요' }}
          </label>
        </template>
        <p v-if="showErr3('proof')" class="ferr">{{ step3Errors.proof }}</p>
      </template>
      </template>

      <!-- ===================== 등록 완료 (10n / 10o) ===================== -->
      <template v-else>
        <div class="done-check" aria-hidden="true">✓</div>
        <div class="done-msg">등록이 완료되었어요!</div>

        <!-- 세입자 / 호실 / 계약기간 카드 -->
        <div class="done-card">
          <div class="dc-top">
            <span class="hico" aria-hidden="true">
              <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                <path d="M5 11L12 5L19 11V19C19 19.55 18.55 20 18 20H6C5.45 20 5 19.55 5 19V11Z" />
              </svg>
            </span>
            <div>
              <div class="nm">{{ result.tenantName }}</div>
              <div class="addr">{{ result.buildingName }} {{ result.unitNo }}</div>
            </div>
          </div>
          <div class="dc-divln"></div>
          <div class="term"><b>계약기간</b>&nbsp;&nbsp;{{ result.term }}</div>
        </div>

        <!-- 계약 정보 요약 -->
        <div class="done-sec-h">
          <span class="ci-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <circle cx="12" cy="8" r="3.2" />
              <path d="M5.5 19C5.5 15.9 8.4 14 12 14C15.6 14 18.5 15.9 18.5 19" />
            </svg>
          </span>
          계약 정보
        </div>
        <div class="done-table">
          <div class="r"><span class="k">계약형태</span><span class="v">{{ result.leaseType }}</span></div>
          <div class="r"><span class="k">보증금</span><span class="v">{{ formatWon(result.deposit) }}</span></div>
          <div v-if="result.leaseType === '월세'" class="r"><span class="k">월세</span><span class="v">{{ formatWon(result.monthlyRent) }}</span></div>
          <div class="r"><span class="k">관리비</span><span class="v">{{ formatWon(result.maintenanceFee) }}</span></div>
          <div class="r"><span class="k">기타1</span><span class="v">{{ formatWon(result.etcFee1) }}</span></div>
          <div class="r"><span class="k">기타2</span><span class="v">{{ formatWon(result.etcFee2) }}</span></div>
        </div>

        <!-- 안내 -->
        <div class="done-info"><span class="ex">!</span>월세 입금자와 등록된 세입자의 이름이 동일해야해요</div>
        <div class="done-info"><span class="ex">!</span>세입자 등록 완료 시, 계약 시작 하루전에 해당 세입자에게 납부 알림이 전송돼요</div>

        <!-- (선택)파일 업로드·알림톡 mock 등 부수 작업 경고 — 등록 자체는 성공 -->
        <div v-for="(w, i) in result.warnings" :key="i" class="done-info warn"><span class="ex">!</span>{{ w }}</div>
      </template>
    </div>

    <!-- 하단 고정 액션바 — 위저드: 뒤로/다음 · 완료: 완료/추가 등록하기 -->
    <div v-if="!done" class="formfoot">
      <button class="ff-back" type="button" aria-label="뒤로" :disabled="saving" @click="onBack">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <button class="ff-next" type="button" :disabled="saving" @click="onNext">
        {{ step === 3 ? (saving ? '등록 중…' : '등록 완료') : '다음' }}
      </button>
    </div>
    <div v-else class="done-foot">
      <button class="df-sub" type="button" @click="onDone">완료</button>
      <button class="df-main" type="button" @click="onRegisterMore">추가 등록하기</button>
    </div>

    <!-- 저장 실패 안내(danger) + 과거 미납 알림톡(mock) 안내 토스트 -->
    <Transition name="notice">
      <div v-if="nextNotice" class="next-notice err">{{ nextNotice }}</div>
    </Transition>
    <Transition name="notice">
      <div v-if="payNotice" class="next-notice mock">{{ payNotice }}</div>
    </Transition>

    <!-- 계약기간 캘린더 모달 -->
    <DatePickerModal
      v-if="picker"
      :value="picker === 'start' ? form.start : form.end"
      :title="picker === 'start' ? '계약 시작일 선택' : '계약 종료일 선택'"
      @confirm="onPickConfirm"
      @cancel="picker = null"
    />

    <!-- Step3 — 납부일(1~31) / 과거 미납 휠 피커 (10i-1·10i-2) -->
    <WheelPicker
      v-if="wheelTarget === 'day'"
      :options="dayOptions"
      :model-value="form.paymentDay"
      title="입금 예정일"
      @confirm="onWheelConfirm"
      @cancel="wheelTarget = null"
    />
    <WheelPicker
      v-else-if="wheelTarget === 'unpaid'"
      :options="unpaidOptions"
      :model-value="form.pastUnpaid"
      title="과거 미납 내역"
      desc="계약기간 중 아직 미납된 내역이 있다면 선택해주세요. 세입자에게 알림톡을 보내줘요."
      @confirm="onWheelConfirm"
      @cancel="wheelTarget = null"
    />

    <!-- Step3 — 납부 내역 회차표 (10k·10l). 확인 완료 시 잠김. -->
    <PaymentScheduleModal
      v-if="showSchedule"
      :rows="schedule"
      :payment-day="form.paymentDay"
      :lease-type="form.leaseType"
      :payment-timing="form.paymentTiming"
      :amount="total"
      @confirm="onScheduleConfirm"
      @cancel="showSchedule = false"
    />

    <!-- Step3 — 증빙 발급 설정 모달 (10m, 5종) -->
    <ProofSheet
      v-if="showProof"
      :model-value="form.proofKind"
      @select="onProofSelect"
      @cancel="showProof = false"
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
.tbar.center {
  justify-content: center;
  padding-top: 14px;
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

/* ===== Step3 납부 정보 ===== */
/* 라벨 우측 '탭 → …' 힌트 뱃지 */
.flab.fl-hint {
  justify-content: flex-start;
}
.taphint {
  margin-left: auto;
  font-size: 9px;
  font-weight: 800;
  color: #fff;
  background: var(--accent);
  padding: 2px 8px;
  border-radius: 7px;
  white-space: nowrap;
}
/* 탭하면 휠/모달이 열리는 값 표시 필드(납부일·과거미납·납부내역·증빙) */
.tapfield {
  width: 100%;
  justify-content: center;
  border: 1px solid transparent;
  cursor: pointer;
  font-family: inherit;
  font-size: 13px;
  color: var(--gray-5);
  font-weight: 700;
  gap: 6px;
}
.tapfield.filled {
  color: var(--ink);
}
.tapfield.err {
  border-color: var(--danger);
  background: var(--danger-soft);
}
.tapfield .caret {
  color: var(--gray-4);
  font-size: 12px;
}
/* 첫 납부일 자동 표기 박스 */
.firstpay {
  margin-top: 9px;
  background: var(--gray-1);
  border-radius: var(--r-input);
  padding: 14px;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 13.5px;
  font-weight: 800;
  color: var(--accent-deep);
}
.firstpay .ar {
  color: var(--accent);
  font-weight: 800;
}
/* 안내 힌트 줄(!  …) */
.hint-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 10.5px;
  color: var(--gray-4);
  margin-top: 7px;
  font-weight: 600;
}
.hint-row .ex {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--gray-3);
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  font-weight: 800;
  flex: 0 0 auto;
}
/* 입금자명 — '계약자 명과 동일' 표시 박스 + 체크 토글 */
.namebox {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border: 1px solid var(--line);
  border-radius: var(--r-input);
  padding: 13px 14px;
}
.namebox .nm {
  font-size: 13px;
  font-weight: 800;
  color: var(--ink);
}
.same-check {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 700;
  color: var(--gray-6);
  border: none;
  background: none;
  cursor: pointer;
  font-family: inherit;
  flex: 0 0 auto;
}
.same-check .cb {
  width: 16px;
  height: 16px;
  border-radius: 4px;
  background: var(--accent);
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  font-weight: 800;
}
.same-check .cb.off {
  background: var(--gray-3);
}
/* 입금자명 직접 입력(동일 해제 시) — 입력 + 체크 토글 한 줄 */
.name-edit {
  gap: 8px;
  border: 1px solid transparent;
  padding: 6px 12px;
}
.name-edit.filled {
  background: #fff;
  border-color: var(--accent);
}
.name-edit.err {
  border-color: var(--danger);
  background: var(--danger-soft);
}
.name-in {
  flex: 1;
  min-width: 0;
  border: none;
  outline: none;
  background: transparent;
  font-family: inherit;
  font-size: 13px;
  color: var(--ink);
  padding: 7px 0;
  font-weight: 700;
}
.name-in::placeholder {
  color: var(--gray-4);
  font-weight: 400;
}
/* 납부 내역 확인완료 잠김 표시 */
.fin.confirmed {
  background: var(--gray-1);
  color: var(--gray-5);
  justify-content: center;
  font-weight: 700;
  gap: 7px;
}
.fin.confirmed .ck {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: var(--ok);
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  font-weight: 800;
}
/* 증빙 하위 입력 필드 */
.proof-sub {
  margin-top: 10px;
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
  border: 1px solid transparent;
}
/* 업로드 완료/미입력(필수 누락) 상태 — 증빙 사업자등록증 필수 검증 시각 피드백 */
.uploadbox.done {
  background: #fff;
  border-color: var(--accent);
}
.uploadbox.err {
  background: var(--danger-soft);
  color: var(--danger);
  border-color: var(--danger);
}
.uploadbox.err .up-ico svg {
  stroke: var(--danger);
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
.formfoot .ff-next:disabled,
.formfoot .ff-back:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* ===== 등록 완료 (10n / 10o) ===== */
.done-check {
  width: 62px;
  height: 62px;
  border-radius: 50%;
  background: var(--accent);
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 30px;
  margin: 6px auto 12px;
}
.done-msg {
  text-align: center;
  font-size: 16px;
  font-weight: 800;
  color: var(--accent);
  margin-bottom: 16px;
}
.done-card {
  border: 1px solid var(--line);
  border-radius: var(--r-card);
  padding: 14px;
}
.done-card .dc-top {
  display: flex;
  align-items: center;
  gap: 11px;
}
.done-card .hico {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background: var(--accent);
  display: grid;
  place-items: center;
  flex: 0 0 auto;
}
.done-card .hico svg {
  width: 20px;
  height: 20px;
  stroke: #fff;
  stroke-width: 1.9;
  fill: none;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.done-card .nm {
  font-size: 15px;
  font-weight: 800;
  color: var(--ink);
}
.done-card .addr {
  font-size: 11.5px;
  color: var(--gray-6);
  font-weight: 600;
  margin-top: 2px;
}
.done-card .dc-divln {
  border-top: 1px solid var(--line);
  margin: 11px 0;
}
.done-card .term {
  font-size: 11.5px;
  color: var(--gray-6);
  font-weight: 600;
}
.done-card .term b {
  color: var(--ink);
  font-weight: 800;
}
.done-sec-h {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 16px 0 9px;
  font-size: 14px;
  font-weight: 800;
  color: var(--accent);
}
.done-sec-h .ci-icon {
  width: 22px;
  height: 22px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
}
.done-sec-h .ci-icon svg {
  width: 20px;
  height: 20px;
  stroke: var(--accent);
  stroke-width: 1.8;
  fill: none;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.done-table {
  background: var(--gray-1);
  border-radius: var(--r-card);
  padding: 3px 14px;
}
.done-table .r {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 0;
}
.done-table .r + .r {
  border-top: 1px solid var(--line);
}
.done-table .k {
  font-size: 13px;
  color: var(--gray-6);
  font-weight: 600;
}
.done-table .v {
  font-size: 14px;
  font-weight: 800;
  color: var(--ink);
}
.done-info {
  background: var(--gray-1);
  border-radius: var(--r-input);
  padding: 12px 13px;
  font-size: 11px;
  line-height: 1.55;
  color: var(--gray-6);
  font-weight: 600;
  margin-top: 10px;
  display: flex;
  gap: 7px;
  align-items: flex-start;
}
.done-info .ex {
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
/* (선택)첨부·알림톡 mock 부수 실패 — 등록은 성공, warn(amber) 톤으로 구분 */
.done-info.warn {
  background: var(--warn-soft);
  color: var(--warn);
}
.done-info.warn .ex {
  background: var(--warn);
}

/* 완료 화면 하단 액션바 — 완료 / 추가 등록하기 */
.done-foot {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-top: 1px solid var(--line);
  background: #fff;
}
.done-foot .df-sub {
  flex: 0 0 auto;
  padding: 14px 22px;
  border-radius: 12px;
  background: var(--gray-1);
  color: var(--gray-6);
  font-weight: 800;
  font-size: 14px;
  border: none;
  cursor: pointer;
  font-family: inherit;
}
.done-foot .df-main {
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

/* 안내 토스트(기본 accent) */
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
/* 저장 실패 — danger(red) */
.next-notice.err {
  background: var(--danger-soft);
  color: var(--danger);
}
/* 과거 미납 알림톡(mock) 안내 — 즐겨찾기·증빙 계열 warn(amber) 톤으로 구분 */
.next-notice.mock {
  background: var(--warn-soft);
  color: var(--warn);
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
