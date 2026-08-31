#!/bin/bash
# assemble vless-server.sh v3.5.14 (LF) from GitHub parts
set -eu
BASE="https://raw.githubusercontent.com/Jyanbai/vless-all-in-one/main/release-assets/v3.5.14"
OUT="${1:-vless-server.sh}"
EXPECT_SHA="da903f678df4975645d3505ec53d08c32304b0cc54828ff421bb2d9fd70739a1"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
parts=$(curl -fsSL "$BASE/parts.list")
: > "$TMP"
for p in $parts; do
  curl -fsSL "$BASE/$p" >> "$TMP"
done
# strip CR if any
tr -d '\r' < "$TMP" > "$OUT"
chmod +x "$OUT"
got=$(sha256sum "$OUT" | awk '{print $1}')
if [ "$got" != "$EXPECT_SHA" ]; then
  echo "sha256 mismatch: $got" >&2
  exit 1
fi
bash -n "$OUT"
echo "OK $OUT  $(wc -c < "$OUT") bytes  $got"
