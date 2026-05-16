#!/usr/bin/env bash
# 把 mcpo 註冊成 admin 的 Tool Server,讓 chat 裡可以勾選。
set -euo pipefail
source "$(dirname "$0")/../config.env"

if [[ "${MCPO_ENABLED:-false}" != "true" ]]; then
  echo "  MCPO_ENABLED=false — skip"
  exit 0
fi

IP_NOW="$(hostname -I | awk '{print $1}')"
TOOL_URL="http://${IP_NOW}:${MCPO_PORT}/${UPSTREAM_MCP_NAME}"

docker exec -i \
  -e TOOL_URL="$TOOL_URL" \
  -e TOOL_NAME="$UPSTREAM_MCP_NAME" \
  -e MCPO_API_KEY="$MCPO_API_KEY" \
  open-webui python3 <<'PYEOF'
import json, os, sqlite3

DB = '/app/backend/data/webui.db'
db = sqlite3.connect(DB)
row = db.execute("SELECT id, settings FROM user WHERE role='admin' LIMIT 1").fetchone()
if not row:
    print('  no admin user yet — register first, then re-run with --skip-network --skip-docker --skip-openwebui --skip-llm')
    raise SystemExit(0)

uid, raw = row
settings = json.loads(raw) if raw else {}
ui = settings.setdefault('ui', {})
servers = ui.setdefault('toolServers', [])

new_entry = {
    'type': 'openapi',
    'url': os.environ['TOOL_URL'],
    'spec_type': 'url',
    'spec': '',
    'path': 'openapi.json',
    'auth_type': 'bearer',
    'key': os.environ['MCPO_API_KEY'],
    'config': {'enable': True, 'function_name_filter_list': '', 'access_grants': []},
    'info': {'id': '', 'name': os.environ['TOOL_NAME'], 'description': ''},
}
# 同 URL 已存在就取代
servers = [s for s in servers if s.get('url') != new_entry['url']]
servers.append(new_entry)
ui['toolServers'] = servers
db.execute('UPDATE user SET settings=? WHERE id=?', (json.dumps(settings), uid))
db.commit()
print(f"  + registered tool server: {new_entry['url']}")
PYEOF
