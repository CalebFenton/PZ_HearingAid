#!/usr/bin/env bash
# Boots a throwaway dedicated server (no Steam, isolated cache dir) with only this mod enabled,
# waits for it to finish loading, stops it, and fails if the mod logged a problem. The server
# loads registries, scripts, sandbox options, shared and server Lua, and the loot tables.
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-server).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

CACHE="${CACHE:-${TMPDIR:-/tmp}/pz-hearingaid-server}"
NAME=hearingaid
TIMEOUT=${TIMEOUT:-900}

link_mod
mkdir -p "$CACHE/Server"
cat > "$CACHE/Server/$NAME.ini" <<EOF
Mods=cf_hearing_aid
Map=Muldraugh, KY
UPnP=false
Public=false
EOF

LOG="$CACHE/server-console.txt"
rm -f "$LOG"
FIFO="$CACHE/stdin"
rm -f "$FIFO"
mkfifo "$FIFO"

cd "$PZ/Java"
"$JAVA" "${JVM_COMMON[@]}" -Ddebug -Xmx4g zombie.network.GameServer \
    -cachedir="$CACHE" -servername "$NAME" -adminpassword admin -nosteam -debuglog=Mod,Lua \
    < "$FIFO" > "$CACHE/stdout.txt" 2>&1 &
SERVER=$!
# Background jobs of a script ignore Ctrl-C, so the server would outlive the script.
trap 'kill "$SERVER" 2>/dev/null || true; rm -f "$FIFO"' EXIT
exec 3>"$FIFO"

started=0
for _ in $(seq "$TIMEOUT"); do
    if grep -q "SERVER STARTED" "$LOG" 2>/dev/null; then started=1; break; fi
    if ! kill -0 "$SERVER" 2>/dev/null; then break; fi
    sleep 1
done
if kill -0 "$SERVER" 2>/dev/null; then
    echo quit >&3
    for _ in $(seq 120); do kill -0 "$SERVER" 2>/dev/null || break; sleep 1; done
fi
exec 3>&-

echo "log: $LOG"
if [ "$started" != 1 ]; then
    echo "FAIL: server did not start"
    exit 1
fi
# Lua errors carry "(MOD:Hearing Aid)" in their stack trace, script warnings name the item or
# recipe, and HearingAidDistributions.lua prints "HearingAid: missing" for unknown loot tables.
if grep -n -E '\(MOD:Hearing Aid\)|HearingAid: missing|^(WARN|ERROR).*[Hh]earing ?[Aa]id' "$LOG"; then
    echo "FAIL: the mod logged problems"
    exit 1
fi
echo "PASS: server started and the mod logged no problems"
