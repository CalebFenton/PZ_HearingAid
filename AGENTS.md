# Hearing Aid

## Commands

- After every change: `dev/validate-server.sh`. It boots a headless dedicated server and fails on any error the mod logs.
- While you iterate, run only the tests your change touches, in a kept game: `TESTS=<name prefix> dev/run-debug-client.sh --test --stay` runs those and keeps the game open, so the next such run reruns them in a second or two; `--failed` reruns the last run's failures. A kept game reloads only the test and handler files; a change to `Contents` or the harness relaunches it. The runs need a JDK's `javac` on `PATH` (or `JAVAC` set).
- Before committing: one plain `--test` and one `--test --mp`, the whole suite in fresh worlds. `--mp` runs the same tests with a dedicated server and a client that joins it. What only the server can do goes through `PZHarness.Test.server` and handlers in the dev mod's server Lua; `dev/harness/docs/multiplayer.md` explains it.
- The scripts run on the shared test harness in the `dev/harness` submodule (`git submodule update --init` in a fresh clone), whose README describes it. It's shared with other mods: change it only in ways that fit any mod, and expect a run to wait while another mod's dev script has a game up; just run them.

## Spending game runs

A fresh multiplayer game costs most of a minute before the first test; the `timing:` lines and `dev/.runs.log` show where each run's time went. A run is the most expensive thing you do, so each one must test something new:

- Before a run, check that your edits applied. Rerunning unchanged code tells you nothing, unless you are measuring a flake with `REPEAT=<n>`.
- A failure: read its reason and the log around it (both logs' paths print at the end), add the one diagnostic that decides between your explanations, and rerun only that test.
- Passes alone but fails in the suite: an earlier test leaked. Read the `LEAK` and `DESYNC` lines, which every run prints and which fail the test that leaked; `ORDER=reverse` or `ORDER=shuffle` confirms an order dependence. Never bisect by hand in a `--stay` game: it keeps every earlier run's leftovers.
- Three runs on one failure without narrowing it: stop, write down what each ruled out, and change approach.
- Subagents edit; one agent runs the game, batching everyone's changes into one run.
- `dev/harness/docs/debugging.md` has the whole protocol and the harness's traps, such as a refused timed action clearing the action queue and a Lua error stopping the game.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add tests to `dev/HearingAidDevHarness/42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`, with the harness's test library (`PZHarness.Test`). Tests, the debug scenario, and the art, promo, and loot code live in that dev mod, never in `Contents`, which is published. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- Edit `art/models/build.py` and `art/promo/compose.py`, not the models, textures, or images they generate; the next run overwrites hand edits.
- Comments say why, without repeating values from the code. Before editing `DEVELOPMENT.md`, read its opening on what belongs there.
- Don't add `CLAUDE.md`; this is the only agent instruction file.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo, and loot commands.
