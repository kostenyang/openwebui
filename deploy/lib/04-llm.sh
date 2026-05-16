#!/usr/bin/env bash
# 把 OpenAI / Gemini / Anthropic 設定直接灌進 Open WebUI 的 SQLite。
# 比走 UI 快,而且 idempotent。
set -euo pipefail
source "$(dirname "$0")/../config.env"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# 先檢查至少一家有 key
if [[ -z "${OPENAI_API_KEY:-}" && -z "${GEMINI_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "  no LLM key in config.env — skip"
  exit 0
fi

# 把 anthropic_pipe.py 複製進容器(若需要)
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  if [[ ! -f "$HERE/../functions/anthropic_pipe.py" ]]; then
    echo "ERROR: $HERE/../functions/anthropic_pipe.py missing"
    exit 1
  fi
  docker cp "$HERE/../functions/anthropic_pipe.py" open-webui:/tmp/anthropic_pipe.py
fi

# 一次性 python script 在容器內跑
docker exec -i \
  -e OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  -e OPENAI_API_BASE="${OPENAI_API_BASE:-https://api.openai.com/v1}" \
  -e GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  open-webui python3 <<'PYEOF'
import datetime, json, os, sqlite3, time

DB = '/app/backend/data/webui.db'
db = sqlite3.connect(DB)
now_iso = datetime.datetime.utcnow().isoformat()

# ── helper: get admin user id ─────────────────────────────────────────
row = db.execute("SELECT id FROM user WHERE role='admin' LIMIT 1").fetchone()
admin_id = row[0] if row else None

# ── OpenAI + Gemini → config.openai.{api_keys, api_base_urls, api_configs}
row = db.execute('SELECT data FROM config WHERE id=1').fetchone()
cfg = json.loads(row[0]) if row and row[0] else {'version': 0, 'ui': {}}
cfg.setdefault('ui', {})

urls, keys, configs = [], [], {}
def add(url, key, prefix):
    idx = str(len(urls))
    urls.append(url); keys.append(key)
    configs[idx] = {
        'enable': True, 'tags': [], 'prefix_id': prefix,
        'model_ids': [], 'connection_type': 'external',
    }

if os.environ.get('OPENAI_API_KEY'):
    add(os.environ['OPENAI_API_BASE'], os.environ['OPENAI_API_KEY'], 'openai')
    print('  + OpenAI')
if os.environ.get('GEMINI_API_KEY'):
    add('https://generativelanguage.googleapis.com/v1beta/openai',
        os.environ['GEMINI_API_KEY'], 'gemini')
    print('  + Gemini')

if urls:
    cfg['openai'] = {
        'enable': True,
        'api_keys': keys,
        'api_base_urls': urls,
        'api_configs': configs,
    }
    db.execute('UPDATE config SET data=?, updated_at=? WHERE id=1',
               (json.dumps(cfg), now_iso))
    db.commit()

# ── Anthropic → function table
if os.environ.get('ANTHROPIC_API_KEY') and admin_id:
    content = open('/tmp/anthropic_pipe.py', encoding='utf-8').read()
    valves = json.dumps({
        'ANTHROPIC_API_KEY': os.environ['ANTHROPIC_API_KEY'],
        'ANTHROPIC_API_BASE': 'https://api.anthropic.com/v1',
        'MAX_TOKENS': 8192,
    })
    meta = json.dumps({'description': 'Anthropic Claude provider', 'manifest': {}})
    now = int(time.time())
    db.execute('DELETE FROM function WHERE id=?', ('anthropic',))
    db.execute(
        'INSERT INTO function (id, user_id, name, type, content, meta, '
        'created_at, updated_at, valves, is_active, is_global) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
        ('anthropic', admin_id, 'Anthropic', 'pipe', content, meta,
         now, now, valves, 1, 1)
    )
    db.commit()
    print('  + Anthropic (Function)')

db.close()
PYEOF

# 改了 DB 要重啟才會載入
echo "  restarting open-webui..."
docker restart open-webui >/dev/null
for i in $(seq 1 45); do
  s=$(docker inspect -f '{{.State.Health.Status}}' open-webui 2>/dev/null || echo none)
  [[ "$s" == "healthy" ]] && break
  sleep 2
done
echo "  ✓ done"
