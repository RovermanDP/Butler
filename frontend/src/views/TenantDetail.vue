<script setup>
// 화면 6a/6b/6c + 6d — 세입자 상세 (PRD 4.2 B-3).
import { ref, computed } from 'vue'
import { formatWon } from '../lib/format'
import { formatDotYmd, formatShortDate } from '../lib/contractDates'
import { tenantPaymentSummary } from '../lib/collect'
import { deleteTenant } from '../lib/detail'
import PaymentRounds from '../components/PaymentRounds.vue'

const props = defineProps({
  tenant: { type: Object, required: true },
  buildingName: { type: String, default: '' },
  initialTab: { type: String, default: '정보' },
})

const emit = defineEmits(['back', 'teaser', 'deleted'])

const c = computed(() => props.tenant.primary ?? {})
const sub = ref(['정보', '계약', '수납'].includes(props.initialTab) ? props.initialTab : '정보')

// 수납 요약(6a·6c 공유)
const pay = computed(() => tenantPaymentSummary(props.tenant.payments))

// 알림톡 히스토리 전체보기 토글
const showAllNotifications = ref(false)

const NTAG = { 납부: 'pay', 미납: 'miss', 연장: 'ext', 종료: 'end' }
function ntag(type) {
  return NTAG[type] ?? 'end'
}

// 삭제 확인 모달(6d)
const confirmOpen = ref(false)
const deleting = ref(false)
const delErr = ref('')

async function confirmDelete() {
  if (deleting.value) return
  deleting.value = true
  delErr.value = ''
  try {
    await deleteTenant(props.tenant.id)
    confirmOpen.value = false
    emit('deleted')
  } catch (e) {
    delErr.value = e.message || '삭제에 실패했습니다.'
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="scr">
    <div class="tbar">
      <button class="ico" type="button" aria-label="뒤로" @click="emit('back')">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M15 18L9 12L15 6" /></svg>
      </button>
      <span class="ttl">세입자 상세</span>
      <button class="ico" type="button" aria-label="세입자 삭제" @click="confirmOpen = true">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M3.5 6.5H20.5" />
          <path d="M8 6.5V5.5C8 4.95 8.45 4.5 9 4.5H15C15.55 4.5 16 4.95 16 5.5V6.5" />
          <path d="M7.5 8.5V18.5C7.5 19.6 8.4 20.5 9.5 20.5H14.5C15.6 20.5 16.5 19.6 16.5 18.5V8.5" />
          <path d="M10.5 10.5V16.5" /><path d="M13.5 10.5V16.5" />
        </svg>
      </button>
    </div>

    <div class="body">
      <!-- 헤더 카드 -->
      <div class="tn-headcard">
        <div class="thead">
          <span class="nm">{{ tenant.name }}</span>
          <span class="pill" :class="{ off: c.status !== '계약중' }">{{ c.status }}</span>
          <span class="acts">
            <span class="cbtn call" aria-hidden="true">📞</span>
            <span class="cbtn msg" aria-hidden="true">💬</span>
          </span>
        </div>
      </div>

      <!-- sub-tab -->
      <div class="subtabs">
        <div :class="{ on: sub === '정보' }" @click="sub = '정보'">정보</div>
        <div :class="{ on: sub === '계약' }" @click="sub = '계약'">계약</div>
        <div :class="{ on: sub === '수납' }" @click="sub = '수납'">수납</div>
      </div>

      <!-- ───────── 정보(6a) ───────── -->
      <template v-if="sub === '정보'">
        <div v-if="tenant.memo" class="memo">
          {{ tenant.memo }}<span class="pen" aria-hidden="true">✎</span>
        </div>

        <div class="sub-h">계약 정보</div>
        <div class="contract">
          <div class="ph"><i class="home" aria-hidden="true">🏠</i><b>{{ tenant.name }}</b></div>
          <div class="loc">{{ buildingName }} / {{ c.unit_no }}</div>
          <div class="cdiv"></div>
          <div class="dt">계약기간 &nbsp; {{ formatDotYmd(c.contract_start) }} ~ {{ formatDotYmd(c.contract_end) }}</div>
          <div class="cact">
            <button type="button" @click="emit('teaser', '계약 연장')">계약 연장 ›</button>
            <button type="button" @click="emit('teaser', '계약 종료')">계약 종료 ›</button>
          </div>
        </div>

        <div class="sub-h">수납 정보 <button class="more" type="button" @click="sub = '수납'">›</button></div>
        <div class="totalpay">
          <span class="k">총 입금 금액 <span class="cnt-ok">{{ pay.paidCount }}건</span></span>
          <span class="v">{{ formatWon(pay.paidTotal) }}</span>
        </div>
        <div class="paysum">
          <div class="r"><span class="k">매월 납부일</span><span class="v">{{ c.payment_day }} 일</span></div>
          <div class="r"><span class="k">매월 납부액</span><span class="v">{{ formatWon(pay.monthly) }}</span></div>
          <div class="r">
            <span class="k">미납 <span class="cnt">{{ pay.missCount }} 건</span></span>
            <span class="v red">{{ formatWon(pay.missTotal) }}</span>
          </div>
        </div>

        <!-- 알림톡 히스토리: 최근 3건 + 전체보기 버튼 -->
        <div class="sub-h">
          알림톡 히스토리
          <button
            v-if="(tenant.notifications?.length ?? 0) > 3"
            class="more"
            type="button"
            @click="showAllNotifications = !showAllNotifications"
          >{{ showAllNotifications ? '접기' : '전체보기 ›' }}</button>
        </div>
        <p v-if="!tenant.notifications?.length" class="empty">발송된 알림톡 내역이 없습니다.</p>
        <div
          v-for="n in showAllNotifications
            ? tenant.notifications
            : (tenant.notifications ?? []).slice(0, 3)"
          :key="n.id"
          class="nrow"
        >
          <span class="ntag" :class="ntag(n.type)">{{ n.type }}</span>
          <span class="txt">{{ n.title }}</span>
          <span class="dt">{{ formatShortDate(String(n.sent_at).slice(0, 10)) }}</span>
        </div>
      </template>

      <!-- ───────── 계약(6b) ───────── -->
      <template v-else-if="sub === '계약'">
        <div class="sub-h">계약 정보</div>
        <div class="money">
          <div class="row"><span class="k">계약형태</span><span class="v">{{ c.lease_type }}</span></div>
          <div class="row"><span class="k">보증금</span><span class="v">{{ formatWon(c.deposit) }}</span></div>
          <div v-if="c.lease_type === '월세'" class="row">
            <span class="k">월세 <span v-if="c.rent_vat" class="vat">부가세 포함</span></span>
            <span class="v">{{ formatWon(c.monthly_rent) }}</span>
          </div>
          <div v-if="c.maintenance_fee > 0" class="row">
            <span class="k">관리비 <span v-if="c.maintenance_vat" class="vat">부가세 포함</span></span>
            <span class="v">{{ formatWon(c.maintenance_fee) }}</span>
          </div>
          <div v-if="c.etc_fee1 > 0" class="row">
            <span class="k">기타비용1 <span v-if="c.etc1_vat" class="vat">부가세 포함</span></span>
            <span class="v">{{ formatWon(c.etc_fee1) }}</span>
          </div>
          <div v-if="c.etc_fee2 > 0" class="row">
            <span class="k">기타비용2 <span v-if="c.etc2_vat" class="vat">부가세 포함</span></span>
            <span class="v">{{ formatWon(c.etc_fee2) }}</span>
          </div>
        </div>

        <div class="sub-h">증빙 · 서류</div>
        <div class="paysum">
          <div class="r"><span class="k">증빙 발급 설정</span><span class="v doc">{{ c.proof_kind || '해당없음' }}</span></div>
          <div class="r">
            <span class="k">임대차 계약서</span>
            <a v-if="c.contract_file_url" class="v link" :href="c.contract_file_url" target="_blank" rel="noopener">파일 보기 ›</a>
            <span v-else class="v doc">-</span>
          </div>
          <div v-if="tenant.tenant_type === '사업자'" class="r">
            <span class="k">사업자등록증</span>
            <a v-if="c.proof_biz_license_url" class="v link" :href="c.proof_biz_license_url" target="_blank" rel="noopener">파일 보기 ›</a>
            <span v-else class="v doc">-</span>
          </div>
        </div>
      </template>

      <!-- ───────── 수납(6c) ───────── -->
      <template v-else>
        <div class="payhead">
          <div class="row"><span class="k">매월 납부액</span><span class="v">{{ formatWon(pay.monthly) }}</span></div>
          <div class="row">
            <span class="k">미납 <span class="cnt">{{ pay.missCount }}건</span></span>
            <span class="v red">{{ formatWon(pay.missTotal) }}</span>
          </div>
        </div>
        <div class="payinfo">
          <span class="t">{{ c.lease_type }}</span>
          <span class="t">{{ c.payment_timing }}</span>
          <span class="due">입금 예정일 <b>{{ c.payment_day }} 일</b></span>
        </div>
        <PaymentRounds :payments="tenant.payments" />
      </template>
    </div>

    <!-- 삭제 확인 모달(6d) -->
    <template v-if="confirmOpen">
      <div class="dim" @click="!deleting && (confirmOpen = false)"></div>
      <div class="sheet confirm">
        <div class="cf-ico">🗑</div>
        <div class="cf-title">세입자를 삭제할까요?</div>
        <div class="cf-desc">
          이 세입자의 <b>계약 · 수납 회차 · 알림톡 내역</b>이 모두 함께 삭제되며, 되돌릴 수 없습니다.
        </div>
        <p v-if="delErr" class="cf-err">{{ delErr }}</p>
        <div class="cf-acts">
          <button class="cf-cancel" type="button" :disabled="deleting" @click="confirmOpen = false">취소</button>
          <button class="cf-del" type="button" :disabled="deleting" @click="confirmDelete">
            {{ deleting ? '삭제 중…' : '삭제' }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.scr { flex: 1; display: flex; flex-direction: column; color: var(--ink); overflow: hidden; position: relative; }
.tbar { display: flex; align-items: center; justify-content: space-between; padding: 8px 12px 4px; gap: 8px; }
.tbar .ttl { font-size: 13.5px; font-weight: 800; flex: 1; text-align: center; }
.tbar .ico { border: none; background: none; padding: 0; width: 24px; height: 24px; flex: 0 0 auto; color: var(--ink); cursor: pointer; }
.tbar .ico svg { width: 100%; height: 100%; fill: none; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }
.body { flex: 1; overflow-y: auto; padding: 12px 15px 20px; }
.empty { text-align: center; color: var(--gray-4); font-size: 12px; padding: 22px 0; }
.tn-headcard { border: 1px solid var(--line); border-radius: 12px; padding: 12px 13px; box-shadow: 0 4px 16px rgba(31,31,36,.04), 0 1px 2px rgba(31,31,36,.04); }
.thead { display: flex; align-items: center; gap: 9px; }
.thead .nm { font-size: 17px; font-weight: 800; color: var(--ink); }
.pill { font-size: 10px; font-weight: 700; padding: 3px 9px; border-radius: 8px; background: var(--ok); color: #fff; }
.pill.off { background: var(--gray-3); }
.thead .acts { margin-left: auto; display: flex; gap: 8px; }
.thead .acts .cbtn { width: 28px; height: 28px; border-radius: 50%; background: var(--accent-soft); display: grid; place-items: center; font-size: 13px; }
.subtabs { display: flex; gap: 18px; border-bottom: 1px solid var(--line); margin: 16px 0 14px; }
.subtabs div { font-size: 13.5px; font-weight: 700; color: var(--ink-mute); padding: 0 0 9px; position: relative; cursor: pointer; }
.subtabs div.on { color: var(--ink); font-weight: 800; }
.subtabs div.on::after { content: ''; position: absolute; left: 0; right: 0; bottom: -1px; height: 2px; border-radius: 2px; background: var(--ink); }
.sub-h { font-size: 14px; font-weight: 800; margin: 16px 0 8px; display: flex; align-items: center; gap: 6px; color: var(--ink); }
.sub-h .more { border: none; background: none; font-family: inherit; font-size: 12px; color: var(--accent-deep); background: var(--accent-soft); padding: 3px 10px; border-radius: 8px; cursor: pointer; font-weight: 700; }
.memo { background: var(--gray-1); border-radius: 10px; padding: 11px 12px 30px; font-size: 11.5px; line-height: 1.55; color: var(--ink-soft); position: relative; min-height: 50px; }
.memo .pen { position: absolute; bottom: 10px; right: 11px; color: var(--accent); font-size: 13px; }
.contract { border: 1px solid var(--line); border-radius: 12px; padding: 12px; font-size: 12px; }
.contract .ph { display: flex; align-items: center; gap: 7px; font-weight: 700; color: var(--ink); }
.contract .ph i { width: 20px; height: 20px; border-radius: 7px; background: var(--accent); display: grid; place-items: center; font-size: 11px; flex: 0 0 auto; font-style: normal; }
.contract .loc { font-size: 11.5px; color: var(--ink-soft); font-weight: 600; margin: 5px 0 0 27px; }
.contract .cdiv { border-top: 1px solid var(--line); margin: 11px 0 9px; }
.contract .dt { color: var(--ink-mute); font-size: 11px; }
.contract .cact { display: flex; gap: 8px; margin-top: 12px; }
.contract .cact button { flex: 1; border: none; border-radius: 10px; background: var(--accent-soft); padding: 9px 0; font-size: 11.5px; font-weight: 700; color: var(--accent-deep); font-family: inherit; cursor: pointer; }
.totalpay { display: flex; align-items: center; justify-content: space-between; padding: 6px 2px 12px; }
.totalpay .k { font-size: 12.5px; font-weight: 600; color: var(--ink-soft); display: flex; align-items: center; }
.totalpay .v { font-size: 19px; font-weight: 800; color: var(--ink); }
.totalpay .cnt-ok { font-size: 10px; color: #fff; background: var(--ok); padding: 2px 7px; border-radius: 7px; margin-left: 6px; font-weight: 800; }
.paysum { background: var(--gray-1); border-radius: 10px; padding: 4px 14px; margin-top: 10px; }
.paysum .r { display: flex; align-items: center; justify-content: space-between; padding: 11px 0; }
.paysum .r + .r { border-top: 1px solid var(--line); }
.paysum .k { font-size: 12px; color: var(--ink-soft); font-weight: 600; display: flex; align-items: center; }
.paysum .v { font-size: 14px; font-weight: 800; color: var(--ink); }
.paysum .v.doc { font-size: 12.5px; }
.paysum .v.red { color: var(--danger); }
.paysum .v.link { font-size: 12.5px; color: var(--accent); text-decoration: none; }
.paysum .cnt { font-size: 10px; color: #fff; background: var(--danger); padding: 2px 7px; border-radius: 7px; margin-left: 5px; font-weight: 800; }
.money .row { display: flex; align-items: center; justify-content: space-between; padding: 7px 0; }
.money .k { font-size: 12px; color: var(--ink-mute); font-weight: 600; display: flex; align-items: center; gap: 5px; }
.money .v { font-size: 12.5px; font-weight: 800; color: var(--ink); }
.vat { font-size: 9.5px; background: var(--warn-soft); color: var(--warn); padding: 2px 6px; border-radius: 7px; font-weight: 700; }
/* 알림톡 히스토리 행 */
.nrow { display: flex; align-items: center; gap: 10px; padding: 12px 0; border-bottom: 1px solid var(--line); }
.ntag { font-size: 10px; font-weight: 700; padding: 4px 8px; border-radius: 7px; flex: 0 0 auto; min-width: 34px; text-align: center; }
.ntag.pay { background: var(--ok-soft); color: var(--ok); }
.ntag.miss { background: var(--danger-soft); color: var(--danger); }
.ntag.ext { background: var(--accent-soft); color: var(--accent-deep); }
.ntag.end { background: var(--gray-1); color: var(--ink-soft); }
.nrow .txt { font-size: 11.5px; font-weight: 600; color: var(--ink); flex: 1; }
.nrow .dt { margin-left: auto; font-size: 10.5px; color: var(--ink-mute); }
/* 수납(6c) */
.payhead { background: var(--gray-1); border-radius: 10px; padding: 3px 13px; margin-top: 4px; }
.payhead .row { display: flex; align-items: center; justify-content: space-between; padding: 10px 0; }
.payhead .row + .row { border-top: 1px solid var(--line); }
.payhead .k { font-size: 12px; font-weight: 600; color: var(--ink-soft); display: flex; align-items: center; }
.payhead .v { font-size: 14px; font-weight: 800; color: var(--ink); }
.payhead .v.red { color: var(--danger); }
.payhead .cnt { font-size: 10px; color: var(--danger); background: var(--danger-soft); padding: 1px 6px; border-radius: 6px; margin-left: 5px; font-weight: 700; }
.payinfo { border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px; margin-top: 10px; display: flex; align-items: center; gap: 8px; font-size: 12px; }
.payinfo .t { font-size: 10px; background: var(--gray-1); padding: 3px 7px; border-radius: 7px; font-weight: 700; color: var(--ink-soft); }
.payinfo .due { margin-left: auto; font-weight: 700; }
.payinfo .due b { font-size: 13px; }
/* 삭제 모달 */
.dim { position: absolute; inset: 0; background: rgba(31,31,36,.38); z-index: 7; }
.sheet.confirm { position: absolute; left: 0; right: 0; bottom: 0; z-index: 8; background: #fff; border-top: 1px solid var(--line); border-radius: 20px 20px 0 0; box-shadow: 0 -12px 26px rgba(31,31,36,.12); text-align: center; padding: 24px 20px 20px; }
.confirm .cf-ico { font-size: 30px; margin-bottom: 8px; }
.confirm .cf-title { font-size: 16px; font-weight: 800; color: var(--ink); margin-bottom: 9px; }
.confirm .cf-desc { font-size: 12px; color: var(--ink-soft); line-height: 1.6; margin-bottom: 14px; }
.confirm .cf-desc b { color: var(--danger); font-weight: 800; }
.confirm .cf-err { font-size: 11.5px; color: var(--danger); font-weight: 700; margin-bottom: 12px; }
.confirm .cf-acts { display: flex; gap: 10px; }
.confirm .cf-acts button { flex: 1; border: none; border-radius: 12px; padding: 13px 0; font-weight: 800; font-size: 14px; font-family: inherit; cursor: pointer; }
.confirm .cf-cancel { background: var(--gray-1); color: var(--ink-soft); }
.confirm .cf-del { background: var(--danger); color: #fff; }
.confirm .cf-acts button:disabled { opacity: .6; cursor: default; }
</style>