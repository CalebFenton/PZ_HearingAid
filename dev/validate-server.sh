#!/usr/bin/env bash
# Boots a throwaway dedicated server (no Steam, isolated cache dir) with only this mod enabled,
# waits for it to finish loading, stops it, and fails if the mod logged a problem. The server
# loads registries, scripts, sandbox options, shared and server Lua, and the loot tables.
#
# Usage: dev/validate-server.sh [cache dir]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PZ="${PZ_APP:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents}"
JAVA="$PZ/PlugIns/jre-$(uname -m | sed 's/arm64/aarch64/')/Contents/Home/bin/java"
CACHE="${1:-${TMPDIR:-/tmp}/pz-hearingaid-server}"
NAME=hearingaid
TIMEOUT=${TIMEOUT:-900}

mkdir -p "$CACHE/mods" "$CACHE/Server"
ln -sfn "$REPO/Contents/mods/HearingAid" "$CACHE/mods/HearingAid"
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
"$JAVA" -Djava.awt.headless=true -Djava.library.path=. \
    --enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED \
    -Dzomboid.steam=0 -Dzomboid.znetlog=1 -Ddebug -Xmx4g -XX:-OmitStackTraceInFastThrow \
    -cp .:projectzomboid.jar zombie.network.GameServer \
    -cachedir="$CACHE" -servername "$NAME" -adminpassword admin -nosteam -debuglog=Mod,Lua \
    < "$FIFO" > "$CACHE/stdout.txt" 2>&1 &
SERVER=$!
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
    kill "$SERVER" 2>/dev/null || true
fi
exec 3>&-
rm -f "$FIFO"

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
