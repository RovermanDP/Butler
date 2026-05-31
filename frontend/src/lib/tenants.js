import { supabase, supabaseConfigError } from './supabase'

// 세입자 등록(Flow E) 저장 — Supabase 직결 CRUD 의 단일 진실 공급원(OSoT).
// CLAUDE.md 책임 분담: 등록은 대부분 단순 CRUD라 FastAPI를 거치지 않고 Supabase 로 직결한다.
//   결정적 계산(첫 납부일·매월 총액·회차)은 이미 lib/payment·contractAmount 에서 끝났고,
//   여기서는 그 결과(payload)를 tenants → contractors → contracts → payments → notifications 로 적재만 한다.
// 원자성: 멀티테이블 트랜잭션(RPC) 대신, 순차 insert 를 try 로 묶고 실패 시 tenants 행과
//    업로드된 Storage 파일을 함께 보상 삭제해 부분 적재를 막는다(registerTenant 주석 참조).
//    모든 실패는 삼키지 않고 의미 있는 한글 메시지로 throw 하여 화면에서 사용자에게 노출한다.

// 업로드 문서 버킷 — 계약서·사업자등록증(Storage 저장까지만, OCR·검증 없음 · 6.3 범위).
const DOCS_BUCKET = 'tenant-docs'

// 파일 1건 업로드 → public URL. 파일이 없으면 null.
// ⚠ 버킷 미설정 등 업로드 실패는 '선택' 파일이므로 등록 자체를 막지 않는다 — 경고만 모아 호출부로 돌려준다
//   (에러를 무음 처리하지 않되, 필수 아닌 첨부 때문에 등록 전체가 깨지지 않도록).
async function uploadDoc(file, prefix) {
  if (!file) return { url: null, path: null, warning: '' }
  // 파일명에 한글/공백이 있어도 Storage 키로 안전하도록 정규화 + 충돌 방지 prefix.
  const safeName = file.name.replace(/[^\w.\-]/g, '_')
  const path = `${prefix}/${Date.now()}_${safeName}`
  const { error } = await supabase.storage.from(DOCS_BUCKET).upload(path, file, { upsert: false })
  if (error) {
    console.warn('[Butler] 문서 업로드 실패', path, error.message)
    return { url: null, path: null, warning: `${file.name} 업로드 실패: ${error.message}` }
  }
  const { data } = supabase.storage.from(DOCS_BUCKET).getPublicUrl(path)
  return { url: data?.publicUrl ?? null, path, warning: '' }
}

async function removeUploadedDocs(paths) {
  if (!paths.length) return ''
  const { error } = await supabase.storage.from(DOCS_BUCKET).remove(paths)
  if (!error) return ''
  console.error('[Butler] 등록 실패 후 Storage 보상 삭제 실패', error.message)
  return error.message
}

// 0/빈문자/NaN → null (선택 금액 필드용). 양수만 유효값으로 본다.
function positiveOrNull(value) {
  const n = Number(value)
  return n > 0 ? n : null
}

// payload(=TenantRegister.buildPayload 결과) 적재. 성공 시 { tenantId, contractId, warnings } 반환.
// 원자성(PRD §548 "등록 저장(일괄)"): 핵심 적재(tenants→contractors→contracts→payments)를 한 try 로
//   묶고, 어느 단계든 실패하면 tenants 행과 선업로드 파일을 삭제한다. 스키마의 on delete cascade 가 하위
//   (contractors/contracts/payments/notifications)를 일괄 정리하고, Storage remove 가 파일 고아화를 막는다.
export async function registerTenant(p) {
  if (!supabase) throw new Error(supabaseConfigError)
  const warnings = []
  const uploadedPaths = []
  const isTaxProof = p.proofKind === '세금계산서' || p.proofKind === '계산서'

  // ── 1) 파일 업로드 — DB 쓰기 전에 끝낸다. ──────────────────────────────
  // 세금계산서/계산서의 사업자등록증은 DB 제약(contracts_proof_subfield_chk)상 필수다.
  //   누락·업로드 실패를 warning 으로 넘기고 null 로 contract insert 하면 CHECK 위반으로 계약 저장이
  //   깨지면서 앞선 tenants/contractors 가 고아로 남는다 → 여기서 즉시 중단해 DB를 전혀 건드리지 않는다.
  let licenseUrl = null
  let contractDoc = { url: null, path: null, warning: '' }
  try {
    if (isTaxProof) {
      if (!p.proofLicenseFile) throw new Error('사업자 등록증을 업로드해주세요')
      const r = await uploadDoc(p.proofLicenseFile, 'biz-license')
      if (!r.url) throw new Error(`사업자 등록증 업로드에 실패했습니다: ${r.warning || '잠시 후 다시 시도해주세요'}`)
      licenseUrl = r.url
      if (r.path) uploadedPaths.push(r.path)
    }
    // 임대차 계약서는 선택 — 업로드 실패해도 null 로 진행(스키마 허용)하고 경고만 모은다.
    contractDoc = await uploadDoc(p.contractFile, 'contracts')
    if (contractDoc.warning) warnings.push(contractDoc.warning)
    if (contractDoc.path) uploadedPaths.push(contractDoc.path)
  } catch (e) {
    const storageErr = await removeUploadedDocs(uploadedPaths)
    if (storageErr) {
      throw new Error(`${e.message} (실패 후 Storage 파일 정리도 실패했습니다 — 확인이 필요합니다: ${storageErr})`)
    }
    throw e
  }

  const isPerson = p.tenantType === '개인'
  const primary = isPerson ? (p.contractors?.[0] ?? {}) : {}
  const tenantName = (isPerson ? primary.name : p.bizName)?.trim() || ''

  // ── 2) 핵심 적재(원자 단위) — 실패 시 catch 에서 tenants 삭제로 cascade 롤백. ──
  let tenantId = null
  try {
    // tenants — 개인=대표 계약자명·연락처 / 사업자=사업자명·담당자명·연락처.
    const { data: tenant, error: tErr } = await supabase
      .from('tenants')
      .insert({
        building_id: p.buildingId,
        tenant_type: p.tenantType,
        name: tenantName,
        phone: (isPerson ? primary.phone : p.bizPhone)?.trim() || null,
        manager_name: isPerson ? null : p.managerName?.trim() || null,
        memo: p.memo?.trim() || null,
      })
      .select('id')
      .single()
    if (tErr) throw new Error(`세입자 저장에 실패했습니다: ${tErr.message}`)
    tenantId = tenant.id

    // contractors — 개인 경로의 계약자1 + 공동계약자(이름 있는 행만). 첫 행만 is_primary.
    if (isPerson) {
      const rows = (p.contractors ?? [])
        .filter((c) => c.name?.trim())
        .map((c, i) => ({
          tenant_id: tenantId,
          name: c.name.trim(),
          phone: c.phone?.trim() || null,
          is_primary: i === 0,
        }))
      if (rows.length) {
        const { error } = await supabase.from('contractors').insert(rows)
        if (error) throw new Error(`계약자 저장에 실패했습니다: ${error.message}`)
      }
    }

    // contracts — 금액·부가세·납부·증빙 설정 + 업로드 URL. status='계약중'.
    //   전세는 monthly_rent=null·rent_vat=false (폼에서 이미 정규화됐지만 저장 단계에서도 방어).
    const { data: contract, error: cErr } = await supabase
      .from('contracts')
      .insert({
        tenant_id: tenantId,
        building_id: p.buildingId,
        unit_no: p.unitNo,
        contract_start: p.start,
        contract_end: p.end,
        lease_type: p.leaseType,
        deposit: positiveOrNull(p.deposit),
        monthly_rent: p.leaseType === '월세' ? positiveOrNull(p.monthlyRent) : null,
        maintenance_fee: Number(p.maintenanceFee) || 0,
        etc_fee1: Number(p.etcFee1) || 0,
        etc_fee2: Number(p.etcFee2) || 0,
        rent_vat: p.leaseType === '월세' ? !!p.rentVat : false,
        maintenance_vat: !!p.maintenanceVat,
        etc1_vat: !!p.etc1Vat,
        etc2_vat: !!p.etc2Vat,
        payment_day: p.paymentDay,
        payment_timing: p.paymentTiming,
        first_payment_date: p.firstPaymentDate,
        depositor_name: p.depositorName?.trim() || tenantName,
        proof_kind: p.proofKind || null,
        proof_phone: p.proofKind === '현금영수증(개인소득공제용)' ? p.proofPhone?.trim() || null : null,
        proof_biz_reg_no: p.proofKind === '현금영수증(사업자증빙용)' ? p.proofBizRegNo?.trim() || null : null,
        proof_email: isTaxProof ? p.proofEmail?.trim() || null : null,
        proof_biz_license_url: licenseUrl,
        contract_file_url: contractDoc.url,
        status: '계약중',
        is_primary: true,
      })
      .select('id')
      .single()
    if (cErr) throw new Error(`계약 저장에 실패했습니다: ${cErr.message}`)

    // payments — 회차표(첫 납부일~종료일, 과거 미납 시드 포함)를 그대로 일괄 insert.
    const isPostpaid = p.paymentTiming === '후불'
    const payRows = (p.schedule ?? []).map((r) => ({
      contract_id: contract.id,
      round_no: r.round_no,
      amount: r.amount,
      due_date: r.due_date,
      status: r.status,
      is_postpaid: isPostpaid,
    }))
    if (payRows.length) {
      const { error } = await supabase.from('payments').insert(payRows)
      if (error) throw new Error(`수납 회차 저장에 실패했습니다: ${error.message}`)
    }

    // ── 3) 부수 기록(best-effort) — 과거 미납분 → 미납 안내 알림톡(mock). ──
    // 핵심 적재가 모두 끝난 뒤이므로 실패해도 throw 하지 않고 경고만 남긴다(등록 자체는 유효 →
    // 보상 삭제를 트리거하지 않는다). 이 단계 실패로 정상 계약·회차까지 지워지면 더 나쁜 UX.
    const unpaidRounds = payRows.filter((r) => r.status === '미납')
    if (unpaidRounds.length) {
      const sentAt = new Date().toISOString()
      const notiRows = unpaidRounds.map((r) => ({
        contract_id: contract.id,
        type: '미납',
        title: `${r.round_no}회차 미납 안내 알림톡`,
        body: `${tenantName}님, ${r.due_date} 납부 예정분(${Number(r.amount).toLocaleString('ko-KR')}원)이 미납되었습니다.`,
        sent_at: sentAt,
        status: 'mock_sent',
      }))
      const { error } = await supabase.from('notifications').insert(notiRows)
      if (error) {
        console.warn('[Butler] 미납 알림톡(mock) 기록 실패', error.message)
        warnings.push(`미납 알림톡(mock) 기록에 실패했습니다: ${error.message}`)
      }
    }

    return { tenantId, contractId: contract.id, warnings }
  } catch (e) {
    // 보상 삭제 — 선업로드 파일 + tenants 1건 삭제로 cascade(contractors/contracts/payments/notifications) 정리.
    //   부분 적재가 남아 재시도 시 중복·고아가 되는 것을 막는다.
    const cleanupErrors = []
    const storageErr = await removeUploadedDocs(uploadedPaths)
    if (storageErr) cleanupErrors.push(`Storage 파일 정리 실패: ${storageErr}`)

    if (tenantId) {
      const { error: delErr } = await supabase.from('tenants').delete().eq('id', tenantId)
      if (delErr) {
        cleanupErrors.push(`DB 정리 실패: ${delErr.message}`)
        console.error('[Butler] 등록 실패 후 보상 삭제도 실패', delErr.message)
      }
    }
    if (cleanupErrors.length) {
      throw new Error(`${e.message} (실패 후 정리도 실패했습니다 — 확인이 필요합니다: ${cleanupErrors.join(' / ')})`)
    }
    throw e
  }
}
