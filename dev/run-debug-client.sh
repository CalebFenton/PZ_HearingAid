#!/usr/bin/env bash
# Starts the game client in debug mode (no Steam) with its own cache dir, this mod, its dev mod
# dev/HearingAidDevHarness and the shared harness mod (dev/harness, see its README.md).
#
#   dev/run-debug-client.sh          play by hand: main menu > Scenarios > Hearing Aid starts a
#                                    test world, and Debug menu > Dev > Unit Tests > Timed Actions
#                                    runs the hearingaid_* tests
#   dev/run-debug-client.sh --test   starts the scenario, runs every hearingaid_* test and quits
#                                    the game. Runs unattended: ClickToStart presses "Click to
#                                    start", and the display is kept awake. Prints the results and
#                                    exits 1 if a test failed or any Lua error was logged.
#   dev/run-debug-client.sh --test --stay
#                                    the same, but the game stays open after the run, and the next
#                                    --test --stay reruns the tests in it, after reloading
#                                    HearingAidTests.lua, instead of starting the game again. Any
#                                    other change to the mods restarts the game. While it waits it
#                                    shows and logs "HearingAidTest IDLE"; it quits after 10
#                                    minutes without a run, or when another run needs the game.
#   dev/run-debug-client.sh --art    the same, but instead of the tests the harness saves close-ups
#                                    of the worn and dropped aids (art_*.png) to <cache>/Screenshots
#   dev/run-debug-client.sh --promo  the same, but the harness captures the art for the README and
#                                    the Workshop page, and art/promo/extract.py crops it into
#                                    art/promo/captures (needs uv, https://docs.astral.sh/uv/)
#   dev/run-debug-client.sh --loot   the same, but the harness measures how often corpses and
#                                    containers hold hearing aids and wristwatches, and the script
#                                    prints the shares
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-hearingaid-client), JAVAC the compiler for
# ClickToStart.java (default: javac from PATH; any JDK from 8 on works), TIMEOUT the seconds a
# harness run may take (default 1200), and TESTS, a comma-separated list of test name prefixes,
# limits --test to those tests (e.g. TESTS=hearingaid_craft_).
. "$(dirname "$0")/harness/bin/run-client.sh"
