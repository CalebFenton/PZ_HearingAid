#!/usr/bin/env bash
# Checks the mod against the installed game without launching it, in seconds: compiles every Lua
# file of the mod, its dev mod and the harness mod with the game's own compiler, then cross-checks
# translations (every language the game offers, complete), scripts, textures, sandbox options and
# Lua names (dev/harness/docs/static-check.md lists every check). Needs a JDK's javac (or JAVAC)
# and python3.
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-check).
. "$(dirname "$0")/harness/bin/static-check.sh"
