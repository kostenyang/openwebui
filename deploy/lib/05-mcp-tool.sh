#!/usr/bin/env bash
# 註冊 Open WebUI 的 Tool Server。兩種來源:
#   1. 本機 mcpo 包出的 path  (MCPO_ENABLED=true)  e.g. http://<本機>:8000/<name>
#   2. 別台機器自帶 mcpo 的成品 OpenAPI (EXTRA_TOOL_SERVERS)
#
# 兩種都會被寫進 admin user 的 settings.ui.toolServers,Open WebUI 重新整理後生效。
# 同 URL 再跑會「取代」不會「重複」。
set -euo pipefail
source "$(dirname "$0")/../config.env"

IP_NOW="$(hostname -I | awk '{print $1}')"

# 把一條 (name, url, bearer) upsert 進 admin 的 toolServers。
register_tool() {
  local name="$1"
  local url="$2"
  local key="$3"

  if [[ -z "$name" || -z "$url" || -z "$key" ]]; then
    echo "  ✗ skip: missing name/url/key (got name='$name' url='$url' key=$([[ -z "$key" ]] && echo MISSING || echo set))"
    return 0
  fi

  docker exec -i \
    -e TOOL_URL="$url" \
    -e TOOL_NAME="$name" \
    -e MCPO_API_KEY="$key" \
    open-webui python3 <<'PYEOF'
import json, os, sqlite3, sys

DB = '/app/backend/data/webui.db'
db = sqlite3.connect(DB)
row = db.execute("SELECT id, settings FROM user WHERE role='admin' LIMIT 1").fetchone()
if not row:
    print('    no admin user yet — register one in Open WebUI first, then re-run with --skip-network --skip-docker --skip-openwebui --skip-llm', file=sys.stderr)
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
existed = any(s.get('url') == new_entry['url'] for s in servers)
servers = [s for s in servers if s.get('url') != new_entry['url']]
servers.append(new_entry)
ui['toolServers'] = servers
db.execute('UPDATE user SET settings=? WHERE id=?', (json.dumps(settings), uid))
db.commit()
verb = 'replaced' if existed else 'added'
print(f"    {verb}: {new_entry['info']['name']} -> {new_entry['url']}")
PYEOF
}

# ─── [1] 本機 mcpo(MCPO_ENABLED=true 才註冊) ─────────────────────────
if [[ "${MCPO_ENABLED:-false}" == "true" ]]; then
  LOCAL_URL="http://${IP_NOW}:${MCPO_PORT}/${UPSTREAM_MCP_NAME}"
  echo "  → register local mcpo:"
  register_tool "$UPSTREAM_MCP_NAME" "$LOCAL_URL" "$MCPO_API_KEY"
else
  echo "  MCPO_ENABLED=false — skip local mcpo registration"
fi

# ─── [2] 額外的「成品 OpenAPI」tool server ───────────────────────────
if [[ -v EXTRA_TOOL_SERVERS && ${#EXTRA_TOOL_SERVERS[@]} -gt 0 ]]; then
  echo "  → register ${#EXTRA_TOOL_SERVERS[@]} extra tool server(s):"
  for entry in "${EXTRA_TOOL_SERVERS[@]}"; do
    # split "name|url|key"
    IFS='|' read -r t_name t_url t_key <<<"$entry"
    register_tool "$t_name" "$t_url" "$t_key"
  done
else
  echo "  (no EXTRA_TOOL_SERVERS configured)"
fi
