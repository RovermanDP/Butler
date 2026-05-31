import { supabase, supabaseConfigError } from './supabase'

const DOCS_BUCKET = 'tenant-docs'

function storagePathFromUrl(value) {
  if (!value) return ''
  if (!/^https?:\/\//i.test(value)) return value.replace(/^\/+/, '')

  try {
    const { pathname } = new URL(value)
    const marker = `/storage/v1/object/public/${DOCS_BUCKET}/`
    const idx = pathname.indexOf(marker)
    if (idx === -1) return ''
    return decodeURIComponent(pathname.slice(idx + marker.length))
  } catch {
    return ''
  }
}

function tenantDocumentPaths(contracts) {
  const paths = []
  for (const c of contracts ?? []) {
    paths.push(storagePathFromUrl(c.contract_file_url))
    paths.push(storagePathFromUrl(c.proof_biz_license_url))
  }
  return [...new Set(paths.filter(Boolean))]
}

// 건물 상세 탭(세입자·수납·지출) 데이터 접근 — Supabase 직결(CLAUDE.md 책임 분담: 조회는 FastAPI 미경유).
// BuildingDetail 이 진입 시 한 번 조회해 자식 탭(TenantsTab/PaymentsTab/ExpensesTab)에 props 로 내려준다.
// 세입자/수납 탭은 같은 tenants+contracts+payments 소스를 공유하므로 한 함수(OSoT)로 묶는다.

// 세입자 + (계약 다건 + 회차) 중첩 조회. PostgREST 임베딩으로 1회에 가져온 뒤 JS 후처리한다.
//
// ⚠ phone 필터: seed 의 집계용 채움 세입자("03호점 세입자N")는 insert(building_id,name)만 해 phone 이 null 이다
//   (seed.sql 주석: "상세 탭에는 노출되지 않으나 … View 가 계산"). 김동락(데모)·Flow E 등록 세입자는
//   phone 이 항상 채워지므로, phone 보유 세입자만 노출하면 채움 데이터는 숨고 등록분은 보인다.
//
// 반환: [{ id, name, tenant_type, memo, phone, primary, contractCount, payments, notifications }]
//   · primary       : 표시 기준 계약(계약중 우선 → is_primary → 첫 행). 계약 없는 세입자는 제외.
//   · payments      : primary 계약의 회차(round_no 내림차순 = 최근 회차 먼저, 와이어프레임 9→6).
//   · notifications : primary 계약의 알림톡(sent_at 내림차순 = 최근 먼저). 세입자 상세 정보 탭(6a)에서 사용.
//     알림톡은 contracts(*) 안에 notifications(*) 로 임베드해 1회 조회한다(추가 왕복 없음).
export async function fetchTenantsWithPayments(buildingId) {
  if (!supabase) throw new Error(supabaseConfigError)
  const { data, error } = await supabase
    .from('tenants')
    .select('id, name, tenant_type, memo, phone, created_at, contracts(*, payments(*), notifications(*))')
    .eq('building_id', buildingId)
    .not('phone', 'is', null)
    .order('created_at', { ascending: false })
  if (error) throw new Error(error.message)

  return (data ?? [])
    .map((t) => {
      const contracts = t.contracts ?? []
      const primary =
        contracts.find((c) => c.status === '계약중') ??
        contracts.find((c) => c.is_primary) ??
        contracts[0] ??
        null
      if (!primary) return null // 계약 없는 세입자는 상세 탭에서 제외(방어)
      const payments = [...(primary.payments ?? [])].sort((a, b) => b.round_no - a.round_no)
      const notifications = [...(primary.notifications ?? [])].sort((a, b) =>
        String(b.sent_at ?? '').localeCompare(String(a.sent_at ?? '')),
      )
      return {
        id: t.id,
        name: t.name,
        tenant_type: t.tenant_type,
        memo: t.memo,
        phone: t.phone,
        primary,
        contractCount: contracts.length,
        payments,
        notifications,
      }
    })
    .filter(Boolean)
}

// 세입자 삭제(화면 6d · PRD 4.2 B-3). DB 는 tenants 1행 delete 만 하면 FK on delete cascade 로
// 해당 세입자의 contracts·payments·notifications 가 연쇄 삭제된다(Supabase 직결, 별도 엔드포인트 불필요).
// 계약서·사업자등록증은 Storage 객체라 FK cascade 대상이 아니므로 DB 삭제 전에 같은 함수에서 정리한다.
// 책임 분담: 단순 CRUD 라 FastAPI 미경유(CLAUDE.md). 에러는 삼키지 않고 throw 한다.
export async function deleteTenant(tenantId) {
  if (!supabase) throw new Error(supabaseConfigError)
  const { data: contracts, error: readError } = await supabase
    .from('contracts')
    .select('contract_file_url, proof_biz_license_url')
    .eq('tenant_id', tenantId)
  if (readError) throw new Error(readError.message)

  const paths = tenantDocumentPaths(contracts)
  if (paths.length) {
    const { error: storageError } = await supabase.storage.from(DOCS_BUCKET).remove(paths)
    if (storageError) throw new Error(`첨부 문서 삭제에 실패했습니다: ${storageError.message}`)
  }

  const { error } = await supabase.from('tenants').delete().eq('id', tenantId)
  if (error) throw new Error(error.message)
}

// 수동 수납 처리(화면 7 ✎ · PRD 4.2 B-4). 대표 회차 1건의 상태를 갱신한다.
// PG·자동 수납 연동 없음 — payments 1행 update 만(완납 시 paid_date 기록, 그 외 null 로 초기화).
// 책임 분담: 단순 CRUD 라 FastAPI 미경유 Supabase 직결(CLAUDE.md).
export async function updatePaymentStatus(paymentId, status, paidDate) {
  if (!supabase) throw new Error(supabaseConfigError)
  const { error } = await supabase
    .from('payments')
    .update({ status, paid_date: status === '완납' ? paidDate : null })
    .eq('id', paymentId)
  if (error) throw new Error(error.message)
}

// 건물 지출 목록(지출 탭). 월 필터는 두지 않는다 — 정보 탭이 month bar 를 장식으로만 쓰고 집계를 전체로 내듯,
// 지출도 건물 전체를 합산한다(seed 날짜가 2022-10 라 월필터 시 0건이 되는 것도 방지).
export async function fetchBuildingExpenses(buildingId) {
  if (!supabase) throw new Error(supabaseConfigError)
  const { data, error } = await supabase
    .from('expenses')
    .select('id, expense_date, title, amount, proof_type, is_repair')
    .eq('building_id', buildingId)
    .order('expense_date', { ascending: false })
  if (error) throw new Error(error.message)
  return data ?? []
}
