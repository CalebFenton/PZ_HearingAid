#!/usr/bin/env bash
# Rebuilds the hearing aid models with Blender (made with 5.2).
#
#   art/models/make.sh            build.py writes hearing_aid.blend and the textures, export.py the
#                                 FBX files, and preview.py renders them on the vanilla heads
#   art/models/make.sh --export   skips build.py, to export hand edits made in hearing_aid.blend
#
# BLENDER overrides the Blender binary, PREVIEWS the preview folder, and PZ_APP the game's
# Contents folder, where preview.py reads the vanilla heads.
set -euo pipefail
cd "$(dirname "$0")"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
case "${1:-}" in
    "") "$BLENDER" -b --factory-startup -P build.py ;;
    --export) ;;
    *) echo "usage: $0 [--export]" >&2; exit 2 ;;
esac
"$BLENDER" -b --factory-startup hearing_aid.blend -P export.py
"$BLENDER" -b --factory-startup hearing_aid.blend -P preview.py
