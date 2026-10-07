# Hearing Aid

## Commands

- Headless check: `dev/validate-server.sh`. It boots a dedicated server with only this mod and fails if the mod logged a Lua error, a script warning, or a missing loot table.
- In-game tests: `dev/run-debug-client.sh --test`. It runs unattended in about 2 minutes: it presses **Click to start** itself, wakes the display, waits for the results, quits the game, and exits nonzero on a failed test or a Lua error. It needs a JDK's `javac` on `PATH` (or `JAVAC` set) to build `dev/ClickToStart.java`.

## Rules

- Check Build 42 APIs against the installed game, not web docs or memory: the vanilla Lua and scripts in `Project Zomboid.app/Contents/Java/media`, and the decompiled `projectzomboid.jar`. Most published modding docs describe Build 41, and B42 changes many of those APIs.
- Don't edit `Contents/mods/HearingAid/mod.info` or anything under `Contents/mods/HearingAid/media/`. Those files are the published Build 41 release; the Build 42 mod is `Contents/mods/HearingAid/42/` plus `common/`.
- Add tests to `42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`, which the game's own test runner executes. Don't add standalone Lua tests with stubbed game APIs: the stubs encode guesses about the game, which is what the tests need to check.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot tables, or tests, read `DEVELOPMENT.md`. It records Build 42 behavior that fails silently or contradicts Build 41, with the source that proves each fact and the command to decompile the game.
