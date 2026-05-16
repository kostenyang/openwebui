import sqlite3, json, time, sys
user_id = 'bce9fe05-8e16-4044-8787-ae1f58676701'
api_key = sys.argv[1]
content = open('/tmp/anthropic_pipe.py', encoding='utf-8').read()
valves = json.dumps({
    'ANTHROPIC_API_KEY': api_key,
    'ANTHROPIC_API_BASE': 'https://api.anthropic.com/v1',
    'MAX_TOKENS': 8192,
})
meta = json.dumps({'description': 'Anthropic Claude provider (Opus/Sonnet/Haiku 4.x)', 'manifest': {}})
now = int(time.time())
db = sqlite3.connect('/app/backend/data/webui.db')
db.execute('DELETE FROM function WHERE id=?', ('anthropic',))
db.execute('INSERT INTO function (id, user_id, name, type, content, meta, created_at, updated_at, valves, is_active, is_global) VALUES (?,?,?,?,?,?,?,?,?,?,?)', ('anthropic', user_id, 'Anthropic', 'pipe', content, meta, now, now, valves, 1, 1))
db.commit()
print('inserted, rows:', db.execute('SELECT COUNT(*) FROM function').fetchone()[0])
