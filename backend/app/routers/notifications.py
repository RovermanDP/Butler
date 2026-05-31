"""Flow D 라우터 — 자동 알림톡 미리보기·발송(mock) (PRD 4.4).

CLAUDE.md 책임 분담: 알림톡 로직은 FastAPI 경유. 히스토리 '조회'만 Supabase 직결(프론트).
  · POST /api/notifications/preview : 템플릿 치환 미리보기 + 발송 스케줄.
  · POST /api/notifications/send    : 발송(mock) — status='mock_sent' 기록만(실제 카카오 미연동, 6.1).
요청 검증(종류 enum·양수 금액)은 Pydantic 이 담당, 산출·기록은 services.notifications 에 위임(SRP).
"""
from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..services.notifications import (
    TYPE_END,
    TYPE_EXT,
    TYPE_MISS,
    TYPE_PAY,
    build_preview,
    send_mock,
)

router = APIRouter(prefix="/api/notifications", tags=["notifications"])

NotificationType = Literal[TYPE_PAY, TYPE_MISS, TYPE_EXT, TYPE_END]


# ── 미리보기 ─────────────────────────────────────────────────
class PreviewRequest(BaseModel):
    type: NotificationType = TYPE_PAY
    tenant_name: str = ""
    building_name: str = ""
    unit_no: str = ""
    amount: int = Field(default=0, ge=0)  # 매월 입금 예정 총액(원)
    payment_day: int | None = Field(default=None, ge=1, le=31)
    contract_end: str | None = None  # 'YYYY-MM-DD'
    bank_account: str = "우리은행 1004-xxx-xxxxxx"


class PreviewLine(BaseModel):
    label: str
    value: str


class ScheduleItem(BaseModel):
    badge: str
    label: str
    time: str
    date: str | None = None


class PreviewResponse(BaseModel):
    title: str
    lines: list[PreviewLine]
    action: str  # 하단 버튼 라벨(UI only — 실결제·실발송 없음)
    schedule: list[ScheduleItem]


@router.post("/preview", response_model=PreviewResponse)
def preview(req: PreviewRequest) -> PreviewResponse:
    return PreviewResponse(
        **build_preview(
            type=req.type,
            tenant_name=req.tenant_name,
            building_name=req.building_name,
            unit_no=req.unit_no,
            amount=req.amount,
            payment_day=req.payment_day,
            contract_end=req.contract_end,
            bank_account=req.bank_account,
        )
    )


# ── 발송(mock) ───────────────────────────────────────────────
class SendRequest(BaseModel):
    contract_id: str = Field(..., min_length=1)
    type: NotificationType = TYPE_PAY
    title: str = "알림톡 발송"
    body: str | None = None


class SendResponse(BaseModel):
    id: str | None = None
    sent_at: str
    status: str
    persisted: bool  # Supabase 기록 성공 여부(키 미설정 등이면 false — 데모는 계속)


@router.post("/send", response_model=SendResponse)
def send(req: SendRequest) -> SendResponse:
    return SendResponse(**send_mock(req.contract_id, req.type, req.title, req.body))
