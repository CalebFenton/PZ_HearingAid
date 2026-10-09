# Hearing Aid

## Commands

- `dev/validate-server.sh`: headless check. Run it after every change.
- `dev/run-debug-client.sh --test`: every in-game test, unattended. It needs a JDK's `javac` on `PATH` (or `JAVAC` set).
- Art, promo images, loot measurement, and debugging by hand: the commands in `DEVELOPMENT.md`.

## Rules

- Check Build 42 APIs against the installed game, not web docs or memory: the vanilla Lua and scripts in `Project Zomboid.app/Contents/Java/media`, and the decompiled `projectzomboid.jar`. Most published modding docs describe Build 41, and B42 changes many of those APIs.
- Don't edit `Contents/mods/HearingAid/mod.info` or anything under `Contents/mods/HearingAid/media/`. Those files are the published Build 41 release; the Build 42 mod is `Contents/mods/HearingAid/42/` plus `common/`.
- Add tests to `42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`, which the game's own test runner executes. Don't add standalone Lua tests with stubbed game APIs: the stubs encode guesses about the game, which is what the tests need to check.
- Change the models and their textures in `art/models/build.py`, then run `art/models/make.sh`. Don't edit the FBX files or the `textures/clothes` PNGs directly; the scripts overwrite them.
- Change the README and Workshop images in `art/promo/compose.py` and what the game captures in `dev/HearingAidDevHarness/42/media/lua/client/HearingAidDevPromo.lua`. Don't edit `art/promo/images` or `art/promo/captures` by hand; the scripts overwrite them.
- Code says what it does; a comment beside it says why, without repeating the values in the code. `DEVELOPMENT.md` holds commands, debugging tips, and game behavior the code can't show. Don't describe the mod's code there or copy numbers from it.
- The README and Workshop page say where to find hearing aids, not how often. `--loot` measures the rates.
- Agent instructions live in this file only. Don't add `CLAUDE.md` or other per-agent files.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md`. It records Build 42 behavior that fails silently or contradicts Build 41, with the source that proves each fact and the command to decompile the game.
