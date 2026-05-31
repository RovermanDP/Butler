"""Butler FastAPI 진입점.

책임(CLAUDE.md): AI 수선비 분담(Flow C), 알림톡 로직 mock(Flow D)만 담당.
단순 CRUD·집계는 프론트 → Supabase 직결로 처리하므로 여기 두지 않는다.
Flow C/D 라우터는 해당 세션에서 추가한다.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routers import repair_allocation

app = FastAPI(title="Butler API", version="0.1.0")

# CORS — 설정된 frontend_origin + 로컬 개발의 흔한 변형(localhost/127.0.0.1, 임의 Vite 포트)을 허용한다.
# Vite 가 5173 점유 시 5174 로 뜨거나, 브라우저가 127.0.0.1 로 접속하면 origin 이 달라져
# preflight(OPTIONS) 가 400 으로 막힌다 → 정규식으로 로컬 origin 을 폭넓게 허용해 방지(PoC 개발 편의).
app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.frontend_origin],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_methods=["*"],
    allow_headers=["*"],
)

# Flow C — AI 수선비 분담 (PRD 4.3)
app.include_router(repair_allocation.router)


@app.get("/api/health")
def health() -> dict:
    """기반 세션 검증용 헬스체크. 환경 구성 여부를 함께 보고한다."""
    return {
        "service": "butler-api",
        "status": "ok",
        "supabase_configured": bool(settings.supabase_url and settings.supabase_service_role_key),
        "anthropic_configured": bool(settings.anthropic_api_key),
        "model": settings.anthropic_model,
    }
