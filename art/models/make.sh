#!/usr/bin/env bash
# Rebuilds the hearing aid models with Blender (made with 5.2), exporting them with the harness's
# art library (dev/harness/docs/art.md).
#
#   art/models/make.sh            build.py writes hearing_aid.blend and the textures, export.py the
#                                 FBX files, and preview.py renders them on the vanilla heads
#   art/models/make.sh --export   skips build.py, to export hand edits made in hearing_aid.blend
#
# BLENDER overrides the Blender binary, PREVIEWS the preview folder, and PZ_APP the game's
# Contents folder, where preview.py reads the vanilla heads.
set -euo pipefail
cd "$(dirname "$0")"
. ../../dev/harness/lib/blender.sh
case "${1:-}" in
    "") blender build.py ;;
    --export) ;;
    *) echo "usage: $0 [--export]" >&2; exit 2 ;;
esac
blender hearing_aid.blend export.py
blender hearing_aid.blend preview.py
