# Hearing Aid

## Commands

- After every change: `dev/validate-server.sh`. It boots a headless dedicated server and fails on any error the mod logs.
- Before finishing: `dev/run-debug-client.sh --test`. It runs every in-game test unattended and needs a JDK's `javac` on `PATH` (or `JAVAC` set). While you iterate, `TESTS=<name prefix> dev/run-debug-client.sh --test --stay` runs only those tests and keeps the game open, so the next such run reruns them in a second or two; finish with a plain `--test`.
- Multiplayer: `dev/run-debug-client.sh --test --mp` runs the same tests with a dedicated server and a client that joins it; add `--stay` while you iterate, so the next such run reruns them in about a second. What only the server can do goes through `PZHarness.Test.server` and handlers in the dev mod's server Lua; `dev/harness/docs/multiplayer.md` explains it.
- The scripts run on the shared test harness in the `dev/harness` submodule (`git submodule update --init` in a fresh clone), whose README describes it. It's shared with other mods: change it only in ways that fit any mod, and expect a run to wait while another mod's dev script has a game up; just run them.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add tests to `dev/HearingAidDevHarness/42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`, with the harness's test library (`PZHarness.Test`). Tests, the debug scenario, and the art, promo, and loot code live in that dev mod, never in `Contents`, which is published. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- Edit `art/models/build.py` and `art/promo/compose.py`, not the models, textures, or images they generate; the next run overwrites hand edits.
- Comments say why, without repeating values from the code. Before editing `DEVELOPMENT.md`, read its opening on what belongs there.
- Don't add `CLAUDE.md`; this is the only agent instruction file.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo, and loot commands.
