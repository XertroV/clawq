#!/bin/bash
# Generate chat_ui_assets.ml from static/ files
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIC_DIR="$REPO_ROOT/static"
OUTPUT="$REPO_ROOT/src/chat_ui_assets.ml"

embed_file() {
  local name="$1"
  local path="$2"
  printf 'let %s =\n  {|' "$name"
  cat "$path"
  printf '|}\n\n'
}

if [ ! -f "$STATIC_DIR/index.html" ]; then
  echo "No static/ files found, skipping (using existing chat_ui_assets.ml)"
  exit 0
fi

echo "Generating $OUTPUT from $STATIC_DIR..."

{
  echo "(* Auto-generated chat UI assets - embedded static files *)"
  echo ""
  embed_file "index_html" "$STATIC_DIR/index.html"
  embed_file "chat_css" "$STATIC_DIR/chat.css"
  embed_file "chat_js" "$STATIC_DIR/chat.js"
} > "$OUTPUT"

echo "Generated $OUTPUT"
