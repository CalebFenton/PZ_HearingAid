#!/usr/bin/env bash
# Launches the game client in debug mode (no Steam) with an isolated cache dir that has only
# this mod enabled. Uses the vanilla debug tooling:
#   - main menu SCENARIOS panel -> "Hearing Aid" (zombie-free test world, all items)
#   - in game: bug icon (left sidebar) -> Dev -> Unit Tests -> Timed Actions -> hearingaid_*
#
#   dev/run-debug-client.sh            interactive: pick the scenario yourself
#   dev/run-debug-client.sh --auto     also loads dev/HearingAidDevHarness, which launches the
#                                      scenario, runs every hearingaid_* test and prints
#                                      "HearingAidTest ..." lines to <cache>/console.txt
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-client).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PZ="${PZ_APP:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents}"
JAVA="$PZ/PlugIns/jre-$(uname -m | sed 's/arm64/aarch64/')/Contents/Home/bin/java"
CACHE="${CACHE:-${TMPDIR:-/tmp}/pz-hearingaid-client}"
AUTO=0
[ "${1:-}" = "--auto" ] && AUTO=1
mkdir -p "$CACHE/mods"
# Reuse your game settings (resolution, language, accepted terms of service) so a fresh
# cache dir doesn't stop at first-run screens.
if [ ! -f "$CACHE/options.ini" ] && [ -f "$HOME/Zomboid/options.ini" ]; then
    cp "$HOME/Zomboid/options.ini" "$CACHE/options.ini"
fi
ln -sfn "$REPO/Contents/mods/HearingAid" "$CACHE/mods/HearingAid"
MODS="    mod = cf_hearing_aid,"
if [ "$AUTO" = 1 ]; then
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
# The harness scenario sets forceLaunch; this debug option lets it fire from the main menu.
printf 'Version=1\nDebugScenario.ForceLaunch=%s\n' "$([ "$AUTO" = 1 ] && echo true || echo false)" > "$CACHE/debug-options.ini"

cd "$PZ/Java"
exec "$JAVA" -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
    --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED -XstartOnFirstThread \
    -Dzomboid.steam=0 -Dzomboid.znetlog=1 -Xmx3072m -XX:+UseZGC -XX:-OmitStackTraceInFastThrow \
    -Djava.library.path=. -cp .:projectzomboid.jar zombie.gameStates.MainScreenState \
    -debug -nosteam -cachedir="$CACHE"
