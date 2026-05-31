<script setup>
// 화면 11·12 — Flow D 자동 알림톡 (PRD 4.4).
// 진입: 건물 상세 · 정보 탭 우측 상단 벨 아이콘(BuildingDetail) → App 라우팅(screen='notifications').
//   · 11 히스토리: 건물 단위 알림톡 내역(종류 색 태그 + 발송일 타임라인). Supabase 직결 조회.
//   · 12 미리보기·발송 시점: 항목 탭 → 카카오 미리보기 + D-1/D+n/D-60/D-3 스케줄(FastAPI 템플릿 치환).
// ⚠ 발송은 mock(6.1) — 미리보기·히스토리·스케줄 UI까지만 진짜 구현. '발송'은 status='mock_sent' 기록만.
//   첨부 레퍼런스의 민트색은 폐기 팔레트 — accent(slate blue)·ok·danger·warn 토큰만 사용.
import { ref, onMounted } from 'vue'
import { formatShortDate } from '../lib/contractDates'
import { monthlyTotal } from '../lib/contractAmount'
import {
  fetchBuildingNotifications,
  requestNotificationPreview,
  sendNotificationMock,
} from '../lib/notifications'

const props = defineProps({
  building: { type: Object, required: true },
})
const emit = defineEmits(['back'])

const view = ref('history') // 'history'(11) | 'preview'(12)

// 종류 → 색 태그 클래스(CLAUDE.md: 납부/미납/연장/종료).
const NTAG = { 납부: 'pay', 미납: 'miss', 연장: 'ext', 종료: 'end' }
function ntag(type) {
  return NTAG[type] ?? 'end'
}

// ── 히스토리(화면 11) ────────────────────────────────────
const items = ref([])
const loading = ref(false)
const loadErr = ref('')

async function loadHistory() {
  loading.value = true
  loadErr.value = ''
  try {
    items.value = await fetchBuildingNotifications(props.building.id)
  } catch (e) {
    loadErr.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(loadHistory)

// ── 미리보기(화면 12) ────────────────────────────────────
const selected = ref(null)
const preview = ref(null)
const previewLoading = ref(false)
const previewErr = ref('')
const sending = ref(false)
const sendMsg = ref('')
const sendKind = ref('ok') // 'ok' | 'err'

async function openPreview(item) {
  selected.value = item
  view.value = 'preview'
  preview.value = null
  previewErr.value = ''
  sendMsg.value = ''
  previewLoading.value = true
  const c = item.contract ?? {}
  // 매월 입금 예정 총액(OSoT: contractAmount.monthlyTotal). 이 함수는 camelCase 키를
  // 기대하므로 Supabase snake_case 계약을 매핑해서 넘긴다(없으면 0 원으로 안전 처리).
  const amount = monthlyTotal({
    leaseType: c.lease_type,
    monthlyRent: c.monthly_rent,
    rentVat: c.rent_vat,
    maintenanceFee: c.maintenance_fee,
    maintenanceVat: c.maintenance_vat,
    etcFee1: c.etc_fee1,
    etc1Vat: c.etc1_vat,
    etcFee2: c.etc_fee2,
    etc2Vat: c.etc2_vat,
  })
  try {
    preview.value = await requestNotificationPreview({
      type: item.type,
      tenant_name: item.tenantName,
      building_name: props.building.name,
      unit_no: c.unit_no ?? '',
      amount,
      payment_day: c.payment_day ?? null,
      contract_end: c.contract_end ?? null,
    })
  } catch (e) {
    previewErr.value = e.message
  } finally {
    previewLoading.value = false
  }
}

function backToHistory() {
  view.value = 'history'
  selected.value = null
  preview.value = null
}

// 발송(mock) — 자동 발송 정책의 해당 안내를 지금 mock 으로 1건 기록한다(실제 카카오 미발송, 6.1).
async function sendMock() {
  if (sending.value || !selected.value) return
  sending.value = true
  sendMsg.value = ''
  try {
    const res = await sendNotificationMock({
      contract_id: selected.value.contract_id,
      type: selected.value.type,
      title: `${selected.value.type} 안내 알림톡 발송`,
    })
    sendKind.value = 'ok'
    sendMsg.value = res.persisted
      ? 'mock 발송 완료 — 히스토리에 기록되었습니다.'
      : 'mock 발송 처리됨(서버 미저장 — 데모 표시).'
    if (res.persisted) await loadHistory() // 새 기록을 11에 반영
  } catch (e) {
    sendKind.value = 'err'
    sendMsg.value = e.message
  } finally {
    sending.value = false
  }
}
</script>

<template>
  <div class="scr">
    <!-- 상단 바: 11 = X(닫기→상세) / 12 = ‹(뒤로→히스토리) -->
    <div class="tbar">
      <button
        class="ico"
        type="button"
        :aria-label="view === 'history' ? '닫기' : '뒤로'"
        @click="view === 'history' ? emit('back') : backToHistory()"
      >
        <svg v-if="view === 'history'" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M6 6L18 18" /><path d="M18 6L6 18" />
        </svg>
        <svg v-else viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M15 18L9 12L15 6" />
        </svg>
      </button>
      <span class="ttl">{{ view === 'history' ? '알림톡 히스토리' : 'Butler 알리미' }}</span>
      <span class="ico" aria-hidden="true"></span>
    </div>

    <!-- ───────── 히스토리(11) ───────── -->
    <div v-if="view === 'history'" class="body">
      <div class="lead">세입자에게 발송되는<br />알림톡 내역입니다</div>

      <p v-if="loading" class="state">불러오는 중…</p>
      <div v-else-if="loadErr" class="state err">
        <p>{{ loadErr }}</p>
        <button type="button" @click="loadHistory">다시 시도</button>
      </div>
      <p v-else-if="!items.length" class="state">발송된 알림톡 내역이 없습니다.</p>

      <template v-else>
        <button v-for="n in items" :key="n.id" class="nrow" type="button" @click="openPreview(n)">
          <span class="ntag" :class="ntag(n.type)">{{ n.type }}</span>
          <span class="txt">
            {{ n.title }}
            <small v-if="n.tenantName">
              {{ n.tenantName }}<span v-if="n.contract?.unit_no"> · {{ n.contract.unit_no }}</span>
            </small>
          </span>
          <span class="dt">{{ formatShortDate(String(n.sent_at).slice(0, 10)) }}</span>
        </button>
      </template>
    </div>

    <!-- ───────── 미리보기 · 발송 시점(12) ───────── -->
    <div v-else class="body">
      <p v-if="previewLoading" class="state">미리보기 생성 중…</p>
      <div v-else-if="previewErr" class="state err">
        <p>{{ previewErr }}</p>
        <button type="button" @click="openPreview(selected)">다시 시도</button>
      </div>

      <template v-else-if="preview">
        <!-- 카카오 메시지 미리보기 -->
        <div class="chat">
          <div class="from"><span class="av" aria-hidden="true">⌂</span>Butler 알리미</div>
          <div class="kbub">
            <span class="kh">알림톡 도착</span>
            <div class="ktitle">{{ preview.title }}</div>
            <div v-for="(l, i) in preview.lines" :key="i" class="kline">
              <span class="ck" aria-hidden="true">✓</span> {{ l.label }} : {{ l.value }}
            </div>
            <div class="pay-btn">{{ preview.action }}</div>
          </div>
        </div>

        <!-- 발송 스케줄 -->
        <div class="sub-h">📋 알림톡 전송 시점</div>
        <div class="timing">
          <div v-for="(s, i) in preview.schedule" :key="i" class="ti">
            <span class="bd" :class="`d${i + 1}`">{{ s.badge }}</span>
            <span class="tt">
              {{ s.label }}
              <small>{{ s.time }}<span v-if="s.date"> · 예정 {{ s.date }}</span></small>
            </span>
          </div>
        </div>

        <!-- 발송은 mock(6.1) — 실제 카카오 연동 없이 히스토리 기록만 -->
        <p class="mocknote">
          실제 카카오 알림톡 발송은 템플릿 심사 후 제공됩니다. 아래는 mock 발송(히스토리 기록)입니다.
        </p>
        <button class="sendbtn" type="button" :disabled="sending" @click="sendMock">
          {{ sending ? '발송 중…' : '지금 mock 발송' }}
        </button>
        <p v-if="sendMsg" class="sendmsg" :class="sendKind">{{ sendMsg }}</p>
      </template>
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
  position: relative;
}
.tbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 12px 4px;
  gap: 8px;
}
.tbar .ttl {
  font-size: 13.5px;
  font-weight: 800;
  flex: 1;
  text-align: center;
}
.tbar .ico {
  border: none;
  background: none;
  padding: 0;
  width: 24px;
  height: 24px;
  flex: 0 0 auto;
  color: var(--ink);
  cursor: pointer;
}
.tbar .ico svg {
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
  padding: 12px 15px 20px;
}
.lead {
  font-size: 13px;
  font-weight: 800;
  line-height: 1.4;
  margin-bottom: 10px;
}
/* 로딩·빈·에러 공통 상태 */
.state {
  text-align: center;
  color: var(--gray-4);
  font-size: 12.5px;
  padding: 40px 0;
}
.state.err {
  color: var(--danger);
}
.state.err button {
  margin-top: 10px;
  border: none;
  background: var(--accent);
  color: #fff;
  border-radius: var(--r-button);
  padding: 9px 18px;
  font-weight: 800;
  font-size: 12px;
  font-family: inherit;
  cursor: pointer;
}
/* 히스토리 행(버튼) */
.nrow {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 12px 2px;
  border: none;
  border-bottom: 1px solid var(--line);
  background: none;
  font-family: inherit;
  text-align: left;
  cursor: pointer;
}
.ntag {
  font-size: 10px;
  font-weight: 700;
  padding: 4px 8px;
  border-radius: 7px;
  flex: 0 0 auto;
  min-width: 34px;
  text-align: center;
}
.ntag.pay {
  background: var(--ok-soft);
  color: var(--ok);
}
.ntag.miss {
  background: var(--danger-soft);
  color: var(--danger);
}
.ntag.ext {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.ntag.end {
  background: var(--gray-1);
  color: var(--ink-soft);
}
.nrow .txt {
  flex: 1;
  min-width: 0;
  font-size: 11.5px;
  font-weight: 600;
  color: var(--ink);
}
.nrow .txt small {
  display: block;
  margin-top: 3px;
  font-size: 10px;
  font-weight: 600;
  color: var(--ink-mute);
}
.nrow .dt {
  flex: 0 0 auto;
  font-size: 10.5px;
  color: var(--ink-mute);
}
/* 카카오 미리보기 */
.chat {
  background: var(--gray-1);
  border-radius: 12px;
  padding: 13px;
  margin-top: 4px;
}
.chat .from {
  font-size: 11px;
  font-weight: 700;
  color: var(--ink-soft);
  display: flex;
  align-items: center;
  gap: 7px;
  margin-bottom: 8px;
}
.chat .from .av {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: var(--accent);
  display: grid;
  place-items: center;
  color: #fff;
  font-size: 10px;
}
.kbub {
  background: #fff;
  border: 1px solid var(--line);
  border-radius: 11px;
  padding: 11px;
  font-size: 11px;
  line-height: 1.7;
  color: var(--ink);
}
.kbub .kh {
  background: #fae100;
  color: #5a3d00;
  font-weight: 800;
  font-size: 10.5px;
  padding: 4px 8px;
  border-radius: 7px;
  display: inline-block;
  margin-bottom: 8px;
}
.kbub .ktitle {
  font-weight: 800;
  margin-bottom: 4px;
}
.kbub .kline {
  font-size: 11px;
}
.kbub .ck {
  color: var(--ok);
  font-weight: 700;
}
.kbub .pay-btn {
  margin-top: 9px;
  background: var(--gray-1);
  border-radius: 8px;
  padding: 9px;
  text-align: center;
  font-weight: 700;
  font-size: 11px;
  color: var(--ink-soft);
}
.sub-h {
  font-size: 14px;
  font-weight: 800;
  margin: 18px 0 10px;
  color: var(--ink);
}
/* 발송 스케줄 */
.timing {
  display: flex;
  flex-direction: column;
  gap: 9px;
}
.timing .ti {
  display: flex;
  align-items: center;
  gap: 10px;
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 10px 11px;
}
.timing .ti .bd {
  font-size: 9.5px;
  font-weight: 800;
  padding: 5px 8px;
  border-radius: 7px;
  flex: 0 0 auto;
  white-space: nowrap;
  min-width: 64px;
  text-align: center;
}
/* 상태 색 매핑: 납부=ok / 미납=danger / 연장=accent / 종료=gray(중립). (CLAUDE.md) */
.timing .ti .bd.d1 {
  background: var(--ok-soft);
  color: var(--ok);
}
.timing .ti .bd.d2 {
  background: var(--danger-soft);
  color: var(--danger);
}
.timing .ti .bd.d3 {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.timing .ti .bd.d4 {
  background: var(--gray-1);
  color: var(--ink-soft);
}
.timing .ti .tt {
  font-size: 11.5px;
  font-weight: 700;
  color: var(--ink);
}
.timing .ti .tt small {
  display: block;
  font-weight: 600;
  color: var(--ink-mute);
  font-size: 10px;
  margin-top: 2px;
}
/* 발송(mock) */
.mocknote {
  margin: 18px 0 10px;
  font-size: 10.5px;
  line-height: 1.5;
  color: var(--warn);
  background: var(--warn-soft);
  border-radius: 10px;
  padding: 10px 12px;
}
.sendbtn {
  width: 100%;
  border: none;
  border-radius: var(--r-button);
  background: var(--accent);
  color: #fff;
  padding: 13px 0;
  font-weight: 800;
  font-size: 13.5px;
  font-family: inherit;
  cursor: pointer;
}
.sendbtn:disabled {
  opacity: 0.6;
  cursor: default;
}
.sendmsg {
  margin-top: 10px;
  font-size: 11.5px;
  font-weight: 700;
  text-align: center;
}
.sendmsg.ok {
  color: var(--ok);
}
.sendmsg.err {
  color: var(--danger);
}
</style>
