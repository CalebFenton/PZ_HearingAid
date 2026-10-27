#!/usr/bin/env bash
# Starts the game client with this mod, its dev mod and the harness mod; dev/harness/docs/running.md
# lists the flags and environment variables. Its scenario, under the main menu's Scenarios: Hearing
# Aid, a test world. Its modes, --art, --promo and --loot, are described at MODES in harness.conf.
# Tests are named hearingaid_*.
. "$(dirname "$0")/harness/bin/run-client.sh"
