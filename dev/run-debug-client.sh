#!/usr/bin/env bash
# Starts the game client in debug mode (no Steam) with its own cache dir and only this mod enabled.
#
#   dev/run-debug-client.sh          play by hand: main menu > Scenarios > Hearing Aid starts a test
#                                    world, and Debug menu > Dev > Unit Tests > Timed Actions runs
#                                    the hearingaid_* tests
#   dev/run-debug-client.sh --test   also loads dev/HearingAidDevHarness, which starts the scenario,
#                                    runs every hearingaid_* test, saves screenshots and quits the
#                                    game. Prints the results and exits 1 if a test failed or the
#                                    mod logged a Lua error.
#
# Someone must click "Click to start" once after the world loads; the game has no way to skip it.
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-client).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

CACHE="${CACHE:-${TMPDIR:-/tmp}/pz-hearingaid-client}"
case "${1:-}" in
    "") TEST=0 ;;
    --test) TEST=1 ;;
    *) echo "usage: $0 [--test]" >&2; exit 2 ;;
esac
TIMEOUT=${TIMEOUT:-1200}

link_mod
# Reuse your game settings (resolution, language, accepted terms of service) so a fresh cache
# dir doesn't stop at first-run screens.
if [ ! -f "$CACHE/options.ini" ] && [ -f "$HOME/Zomboid/options.ini" ]; then
    cp "$HOME/Zomboid/options.ini" "$CACHE/options.ini"
fi
MODS="    mod = cf_hearing_aid,"
if [ "$TEST" = 1 ]; then
    ln -sfn "$REPO/dev/HearingAidDevHarness" "$CACHE/mods/HearingAidDevHarness"
    MODS="$MODS
    mod = cf_hearing_aid_devharness,"
else
    rm -f "$CACHE/mods/HearingAidDevHarness"
fi
cat > "$CACHE/mods/default.txt" <<EOF
VERSION = 1,

mods
{
$MODS
}

maps
{
}
EOF
# The harness scenario sets forceLaunch; this debug option lets it start from the main menu.
printf 'Version=1\nDebugScenario.ForceLaunch=%s\n' "$([ "$TEST" = 1 ] && echo true || echo false)" > "$CACHE/debug-options.ini"

GAME=("$JAVA" "${JVM_COMMON[@]}" -XstartOnFirstThread -Xmx3072m -XX:+UseZGC
    zombie.gameStates.MainScreenState -debug -nosteam -cachedir="$CACHE")
cd "$PZ/Java"
if [ "$TEST" = 0 ]; then
    exec "${GAME[@]}"
fi

LOG="$CACHE/console.txt"
rm -f "$LOG"
"${GAME[@]}" > "$CACHE/stdout.txt" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' INT TERM

prompted=0
for _ in $(seq "$TIMEOUT"); do
    kill -0 "$PID" 2>/dev/null || break
    if [ "$prompted" = 0 ] && grep -q "game loading took" "$LOG" 2>/dev/null; then
        echo "Click \"Click to start\" in the game window."
        prompted=1
    fi
    sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
    echo "FAIL: no result after ${TIMEOUT}s; stopping the game"
    kill "$PID"
    exit 1
fi

echo "log: $LOG"
grep "HearingAidTest" "$LOG" || true
if grep -n -E '\(MOD:Hearing Aid' "$LOG"; then
    echo "FAIL: the mod logged Lua errors"
    exit 1
fi
if ! grep -q -E "HearingAidTest DONE passed=[1-9][0-9]* failed=0$" "$LOG"; then
    echo "FAIL: not every test passed"
    exit 1
fi
echo "PASS: screenshots are in $CACHE/Screenshots"
