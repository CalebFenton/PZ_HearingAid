#!/usr/bin/env bash
# Starts the game client in debug mode (no Steam) with its own cache dir and only this mod enabled.
#
#   dev/run-debug-client.sh          play by hand: main menu > Scenarios > Hearing Aid starts a test
#                                    world, and Debug menu > Dev > Unit Tests > Timed Actions runs
#                                    the hearingaid_* tests
#   dev/run-debug-client.sh --test   also loads dev/HearingAidDevHarness, which starts the scenario,
#                                    runs every hearingaid_* test, saves screenshots and quits the
#                                    game. Runs unattended: dev/ClickToStart.java presses "Click to
#                                    start", and the display is kept awake. Prints the results and
#                                    exits 1 if a test failed or the mod logged a Lua error.
#   dev/run-debug-client.sh --art    the same, but instead of the tests the harness saves close-ups
#                                    of the worn and dropped aids (art_*.png) to <cache>/Screenshots
#   dev/run-debug-client.sh --promo  the same, but the harness captures the art for the README and
#                                    the Workshop page, and art/promo/extract.py crops it into
#                                    art/promo/captures (needs uv, https://docs.astral.sh/uv/)
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-client), and JAVAC the compiler
# for ClickToStart.java (default: javac from PATH; any JDK from 8 on works).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

CACHE="${CACHE:-${TMPDIR:-/tmp}/pz-hearingaid-client}"
case "${1:-}" in
    "") MODE= ;;
    --test) MODE=test ;;
    --art) MODE=art ;;
    --promo) MODE=promo ;;
    *) echo "usage: $0 [--test | --art | --promo]" >&2; exit 2 ;;
esac
TIMEOUT=${TIMEOUT:-1200}

link_mod
# Reuse your game settings (resolution, language, accepted terms of service) so a fresh cache
# dir doesn't stop at first-run screens.
if [ ! -f "$CACHE/options.ini" ] && [ -f "$HOME/Zomboid/options.ini" ]; then
    cp "$HOME/Zomboid/options.ini" "$CACHE/options.ini"
fi
# Without this file the client empties mods/default.txt on start, as it does the first time a cache
# dir runs a new major release (ZomboidFileSystem.resetDefaultModsForNewRelease).
echo "If this file does not exist, default.txt will be reset to empty (no mods active)." > "$CACHE/mods/reset-mods-42_00.txt"
MODS="    mod = cf_hearing_aid,"
if [ -n "$MODE" ]; then
    ln -sfn "$REPO/dev/HearingAidDevHarness" "$CACHE/mods/HearingAidDevHarness"
    MODS="$MODS
    mod = cf_hearing_aid_devharness,"
    mkdir -p "$CACHE/Lua"
    echo "$MODE" > "$CACHE/Lua/HearingAidDevHarness.txt"
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
printf 'Version=1\nDebugScenario.ForceLaunch=%s\n' "$([ -n "$MODE" ] && echo true || echo false)" > "$CACHE/debug-options.ini"

GAME=("$JAVA" "${JVM_COMMON[@]}" -XstartOnFirstThread -Xmx3072m -XX:+UseZGC)
GAME_ARGS=(-debug -nosteam -cachedir="$CACHE")
if [ -z "$MODE" ]; then
    cd "$PZ/Java"
    exec "${GAME[@]}" -cp "$GAME_CLASSPATH" zombie.gameStates.MainScreenState "${GAME_ARGS[@]}"
fi

# The game's own Java has no compiler. Target 8 so that any JDK can build a class it can run.
LAUNCHER="$CACHE/launcher"
if [ "$REPO/dev/ClickToStart.java" -nt "$LAUNCHER/ClickToStart.class" ]; then
    mkdir -p "$LAUNCHER"
    "${JAVAC:-javac}" -source 8 -target 8 -Xlint:-options -d "$LAUNCHER" "$REPO/dev/ClickToStart.java"
fi

# GLFW finds no monitor while the display sleeps, and the game can't open its window. caffeinate -u
# wakes the display, and -d -i keep it and the computer awake until this script exits.
caffeinate -d -i -u -w $$ &
for _ in $(seq 10); do
    system_profiler SPDisplaysDataType | grep -q "Display Asleep: Yes" || break
    sleep 1
done

LOG="$CACHE/console.txt"
rm -f "$LOG" "$CACHE"/Screenshots/promo_*.png
cd "$PZ/Java"
"${GAME[@]}" -cp "$LAUNCHER:$GAME_CLASSPATH" ClickToStart "${GAME_ARGS[@]}" > "$CACHE/stdout.txt" 2>&1 &
PID=$!
# Background jobs of a script ignore Ctrl-C, so the game would outlive the script.
trap 'kill "$PID" 2>/dev/null || true' EXIT

for _ in $(seq "$TIMEOUT"); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
    echo "FAIL: no result after ${TIMEOUT}s; stopping the game"
    exit 1
fi

echo "log: $LOG"
case "$MODE" in
    art) MARK=HearingAidArt ;;
    promo) MARK=HearingAidPromo ;;
    *) MARK=HearingAidTest ;;
esac
if ! grep -q "$MARK" "$LOG" 2>/dev/null; then
    echo "FAIL: the game stopped before the harness ran; the end of $CACHE/stdout.txt:"
    tail -n 20 "$CACHE/stdout.txt"
    exit 1
fi
grep "$MARK" "$LOG" || true
if grep -n -E '\(MOD:Hearing Aid' "$LOG"; then
    echo "FAIL: the mod logged Lua errors"
    exit 1
fi
if [ "$MODE" = art ] || [ "$MODE" = promo ]; then
    if ! grep -q "$MARK DONE" "$LOG"; then
        echo "FAIL: the captures didn't finish"
        exit 1
    fi
    if [ "$MODE" = promo ]; then
        "$REPO/art/promo/extract.py" "$CACHE"
    fi
    echo "PASS: captures are in $CACHE/Screenshots"
    exit 0
fi
if ! grep -q -E "HearingAidTest DONE passed=[1-9][0-9]* failed=0$" "$LOG"; then
    echo "FAIL: not every test passed"
    exit 1
fi
echo "PASS: screenshots are in $CACHE/Screenshots"
