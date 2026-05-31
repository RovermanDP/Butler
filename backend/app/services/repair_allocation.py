"""Flow C — AI 수선비 분담 산출 로직 (PRD 4.3).

책임(SRP): 임대인/임차인 분담 비율 산출 + 금액 계산 + 결과 저장(best-effort).
- RAG-lite: LH 가이드라인·대법원 판례 요약을 system 프롬프트에 텍스트로 주입(벡터DB 없음).
- 데모 안정성: 대표 시나리오(냉장고/노후·자연마모/7년 → 70:30)는 LLM 미호출 고정.
  └ 고정 경로는 ANTHROPIC_API_KEY 없이도 동작한다(시연 안정의 핵심).
- LLM 호출 실패/타임아웃 → 50:50 fallback. (CLAUDE.md: 에러를 무음 처리하지 않음)
"""
from __future__ import annotations

import json
import logging
from functools import lru_cache

from anthropic import Anthropic

from ..config import settings
from ..db import get_supabase

logger = logging.getLogger(__name__)

# 산출에 쓰는 발생 원인 enum(스키마 CHECK·프론트 세그먼트와 동일 문자열).
CAUSE_AGING = "노후·자연마모"
CAUSE_NEGLIGENCE = "사용 부주의"

# ------------------------------------------------------------------
# RAG-lite — LH 가이드라인 핵심 규칙 + 대법원 판례 요약(10~20개)을 프롬프트에 주입.
# ------------------------------------------------------------------
GUIDELINES = """
[LH 임대주택 수선비 부담 가이드라인 — 핵심 규칙]
1. 빌트인 가전(냉장고·에어컨·세탁기 등)의 노후·자연마모로 인한 고장은 임대인 부담이 원칙이다.
2. 시설물의 사용 연수가 길수록(내용연수 경과분) 감가를 반영해 임대인 부담 비중을 높인다.
3. 임차인의 고의·과실·관리 소홀(사용 부주의)로 발생한 손상은 임차인 부담이 원칙이다.
4. 통상적인 사용으로 발생하는 소모(통상손모)는 임대인이 부담한다.
5. 소모품(전구·배터리·필터 등) 교체와 경미한 수선은 임차인이 부담한다.
6. 도배·장판은 거주 기간과 노후도에 따라 분담하되, 장기 거주 시 임대인 비중을 높인다.
7. 보일러·급수설비 등 주요 설비의 노후 고장은 임대인 부담, 동파 등 관리 소홀은 임차인 부담.
8. 설비의 내용연수를 초과해 사용 중 고장이 난 경우 임대인 부담 비중을 크게 둔다.
9. 원인이 노후와 부주의가 혼재된 경우 기여도에 따라 비율을 분담한다.
10. 임대차 특약으로 별도 정한 바가 있으면 특약을 우선하되, 불공정 특약은 제한된다.

[대법원·하급심 판례 요약]
11. 통상적 사용에 따른 손모(통상손모)는 특약이 없는 한 임대인이 부담한다(임차인 원상회복 범위 제한).
12. 임차인의 원상회복 의무는 임차인의 귀책으로 생긴 훼손에 한정되고, 자연적 노후화는 제외된다.
13. 임대인은 임대 목적물을 사용·수익에 필요한 상태로 유지할 수선 의무를 진다(민법 제623조 취지).
14. 대규모·구조적 수선은 임대인, 임차인이 쉽게 할 수 있는 소규모 수선은 임차인 부담으로 본 사례.
15. 시설의 내용연수와 사용 기간을 고려해 감가상각분만큼 임차인 배상액을 감액한 사례.
16. 고의·중과실이 입증되지 않으면 손상 책임을 임차인에게 전부 지울 수 없다고 본 사례.
""".strip()

SYSTEM = f"""너는 임대차 수선비 분담 비율 산출기다.
아래 LH 가이드라인과 판례 요약만을 근거로 임대인/임차인 분담 비율을 정한다.
{GUIDELINES}

판단 원칙:
- 노후·자연마모가 원인이면 임대인 비중을 높인다.
- 사용 부주의가 원인이면 임차인 비중을 높인다.
- 사용 연수가 길수록(감가 반영) 임대인 비중을 높인다.
- 비율의 합은 반드시 100 이다.

반드시 아래 JSON 스키마로만 응답한다(서두·설명·코드펜스·마크다운 금지):
{{"landlord_ratio": <int>, "tenant_ratio": <int>,
  "basis_lh": "<LH 가이드라인 근거 한 문장>",
  "basis_court": "<대법원 판례 근거 한 문장>"}}"""

# ------------------------------------------------------------------
# 데모 안정성: 대표 고정 시나리오 (LLM 미호출, 키 불필요).
#   매칭: item 에 키워드 포함 & 원인 일치 & 사용연수 일치.
# ------------------------------------------------------------------
FIXED: dict[tuple[str, str, int], dict] = {
    ("냉장고", CAUSE_AGING, 7): {
        "landlord_ratio": 70,
        "tenant_ratio": 30,
        "basis_lh": "빌트인 가전의 노후·자연마모 고장은 임대인 부담 원칙. 사용 7년 경과분 감가 반영.",
        "basis_court": "통상적 사용에 따른 손모는 특약 없는 한 임대인 부담. 임차인 과실분만 일부 분담.",
    },
}

# LLM 호출 불가/실패 시 균등 분담 fallback.
FALLBACK = {
    "landlord_ratio": 50,
    "tenant_ratio": 50,
    "basis_lh": "기준 적용이 곤란해 균등 분담을 임시 적용했습니다(참고용).",
    "basis_court": "",
}


@lru_cache(maxsize=1)
def _client() -> Anthropic:
    """Anthropic 클라이언트 lazy 초기화(db.get_supabase 패턴).

    모듈 import 시점이 아니라 LLM이 실제로 필요할 때 생성한다.
    → 고정 시나리오만 시연할 때는 키 없이도 import·호출이 가능하다.
    """
    if not settings.anthropic_api_key:
        raise RuntimeError(
            "ANTHROPIC_API_KEY 가 없습니다. 고정 시나리오 외 산출은 "
            "backend/.env 에 ANTHROPIC_API_KEY 를 설정하세요."
        )
    return Anthropic(api_key=settings.anthropic_api_key)


def _match_fixed(item: str, cause: str, usage_years: int) -> dict | None:
    """대표 고정 시나리오 매칭(키워드 포함·원인·연수 일치)."""
    for (keyword, fixed_cause, fixed_years), value in FIXED.items():
        if keyword in item and fixed_cause == cause and fixed_years == usage_years:
            return value
    return None


def _call_llm(item: str, cost: int, cause: str, usage_years: int) -> dict:
    """실시간 Claude 호출 → JSON 파싱. 실패 시 RuntimeError 로 위임(상위에서 fallback)."""
    msg = _client().messages.create(
        model=settings.anthropic_model,
        max_tokens=512,
        system=SYSTEM,
        messages=[
            {
                "role": "user",
                "content": (
                    f"항목: {item}\n비용: {cost}원\n발생 원인: {cause}\n"
                    f"사용 연수: 설치 후 {usage_years}년 경과"
                ),
            }
        ],
    )
    return json.loads(msg.content[0].text)


def allocate(item: str, cost: int, cause: str, usage_years: int) -> dict:
    """분담 비율 산출 + 금액 계산.

    1) 대표 고정 시나리오면 LLM 미호출.
    2) 아니면 실시간 LLM 호출(RAG-lite).
    3) 키 미설정·호출 실패·파싱 실패 → 균등 분담 fallback(무음 처리 금지, 경고 로깅).
    반환에 landlord_amount/tenant_amount 를 항상 부착한다.
    """
    fixed = _match_fixed(item, cause, usage_years)
    if fixed is not None:
        result = dict(fixed)
    else:
        try:
            result = _call_llm(item, cost, cause, usage_years)
        except Exception:  # noqa: BLE001 — 어떤 실패든 데모는 fallback으로 살린다(원인은 로깅).
            logger.warning("repair allocation LLM 실패 → fallback 적용", exc_info=True)
            result = dict(FALLBACK)

    # 결정적 금액 계산(원 단위). 임차인은 잔액으로 두어 합이 정확히 cost 가 되게 한다.
    landlord_amount = round(cost * result["landlord_ratio"] / 100)
    result["landlord_amount"] = landlord_amount
    result["tenant_amount"] = cost - landlord_amount
    return result


def save_allocation(
    expense_id: str | None,
    item: str,
    cost: int,
    cause: str,
    usage_years: int,
    result: dict,
) -> None:
    """산출 결과를 repair_allocations 에 저장(best-effort).

    Supabase 미설정·쓰기 실패가 산출 응답을 막지 않도록 예외를 삼키되 경고는 남긴다.
    (CLAUDE.md: 결과는 Supabase 저장. 단 저장 실패로 데모 화면이 깨지면 안 됨.)
    """
    row = {
        "item": item,
        "cost": cost,
        "cause": cause,
        "usage_years": usage_years,
        "landlord_ratio": result["landlord_ratio"],
        "tenant_ratio": result["tenant_ratio"],
        "landlord_amount": result["landlord_amount"],
        "tenant_amount": result["tenant_amount"],
        "basis_lh": result.get("basis_lh"),
        "basis_court": result.get("basis_court"),
    }
    if expense_id:
        row["expense_id"] = expense_id
    try:
        get_supabase().table("repair_allocations").insert(row).execute()
    except Exception:  # noqa: BLE001 — 저장 실패는 응답을 막지 않는다(경고만).
        logger.warning("repair_allocations 저장 실패(응답은 유지)", exc_info=True)
