<script setup>
import { reactive, ref, computed } from 'vue'
import { BUILDING_TYPES, insertBuilding } from '../lib/buildings'

// 화면 3 — 건물 등록 폼. 사업자등록번호 기준.
// 5개 필수 필드(주소·건물명·세대/호수·유형·계좌) 모두 채워야 등록 가능.
// 등록 성공 → 'submitted' 로 새 건물 전달(상위가 목록 화면으로 이동시킴).
const emit = defineEmits(['back', 'submitted'])

const form = reactive({
  address: '',
  name: '',
  unitCount: '',
  buildingType: '',
  accountInfo: '',
})

// 필수 필드 정의(검증 + 에러 메시지 단일 출처)
const requiredFields = [
  { key: 'address', label: '건물 주소' },
  { key: 'name', label: '건물명' },
  { key: 'unitCount', label: '세대/호수' },
  { key: 'buildingType', label: '건물 유형' },
  { key: 'accountInfo', label: '계좌 정보' },
]

const touched = reactive({})
const submitAttempted = ref(false)
const submitting = ref(false)
const submitError = ref('')

function fieldEmpty(key) {
  const v = form[key]
  if (key === 'unitCount') return !(Number(v) > 0)
  return String(v).trim() === ''
}

const isValid = computed(() => requiredFields.every((f) => !fieldEmpty(f.key)))

// 해당 필드를 건드렸거나 등록 시도한 뒤에만 에러 노출(첫 진입 시 빨갛게 X)
function showError(key) {
  return (touched[key] || submitAttempted.value) && fieldEmpty(key)
}

function markTouched(key) {
  touched[key] = true
}

async function onSubmit() {
  submitAttempted.value = true
  submitError.value = ''
  if (!isValid.value || submitting.value) return // 비활성 + 연속 클릭 방어

  submitting.value = true
  try {
    const building = await insertBuilding({
      // 사업자등록번호는 화면 3(와이어프레임)에 입력 필드가 없다 → 내부적으로 null.
      // (스키마 nullable. 별도 요구가 생기면 그때 필드를 추가한다.)
      business_reg_no: null,
      address: form.address.trim(),
      name: form.name.trim(),
      unit_count: Number(form.unitCount),
      building_type: form.buildingType,
      account_info: form.accountInfo.trim(),
    })
    emit('submitted', building)
  } catch (e) {
    // 네트워크/환경 미설정/DB 오류를 삼키지 않고 사용자에게 노출
    submitError.value = `등록에 실패했습니다: ${e.message}`
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="scr">
    <div class="tbar">
      <button class="ico back" type="button" aria-label="뒤로" @click="emit('back')">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <span class="ttl">건물 등록</span>
      <span class="ico"></span>
    </div>

    <div class="body">
      <div class="intro">건물을 등록하고<br />편리하게 관리해보세요</div>
      <div class="intro-sub">사업자등록번호 기준으로 등록해주세요</div>

      <!-- 건물 주소 -->
      <label class="flab"><span class="req"></span>건물 주소</label>
      <input
        v-model="form.address"
        class="fin input"
        :class="{ filled: form.address.trim(), err: showError('address') }"
        type="text"
        placeholder="예) 서울 마포구 신촌로 12"
        @blur="markTouched('address')"
      />
      <p v-if="showError('address')" class="ferr">건물 주소를 입력해주세요</p>

      <!-- 건물명 -->
      <label class="flab"><span class="req"></span>건물명</label>
      <input
        v-model="form.name"
        class="fin input"
        :class="{ filled: form.name.trim(), err: showError('name') }"
        type="text"
        placeholder="예) Butler 03호점(신촌)"
        @blur="markTouched('name')"
      />
      <p v-if="showError('name')" class="ferr">건물명을 입력해주세요</p>

      <!-- 세대/호수 -->
      <label class="flab"><span class="req"></span>세대/호수</label>
      <div class="fin input suffix" :class="{ filled: Number(form.unitCount) > 0, err: showError('unitCount') }">
        <input
          v-model="form.unitCount"
          class="bare"
          type="number"
          min="1"
          placeholder="예) 16"
          @blur="markTouched('unitCount')"
        />
        <span class="unit">세대</span>
      </div>
      <p v-if="showError('unitCount')" class="ferr">세대/호수를 1 이상으로 입력해주세요</p>

      <!-- 건물 유형 -->
      <label class="flab"><span class="req"></span>건물 유형</label>
      <select
        v-model="form.buildingType"
        class="fin input select"
        :class="{ filled: form.buildingType, err: showError('buildingType') }"
        @change="markTouched('buildingType')"
      >
        <option value="" disabled>건물 유형 선택</option>
        <option v-for="t in BUILDING_TYPES" :key="t" :value="t">{{ t }}</option>
      </select>
      <p v-if="showError('buildingType')" class="ferr">건물 유형을 선택해주세요</p>

      <!-- 계좌 정보 -->
      <label class="flab"><span class="req"></span>계좌 정보</label>
      <input
        v-model="form.accountInfo"
        class="fin input"
        :class="{ filled: form.accountInfo.trim(), err: showError('accountInfo') }"
        type="text"
        placeholder="예) 신한 110-123-456789 (홍길동)"
        @blur="markTouched('accountInfo')"
      />
      <p v-if="showError('accountInfo')" class="ferr">입금 계좌 정보를 입력해주세요</p>

      <p v-if="submitError" class="submit-error">{{ submitError }}</p>

      <button
        class="submit"
        type="button"
        :disabled="!isValid || submitting"
        @click="onSubmit"
      >
        {{ submitting ? '등록 중…' : '등록하기' }}
      </button>
    </div>
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
  padding: 13px 15px 24px;
}
.intro {
  font-size: 16px;
  font-weight: 800;
  line-height: 1.35;
}
.intro-sub {
  font-size: 11px;
  color: var(--gray-4);
  margin-top: 5px;
}
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
  justify-content: space-between;
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
.select {
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23A8A8B3' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
  background-size: 16px;
  padding-right: 34px;
}
.suffix {
  gap: 8px;
}
.suffix .bare {
  flex: 1;
  border: none;
  outline: none;
  background: none;
  font-family: inherit;
  font-size: 13px;
  font-weight: 700;
  color: var(--ink);
}
.suffix .bare::placeholder {
  color: var(--gray-4);
  font-weight: 400;
}
.suffix .unit {
  font-size: 12px;
  color: var(--gray-5);
  font-weight: 700;
}
.ferr {
  margin: 6px 2px 0;
  font-size: 11px;
  font-weight: 600;
  color: var(--danger);
}
.submit-error {
  margin: 16px 0 0;
  padding: 11px 12px;
  border-radius: 12px;
  background: var(--danger-soft);
  color: var(--danger);
  font-size: 12px;
  font-weight: 700;
  text-align: center;
  word-break: break-all;
}
.submit {
  width: 100%;
  margin: 18px 0 4px;
  border: none;
  background: var(--accent);
  color: #fff;
  border-radius: var(--r-button);
  padding: 14px;
  text-align: center;
  font-weight: 800;
  font-size: 14px;
  font-family: inherit;
  cursor: pointer;
}
.submit:disabled {
  background: var(--gray-3);
  cursor: not-allowed;
}
</style>
