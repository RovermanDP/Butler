"""Flow D — 자동 알림톡 미리보기·발송 스케줄·발송(mock) 로직 (PRD 4.4).

책임(SRP): 카카오 알림톡 미리보기 템플릿 치환 + 발송 스케줄 계산 + 발송(mock) 기록.
- 미리보기: 계약 데이터(세대·금액·납부기한·계좌)를 종류별 템플릿에 치환.
- 발송 스케줄: 계약 납부일·종료일 기준 D-1·D-day / D+2·4·7 / D-60 / D-3 시점 계산(고정 정책).
- 발송: 실제 카카오 API 미연동 → notifications 1행 mock 기록(status='mock_sent', sent_at=now).
  └ 저장 실패가 응답을 막지 않도록 best-effort(repair_allocation.save_allocation 과 동일 기조).

⚠ 실제 카카오 알림톡 발송은 PoC 범위 외(6.1 — 템플릿 심사 기간). 미리보기·히스토리·스케줄
  UI까지만 진짜 구현하고, 발송 인프라 연동은 차기 범위. (히스토리 '조회'는 Supabase 직결 — lib/notifications)
"""
from __future__ import annotations

import calendar
import logging
from datetime import date, datetime, timedelta, timezone

from ..db import get_supabase

logger = logging.getLogger(__name__)

KST = timezone(timedelta(hours=9))

# 알림톡 종류(한글 그대로 — CLAUDE.md 컨벤션 / 스키마 CHECK 와 동일 문자열).
TYPE_PAY, TYPE_MISS, TYPE_EXT, TYPE_END = "납부", "미납", "연장", "종료"


# ── 날짜 유틸(결정적 계산) ───────────────────────────────────
def _today() -> date:
    return datetime.now(KST).date()


def _last_day(y: int, m: int) -> int:
    return calendar.monthrange(y, m)[1]


def _next_due(payment_day: int | None, today: date) -> date | None:
    """납부일(1~31, 말일 보정) 기준 오늘 포함 이후 가장 가까운 납부 예정일."""
    if not payment_day:
        return None
    d = max(1, min(int(payment_day), 31))
    y, m = today.year, today.month
    cand = date(y, m, min(d, _last_day(y, m)))
    if cand < today:
        m += 1
        if m > 12:
            m, y = 1, y + 1
        cand = date(y, m, min(d, _last_day(y, m)))
    return cand


def _parse(iso: str | None) -> date | None:
    if not iso:
        return None
    try:
        return datetime.strptime(iso[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def _fmt_kor(d: date) -> str:
    return f"{d.month}월 {d.day}일"


def _fmt_dot(d: date) -> str:
    return f"{str(d.year)[2:]}.{d.month:02d}.{d.day:02d}"


def _won(n: int) -> str:
    return f"{int(n or 0):,} 원"


def build_schedule(payment_day: int | None, contract_end: str | None) -> list[dict]:
    """발송 스케줄(고정 정책 + 계약 기준 계산일).

    D-1·D-day 납부 안내(18:00) / D+2·4·7 미납 안내(13:00) /
    D-60 연장 여부(AM 10:00) / D-3 계약 종료(AM 10:00). (CLAUDE.md 알림톡 발송 스케줄)
    날짜는 계약 데이터가 있을 때만 계산하고, 매월 반복(미납)은 None 으로 둔다.
    """
    today = _today()
    due = _next_due(payment_day, today)
    end = _parse(contract_end)
    ext_date = end - timedelta(days=60) if end else None
    end_date = end - timedelta(days=3) if end else None
    return [
        {"badge": "D-1·D-day", "label": "납부 안내", "time": "18:00 자동발송",
         "date": _fmt_dot(due) if due else None},
        {"badge": "D+2·4·7", "label": "미납 안내", "time": "13:00 자동발송", "date": None},
        {"badge": "D-60", "label": "연장 여부 안내", "time": "AM 10:00 발송",
         "date": _fmt_dot(ext_date) if ext_date else None},
        {"badge": "D-3", "label": "계약 종료 안내", "time": "AM 10:00 발송",
         "date": _fmt_dot(end_date) if end_date else None},
    ]


def build_preview(
    *,
    type: str,
    tenant_name: str,
    building_name: str,
    unit_no: str,
    amount: int,
    payment_day: int | None,
    contract_end: str | None,
    bank_account: str,
) -> dict:
    """종류별 카카오 미리보기(말풍선 제목·라인·버튼) + 발송 스케줄 생성."""
    name = tenant_name or "세입자"
    sedae = f"{building_name} {unit_no}".strip() or building_name or "-"
    due = _next_due(payment_day, _today())
    due_str = _fmt_kor(due) if due else "납부일"
    end = _parse(contract_end)

    if type == TYPE_MISS:
        title = f"[임대료 미납 안내] {name}님"
        lines = [
            {"label": "세대정보", "value": sedae},
            {"label": "미납금액", "value": _won(amount)},
            {"label": "납부기한", "value": due_str},
            {"label": "입금계좌", "value": bank_account},
        ]
        action = "지금 납부하기"
    elif type == TYPE_EXT:
        title = f"[계약 연장 안내] {name}님"
        lines = [
            {"label": "세대정보", "value": sedae},
            {"label": "계약 만료일", "value": _fmt_kor(end) if end else "-"},
            {"label": "안내", "value": "계약 연장 여부를 회신해 주세요."},
        ]
        action = "연장 의사 회신"
    elif type == TYPE_END:
        title = f"[계약 종료 안내] {name}님"
        lines = [
            {"label": "세대정보", "value": sedae},
            {"label": "계약 종료일", "value": _fmt_kor(end) if end else "-"},
            {"label": "안내", "value": "원활한 퇴실 정산을 위해 미리 안내드립니다."},
        ]
        action = "정산 내역 보기"
    else:  # 납부(기본)
        title = f"[임대료 납부 안내] {name}님"
        lines = [
            {"label": "세대정보", "value": sedae},
            {"label": "납부총액", "value": _won(amount)},
            {"label": "납부기한", "value": due_str},
            {"label": "입금계좌", "value": bank_account},
        ]
        action = "카드로 결제하기"

    return {
        "title": title,
        "lines": lines,
        "action": action,
        "schedule": build_schedule(payment_day, contract_end),
    }


def send_mock(contract_id: str, type: str, title: str, body: str | None) -> dict:
    """실제 카카오 발송 대신 mock 기록(status='mock_sent', sent_at=now) — 6.1.

    Supabase 기록을 시도하되 실패해도 데모를 막지 않는다(저장 실패는 경고만).
    반환: { id, sent_at, status, persisted }.
    """
    now = datetime.now(KST)
    row = {
        "contract_id": contract_id,
        "type": type,
        "title": title,
        "body": body,
        "sent_at": now.isoformat(),
        "status": "mock_sent",
    }
    new_id, persisted = None, False
    try:
        res = get_supabase().table("notifications").insert(row).execute()
        if res.data:
            new_id = res.data[0].get("id")
            persisted = True
    except Exception:  # noqa: BLE001 — 키 미설정·네트워크 실패 등. 데모 진행 우선(경고만).
        logger.warning("notifications mock 저장 실패(응답은 유지)", exc_info=True)

    return {"id": new_id, "sent_at": now.isoformat(), "status": "mock_sent", "persisted": persisted}
