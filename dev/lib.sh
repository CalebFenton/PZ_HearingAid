# Sourced by the dev scripts. PZ_APP overrides the game's Contents folder, and CACHE the cache dir
# that the calling script defaults to.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PZ="${PZ_APP:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents}"
JAVA="$PZ/PlugIns/jre-$(uname -m | sed 's/arm64/aarch64/')/Contents/Home/bin/java"

# JVM arguments shared by the client and the dedicated server. Both run from "$PZ/Java", which
# GAME_CLASSPATH is relative to.
JVM_COMMON=(-Djava.awt.headless=true -Djava.library.path=. --enable-native-access=ALL-UNNAMED
    --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED -Dzomboid.steam=0 -Dzomboid.znetlog=1
    -XX:-OmitStackTraceInFastThrow)
GAME_CLASSPATH=.:projectzomboid.jar

link_mod() {
    mkdir -p "$CACHE/mods"
    ln -sfn "$REPO/Contents/mods/HearingAid" "$CACHE/mods/HearingAid"
}
