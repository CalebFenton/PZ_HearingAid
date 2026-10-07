# Agent notes

- Read `DEVELOPMENT.md` before changing anything. It records the Build 42 facts this mod depends on: layout, scripts, translations, multiplayer authority, loot timing and testing.
- Ground truth is the installed game: vanilla files under `Project Zomboid.app/Contents/Java/media` and the decompiled `projectzomboid.jar` (commands in `DEVELOPMENT.md`). Don't rely on web docs or memory for B42 APIs.
- B42 code lives in `Contents/mods/HearingAid/42/` and assets in `common/`. Files directly under `Contents/mods/HearingAid/media` and `mod.info` are the published Build 41 release; leave them alone.
- Verify every change with `dev/validate-server.sh` (headless, no clicks) and `dev/run-debug-client.sh --auto`. The client needs one human click at "Click to start"; results are the `HearingAidTest`/`HearingAidCheck` lines in `<cache>/console.txt`.
- New behavior gets a `hearingaid_*` test in `42/media/lua/client/HearingAid/Debug/HearingAidTests.lua`.
