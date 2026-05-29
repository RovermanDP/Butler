"""Supabase service-role 클라이언트 (서버측 전용).

CRUD·집계는 프론트가 Supabase 직결로 처리한다(CLAUDE.md 책임 분담).
백엔드는 AI 분담 결과 저장·알림톡 mock 기록 등 '진짜 로직'에서만 이 클라이언트를 쓴다.
키 미설정 시 import 시점이 아니라 사용 시점에 명확히 실패하도록 lazy 초기화한다.
"""
from functools import lru_cache

from supabase import Client, create_client

from .config import settings


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise RuntimeError(
            "Supabase 환경변수가 없습니다. backend/.env 에 "
            "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 를 설정하세요."
        )
    return create_client(settings.supabase_url, settings.supabase_service_role_key)
