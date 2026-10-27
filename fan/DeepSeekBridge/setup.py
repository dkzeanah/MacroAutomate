"""Create secure local configuration without overwriting existing credentials."""
from pathlib import Path
import secrets
ROOT = Path(__file__).resolve().parent
ENV = ROOT / '.env'
if not ENV.exists():
    token = secrets.token_urlsafe(32)
    ENV.write_text(f'BRIDGE_TOKEN={token}\nBRIDGE_PORT=8765\nDEEPSEEK_API_KEY=\nDEEPSEEK_MODEL=deepseek-v4-pro\nDEEPSEEK_VISION_MODEL=deepseek-flash\nDEEPSEEK_BASE_URL=https://api.deepseek.com\nTOOL_TIMEOUT=30\nALLOW_AGENT_SCRIPTS=1\nAUTOHOTKEY_EXE=\n', encoding='utf-8')
    print('Created .env. Insert DEEPSEEK_API_KEY before using the Python agent.')
else:
    print('.env exists; left unchanged.')
