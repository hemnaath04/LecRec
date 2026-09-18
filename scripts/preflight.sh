#!/bin/bash
# Checks every external dependency LecRec shells out to.
cd "$(dirname "$0")/.."
status=0

check() {
  local name="$1" hint="$2" path
  path="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$path" ]; then
    printf '  ok       %-14s %s\n' "$name" "$path"
  else
    printf '  MISSING  %-14s install: %s\n' "$name" "$hint"
    status=1
  fi
}

echo "Dependencies"
check ffmpeg       "brew install ffmpeg"
check ffprobe      "brew install ffmpeg"
check parakeet-mlx "uv tool install parakeet-mlx -U"
check claude       "install Claude Code"
check pdftotext    "brew install poppler"
check pdftoppm     "brew install poppler"

echo
echo "Audio inputs"
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
  | awk '/AVFoundation audio devices/,0' | grep -oE '\[[0-9]+\] .*' | sed 's/^/  /' || true

echo
echo "MCP servers configured in Claude Code"
python3 - <<'PY'
import json, os
try:
    d = json.load(open(os.path.expanduser("~/.claude.json")))
except Exception as e:
    print(f"  could not read ~/.claude.json: {e}"); raise SystemExit
names = set(d.get("mcpServers") or {})
for v in (d.get("projects") or {}).values():
    if isinstance(v, dict):
        names |= set(v.get("mcpServers") or {})
for want in ("notion",):
    print(f"  {'ok      ' if want in names else 'MISSING '} mcp: {want}")
PY

echo
echo "Notes root"
root="$HOME/Documents/course-notes"
[ -d "$root" ] && echo "  ok       $root" || echo "  note     $root does not exist yet, it will be created"

exit $status
