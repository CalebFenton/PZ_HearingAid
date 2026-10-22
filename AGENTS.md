# Hearing Aid

## Commands

- After every change: `dev/static-check.sh`. It compiles every Lua file with the game's compiler and cross-checks scripts, translations (complete in every language), textures and API names in seconds. Then `dev/validate-server.sh`, which boots a headless dedicated server and fails on any error the mod logs.
- In-game tests cost about 25 seconds a run before any test starts (60 with `--mp`), so batch them: make a batch of changes, committing each logical change on its own, then run `dev/run-debug-client.sh --test --changed` once (or `TESTS=<name prefix>`), adding `--mp` when the batch touches what the server does or sends. Before pushing or merging a batch: `dev/run-debug-client.sh --test` and `dev/run-debug-client.sh --test --mp`. A failed test's `suspects` line names the batch's files that reach it and their commits; rerun that test (`TESTS==<name>`) at those commits to find the one that broke it.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add tests to `dev/HearingAidDevHarness/42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`, with the harness's test library (`PZHarness.Test`). Tests, the debug scenario, and the art, promo, and loot code live in that dev mod, never in `Contents`, which is published. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- Give a new file under `Contents/` or the dev mod a `TEST_MAP` line in `dev/harness.conf` naming the tests that reach its code; without one, `--changed` runs every test.
- Edit `art/models/build.py` and `art/promo/compose.py`, not the models, textures, or images they generate; the next run overwrites hand edits.
- Comments say why, without repeating values from the code. Before editing `DEVELOPMENT.md`, read its opening on what belongs there.
- Don't add `CLAUDE.md` files; the `AGENTS.md` files hold the agent instructions.

## Read when needed

- Before running in-game tests, handing them to subagents, or debugging a failure or a `LEAK`, read `dev/harness/docs/debugging.md`: which run answers which question, and the traps that cost reruns.
- Before changing anything under `dev/harness`, read `dev/harness/AGENTS.md`: other mods share it.
- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo, and loot commands.
- Before changing `README.md`, the Workshop page, read `dev/harness/docs/workshop-page.md`. `workshop.txt`'s description is written from the README by `dev/workshop-txt.sh`; don't edit it by hand.
