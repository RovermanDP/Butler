"""환경설정 단일 진실 공급원(OSoT). backend/.env 에서 로드."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Supabase — 서버측은 service_role 키 사용 (RLS 우회 / 집계·쓰기)
    supabase_url: str = ""
    supabase_service_role_key: str = ""

    # Anthropic — Flow C(AI 수선비 분담)에서 사용. Console 발급 키.
    # ⚠ 빌드용 셸과 분리할 것 (CLAUDE.md): 키가 있으면 Claude Code 호출이 과금될 수 있음.
    anthropic_api_key: str = ""
    anthropic_model: str = "claude-haiku-4-5-20251001"

    # CORS — Vite 개발 서버
    frontend_origin: str = "http://localhost:5173"


settings = Settings()
