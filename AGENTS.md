# Hearing Aid

## Commands

- Headless check: `dev/validate-server.sh`. It boots a dedicated server with only this mod and fails if the mod logged a Lua error, a script warning, or a missing loot table.
- In-game tests: `dev/run-debug-client.sh --test`. It runs unattended in about 2 minutes: it presses **Click to start** itself, wakes the display, waits for the results, quits the game, and exits nonzero on a failed test or a Lua error. It needs a JDK's `javac` on `PATH` (or `JAVAC` set) to build `dev/ClickToStart.java`.
- Art: `art/models/make.sh` rebuilds the 3D models and their textures with Blender, and `dev/run-debug-client.sh --art` saves in-game close-ups of them to `<cache>/Screenshots`.
- README and Workshop images: `dev/run-debug-client.sh --promo` captures art and loot numbers from the game into `art/promo/captures`, and `art/promo/compose.py` lays them out into `art/promo/images` and prints the loot tables for `README.md` and `workshop.txt`.

## Rules

- Check Build 42 APIs against the installed game, not web docs or memory: the vanilla Lua and scripts in `Project Zomboid.app/Contents/Java/media`, and the decompiled `projectzomboid.jar`. Most published modding docs describe Build 41, and B42 changes many of those APIs.
- Don't edit `Contents/mods/HearingAid/mod.info` or anything under `Contents/mods/HearingAid/media/`. Those files are the published Build 41 release; the Build 42 mod is `Contents/mods/HearingAid/42/` plus `common/`.
- Add tests to `42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`, which the game's own test runner executes. Don't add standalone Lua tests with stubbed game APIs: the stubs encode guesses about the game, which is what the tests need to check.
- Change the models and their textures in `art/models/build.py`, then run `art/models/make.sh`. Don't edit the FBX files or the `textures/clothes` PNGs directly; the scripts overwrite them.
- Change the README and Workshop images in `art/promo/compose.py` and what the game captures in `dev/HearingAidDevHarness/42/media/lua/client/HearingAidDevPromo.lua`. Don't edit `art/promo/images` or `art/promo/captures` by hand; the scripts overwrite them.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot tables, tests, or art, read `DEVELOPMENT.md`. It records Build 42 behavior that fails silently or contradicts Build 41, with the source that proves each fact and the command to decompile the game.
