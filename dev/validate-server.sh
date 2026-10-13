#!/usr/bin/env bash
# Boots a throwaway dedicated server (no Steam, isolated cache dir) with only this mod enabled,
# waits for it to finish loading, stops it, and fails if the mod logged a problem. The server
# loads registries, scripts, sandbox options, shared and server Lua, and the loot tables, with the
# log patterns of dev/harness.conf.
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-server), and TIMEOUT the seconds
# the server may take to start (default 900).
. "$(dirname "$0")/harness/bin/validate-server.sh"
