# Hearing Aid

## Commands

- After every change: `dev/static-check.sh`, which compiles every Lua file with the game's compiler and cross-checks scripts, translations (complete in every language), textures and API names in seconds. After a change to `Contents/`, also `dev/validate-server.sh`.
- Each in-game test run pays for a game start, so batch: commit each logical change on its own, then run `dev/run-debug-client.sh --test --changed` once per batch, not after each edit. Before pushing or merging: `dev/run-debug-client.sh --test`. Before a release, also `dev/run-debug-client.sh --test --mp`.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts and decompiled Java, not web docs or memory: most published modding docs describe Build 41, whose APIs fail silently in Build 42.
- Test in the game, in the dev mod's `HearingAidTests.lua` with the harness's test library (`PZHarness.Test`), never with standalone Lua and stubbed game APIs: the stubs encode guesses about the game, which is what the tests must check. Tests, the debug scenario and the art, promo and loot code stay in the dev mod, out of `Contents/`, which is published.
- Comments say why, without repeating values from the code: a copied value goes stale and nothing fails.
- When a test or check contradicts what you were asked to do, or fails on uncommitted work that isn't yours, stop and report it rather than editing the test or the other person's work.

## STOP

- Hand edits to generated files: the next run overwrites them. Edit `art/models/build.py` and `art/promo/compose.py`, never the models, textures or images they write.

## Read when needed

- Before running in-game tests, handing them to subagents, or debugging a failure or a `LEAK`, read `dev/harness/docs/debugging.md`: which run answers which question, and the traps that cost reruns.
- Before changing scripts, translations, multiplayer sync, loot, tests or art, read `DEVELOPMENT.md`: the Build 42 behaviour that fails silently, the command to decompile the game, and the art, promo and loot commands.
- Before changing anything under `dev/harness`, read `dev/harness/AGENTS.md`: other mods use it.
- Before changing `README.md`, the Workshop page, read `dev/harness/docs/workshop-page.md`.
