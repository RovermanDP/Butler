"""Flow C 라우터 — POST /api/repair-allocation (PRD 4.3).

요청 검증(원인 enum·양수 비용)은 Pydantic 이 담당해 잘못된 입력은 422 로 응답한다.
산출 로직·저장은 services.repair_allocation 에 위임(SRP).
"""
from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..services.repair_allocation import (
    CAUSE_AGING,
    CAUSE_NEGLIGENCE,
    allocate,
    save_allocation,
)

router = APIRouter(prefix="/api", tags=["repair-allocation"])


class AllocationRequest(BaseModel):
    expense_id: str | None = None  # 저장 시 FK(없어도 산출은 가능)
    item: str = Field(..., min_length=1)  # "201호 냉장고 수리"
    cost: int = Field(..., gt=0)  # 165000 (원)
    cause: Literal[CAUSE_AGING, CAUSE_NEGLIGENCE]  # '노후·자연마모' | '사용 부주의'
    usage_years: int = Field(..., ge=0)  # 설치 후 경과 연수


class AllocationResponse(BaseModel):
    landlord_ratio: int
    tenant_ratio: int
    landlord_amount: int
    tenant_amount: int
    basis_lh: str
    basis_court: str


@router.post("/repair-allocation", response_model=AllocationResponse)
def create_repair_allocation(req: AllocationRequest) -> AllocationResponse:
    result = allocate(req.item, req.cost, req.cause, req.usage_years)
    save_allocation(req.expense_id, req.item, req.cost, req.cause, req.usage_years, result)
    return AllocationResponse(
        landlord_ratio=result["landlord_ratio"],
        tenant_ratio=result["tenant_ratio"],
        landlord_amount=result["landlord_amount"],
        tenant_amount=result["tenant_amount"],
        basis_lh=result.get("basis_lh") or "",
        basis_court=result.get("basis_court") or "",
    )
