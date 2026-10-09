# Hearing Aid

## Commands

- After every change: `dev/validate-server.sh`. It boots a headless dedicated server and fails on any error the mod logs.
- Before finishing: `dev/run-debug-client.sh --test`. It runs every in-game test unattended and needs a JDK's `javac` on `PATH` (or `JAVAC` set).

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add tests to `HearingAidTests.lua`, which the game's own test runner executes. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- Edit `art/models/build.py` and `art/promo/compose.py`, not the models, textures, or images they generate; the next run overwrites hand edits.
- Comments say why, without repeating values from the code. `DEVELOPMENT.md` holds commands, tips, and game behavior; don't describe the mod's code there.
- Don't add `CLAUDE.md`; this is the only agent instruction file.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo, and loot commands.
