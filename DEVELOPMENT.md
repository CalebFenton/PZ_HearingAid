# Developer notes

What to run, and how Project Zomboid Build 42 behaves where the mod's code can't show you.

What belongs here:

- Commands: what to run for each job, what it needs, and how it fails.
- Game behavior the mod depends on that fails silently or isn't obvious from the code. Each fact names its source in the decompiled 42.21.0 Java or the vanilla Lua, so it can be checked again after a game update. Published modding docs mostly describe Build 41; when they disagree with the game files, trust the game files.
- Tips for debugging and writing tests that hold for any change, and the Workshop and release steps.

What doesn't:

- How the mod's own code or tests work. Put that in comments beside the code.
- The mod's own numbers: loot rates, XP, battery hours, test counts, run times that grow with the suite. The code and the commands' output hold them, and a copy here goes stale.
- Why a design or value was chosen, or what changed. That goes in the commit message.
- Notes from one task, and anything not checked against the game files.

Before adding a line, ask whether someone changing the mod a year from now, with the code open, would get something wrong without it.

## Commands

The client and server scripts are thin entry points into the shared test harness in `dev/harness`, a git submodule (run `git submodule update --init` after cloning); `dev/harness.conf` tells it about this mod, and `dev/harness/README.md` describes it. The tests, the debug scenario, their helpers and the art, promo, and loot code live in the dev mod `dev/HearingAidDevHarness`, which is never published. The scripts use the macOS Steam install (set `PZ_APP` to another `Contents` folder) and their own cache under `$TMPDIR` (set `CACHE` to use another), so they never touch your saves, settings, or mod list. Only one game started by these scripts runs at a time, for this mod or any other on the harness: a script waits for the lock while another one's game is up.

- `dev/validate-server.sh`: run after every change. It boots a dedicated server with only this mod and fails if the mod logs an error or names a loot list that doesn't exist.
- `dev/run-debug-client.sh --test`: runs every `hearingaid_*` test unattended and exits nonzero on a failure or any Lua error. It needs a JDK's `javac`, any version from 8 on. `TESTS=hearingaid_craft_,hearingaid_turn_` runs only the tests whose names start with one of those prefixes. The harness runs the tests without the debug menu runner's one-second pause after each, with timed actions instant, and with the frame rate uncapped; "HearingAidTest TIME" gives the seconds and frames the tests took. Starting and quitting the game adds about 27 seconds.
- `dev/run-debug-client.sh --test --stay`: the same, but the game stays open afterwards, and the next `--test --stay`, with any `TESTS`, loads `HearingAidTests.lua` again and reruns the tests in that game, in a second or two plus the tests' own time. A change to any other file restarts the game instead: the rest of the dev mod, the published mod, or the harness mod, because a reloaded file's `Events.*.Add` calls are ignored (see [Debugging by hand](#debugging-by-hand)). While it waits, the game shows and logs "HearingAidTest IDLE", and it quits after 30 minutes without a run or when another script needs the game. What earlier runs left in the kept world stays there (a rerun starts with `HearingAidTest DIRTY` lines naming it), so finish with a plain `--test`.
- `dev/run-debug-client.sh --test --mp`: the same tests in multiplayer: a dedicated server with the mod, the dev mod and the harness mod, and a debug client that joins it as the admin, runs the tests and quits. It fails on anything either side logs, and prints both logs' paths. On the client the inventory, traits and world are the client's copies, so what only the server can do goes through `PZHarness.Test.server` to handlers in the dev mod's server Lua (list them in `RELOAD_FILES` in `dev/harness.conf`), which single player calls in the same game. A test that can't run in one mode says why with `spOnly = "..."` or `mpOnly = "..."`, and the run lists it as `HearingAidTest SKIP`. With `--stay` both stay open and the next `--test --mp --stay` reruns in about a second. `dev/harness/docs/multiplayer.md` explains the server channel and what a client can't do.
- The client runs stop at the first stack trace through the Lua of the mod, the dev mod or the harness mod, or at any Lua failure once the harness has started, and print the trace, instead of waiting for the timeout: in debug mode a Lua error stops the game in the error handler, so it never quits on its own.
- `dev/run-debug-client.sh`: starts the debug client with the mod, the dev mod and the harness mod enabled and stops at the main menu, with the scenario and the tests of [Debugging by hand](#debugging-by-hand).
- `dev/run-debug-client.sh --loot`: prints how often each kind of corpse and container holds a wristwatch and each hearing aid model. Run it after changing loot.
- `art/models/make.sh`: rebuilds the models and textures with Blender. `--export` skips `build.py`, which would overwrite edits you made by hand in `hearing_aid.blend`. Previews land in `$TMPDIR/hearing-aid-previews`.
- `dev/run-debug-client.sh --art`: saves in-game close-ups of the worn and dropped hearing aids to `<cache>/Screenshots`. In the front view, the right ear is on the left of the picture.
- `dev/run-debug-client.sh --promo`, then `art/promo/compose.py`: captures the README and Workshop art from the game into `art/promo/captures`, then lays it out into `art/promo/images`. Commit the captures, so that a layout change needs only `compose.py`. `compose.py` also writes `42/poster.png` and `preview.png` from the same model captures as the banner, and the mod-list icon `42/hearing_aid_icon.png` from `art/drawings/hearing_aid.xcf`, which needs ImageMagick's `magick` to flatten. The mod list draws the icon at 22 to 28 pixels, so `compose.py` thickens the drawing's tube and outline first.
- `--art` and `--promo` draw uncapped frames like `--test`, so their steps wait on the zoom settling and on the UI's drawings, never on counts of frames. The UI draws at its own rate, the `uiRenderFPS` option (at most 120; `Core.StartFrameUI`), and the frames in between show its last drawing; `Events.OnPostUIDraw` fires once per drawing. Both run with the harness's `fastUI`, which draws it at 120, and `clearWeather`, so no fog greys the world shots. Lua can't tell when a model has loaded, and a character preview keeps drawing the old model until the new one has, so a capture that shows the aid of the shot before needs more drawings after the change.

## Debugging by hand

`dev/run-debug-client.sh` without flags gives you these. With `-debug` in the game's Steam launch options a normal game has the debug menu, but neither the scenario nor the tests nor `HearingAidLoot`, which come with the dev mod.

- The **Hearing Aid** scenario under **Scenarios** on the main menu starts a zombie-free world at 10 in the morning with every hearing aid model, batteries, recipe materials, and a table.
- To run one test, open the debug menu with the bug icon, then **Dev**, **Unit Tests**, **Timed Actions**.
- To measure one loot list more precisely than `--loot` does, call `HearingAidLoot.measureZombies(key, samples)` or `HearingAidLoot.measureContainer(key, samples)` in the Lua console. One list takes 40,000 samples; `HearingAidLoot.report`, which measures every list, runs out of memory far sooner.
- To see the loot of vanilla lists, right-click the world and choose **UI**, then **Generate Loot UI**. The **LootZed** admin power uses a simpler formula that ignores rounding, the zombie density bonus, and the rolls multiplier (`SpawnRateChecker.lua`).
- Restart the client after changing Lua. `reloadLuaFile()`, which the debug Lua file browser uses, runs the file again but ignores its `Events.*.Add` calls (`LuaCompiler.rewriteEvents`), so the old handlers keep running. That is enough for the test file, which only registers tests, and `--test --stay` relies on it.
- A dedicated server has no `-debug` argument; it reads only the JVM property `-Ddebug`.
- In debug mode, every mod without `media/AnimSets` and `media/actiongroups` folders logs a `NoSuchFileException` for each, and vanilla logs errors about fonts, `FluidContainerScript` names, a mannequin zone, missing tiles, and missing icons. None come from this mod.
- `getCore():TakeFullScreenshot("name.png")` writes to `<cachedir>/Screenshots/` without macOS Screen Recording permission.
- Keep `media/scripts` out of the dev harness. When it had one, this mod's items showed "Mod: Hearing Aid Dev Harness" in their tooltips.

## Writing tests

- The timed action test runner empties the inventory and calls `clearWornItems()` before each test, which fires no clothing event. Traits, perks, player modData, world objects, sandbox options, and the clock carry over to the next test, and `EveryOneMinute` keeps firing. Write tests with the `test()` helper in `HearingAidTests.lua` and the harness's library it builds on (`dev/harness/mod/42/media/lua/client/PZHarness/TestLib.lua`), whose setters and fixtures put back what they change.
- `--test` runs with the frame rate uncapped, so a count of frames is not a length of time. A test that waits for the game waits on the condition it needs (`PZHarness.Test.waitUntil`), never for a fixed number of frames.
- Every test runs at 10 in the morning, the scenario's hour, and waits for the light first: crafting needs light, and the world's light catches up with the clock only some frames after the game starts or the clock changes.
- `ISInventoryPaneContextMenu.OnNewCraft` crafts through the same path as a right-click, and when the game refuses, it queues nothing and says nothing. `HandcraftLogic` can tell you why.
- A table for an `AnySurfaceCraft` recipe must come from `IsoObject.new(square, spriteName, name)`. `IsoObject.new(square, spriteName)` builds a new sprite from the texture alone, so the object looks like a table but has no `Surface`. `findCraftSurface` also skips squares the character can't reach, such as the far side of a wall.

## Ground truth

The game ships its Lua, scripts, and assets unpacked, and its Java decompiles cleanly. The bundled Java has no `jar` tool, so `unzip` and `zip` pick out the `zombie` packages; decompiling them takes about 20 seconds:

```sh
PZC="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents"
cat ~/Zomboid/version.txt                     # installed version, such as 42.21.0 4a0e9546ec
ln -sfn "$PZC/Java/media" /tmp/pzmedia        # vanilla lua/, scripts/generated/, clothing/, models_X/
mkdir -p /tmp/pztools /tmp/pzclasses /tmp/pzsrc && cd /tmp/pzclasses
curl -sSL -o /tmp/pztools/vineflower.jar https://repo1.maven.org/maven2/org/vineflower/vineflower/1.11.1/vineflower-1.11.1.jar
unzip -q "$PZC/Java/projectzomboid.jar" 'zombie/*' && zip -qr /tmp/pztools/zombie.jar zombie
"$PZC/PlugIns/jre-aarch64/Contents/Home/bin/java" -jar /tmp/pztools/vineflower.jar -dgs=1 -thr=8 -log=WARN \
    "-e=$PZC/Java/projectzomboid.jar" /tmp/pztools/zombie.jar /tmp/pzsrc
```

Start from these files:

- Lua globals are the `@LuaMethod(name = ...)` methods in `zombie/Lua/LuaManager.java`; exposed classes are its `setExposed(X.class)` calls.
- `zombie/Lua/LuaEventManager.java` lists the Lua events. Search for `triggerEvent("Name"` in both the Java and the vanilla Lua to see which side fires each one.
- Script keys are parsed in `zombie/scripting/objects/Item.java` (`DoParam`) and in `CraftRecipe.java`, `InputScript.java`, and `OutputScript.java` under `zombie/scripting/entity/components/crafting/`.
- Vanilla patterns are in `/tmp/pzmedia/lua/shared/TimedActions/` and `/tmp/pzmedia/scripts/generated/`.
- Subscribed Workshop mods, some already ported to Build 42, are in `~/Library/Application Support/Steam/steamapps/workshop/content/108600/`.

## Mod layout and loading

Build 42 lists a mod folder only if it has `common/mod.info` or `<version folder>/mod.info`, and ignores files at the mod root.

- The game uses the child folder with the highest numeric name that is at least 42.0 and at most the game version, comparing major × 1000 + minor and ignoring the patch number. A folder named `42` works for every 42.x release.
- `common/media` loads first, and the version folder overrides files at the same relative path. A mod Lua file at the same relative path as a vanilla file replaces the vanilla file, so give every Lua file a `HearingAid` prefix in its folder or name.
- `versionMin` and `versionMax` in `mod.info` are the only compatibility check (`ChooseGameInfo.Mod.isAvailableSelf`). The mod list shows them as `min - max`, in red when the game is outside the range, and the game doesn't load such a mod. The "unsupported mods" filter only hides mods made for versions before 42.0 (`Core.getBreakModGameVersion()`).
- With Steam running, the game finds mods in `~/Zomboid/mods/*`, in Workshop staging folders (`~/Zomboid/Workshop/*/Contents/mods/*`), and in subscriptions. With `-nosteam` it reads only `<cachedir>/mods`. Two copies with the same `id` conflict, so unsubscribe from the Workshop copy while you develop.
- `media/registries.lua` runs before scripts load and again on every Lua reset; only the copy in the version folder runs if there is one, otherwise the copy in `common`. It's the only place to register namespaced ids such as `ItemBodyLocation.register("hearingaid:hearingaid")`. The game rejects the `base:` namespace and lowercases ids.
- Leaving a game re-initializes Lua (`IngameState.exit()` calls `LuaManager.init()`), so module-level Lua state starts fresh for every loaded game.

## Scripts

Item and recipe scripts are in `media/scripts/*.txt`. Only `/* */` comments work in them; `//` and `--` don't.

- Set `ItemType = base:clothing` (or `base:normal`, `base:drainable`, and so on). The Build 41 key `Type = Clothing` becomes an unknown parameter, and the item has no class.
- `ItemName.json` (key `Module.Item`) overwrites `DisplayName`, and vanilla items have no `DisplayName`.
- A new `BodyLocation` must be registered in `registries.lua`, added to the "Human" group from shared Lua with `BodyLocations.getGroup("Human"):getOrCreateLocation(location)`, and added to `WearClothingAnimations`. Without the group, wearing the item throws a `NullPointerException` in `WornItems.setItem`.
- A bare model name in `WorldStaticModel` resolves only in `module Base` (`ScriptBucketCollection.getScript`).
- A clothing XML file must have the item's `ClothingItem` name. `media/fileGuidTable.xml` maps its path to a GUID, which is what the lookup uses, so keep the GUID equal to the XML's `m_GUID`.
- A choice of how to wear an item, such as which ear, is a pair of item types. Each sets `ClothingExtraSubmenu` to its own option and `ClothingItemExtra` and `ClothingItemExtraOption` to its twin, as vanilla wristwatches do (`ISInventoryPaneContextMenu.doClothingItemExtraMenu`). Picking the twin's option runs `ISClothingExtraAction`, which replaces the item with a new one of the twin type; `copyModData` wipes the new item's modData first, so its OnCreate state doesn't survive. The action fires `OnClothingUpdated` from `complete()` and doesn't go through `ISWearClothing`.
- The item `OnCreate = Some.Lua.func` calls `func(item)` on every instantiation: loot, crafting outputs, debug spawns, loading a save, and a multiplayer client receiving the item. When loading, `item:load()` then replaces the modData, but only if the saved modData isn't empty, so always write at least one key. Uses set on a drainable item in OnCreate are overwritten afterwards.
- `Medical = true` puts the item under the Medical loot rarity setting; clothing otherwise counts as Clothing. `Tags = base:ignorezombiedensity` keeps the zombie density bonus, up to 0.8% per roll, from swamping small weights.
- `ChanceToFall` gets 40 added when the head is hit (`IsoGameCharacter.helmetFallFromWornItems`), so a value of 5 means a 45% chance per head hit.
- With the 3D ground items option on, which is the default (`3DGroundItem` in `Core`), the game draws a dropped item from its `WorldStaticModel`, resting on y = 0 with y up.

### craftRecipe

Build 41 `recipe` blocks no longer load.

- Lines without `=`, such as the Build 41 `Time:30`, are skipped without an error. Unknown keys log an error, and throw in debug mode.
- Input flags in `flags[...]` are case-sensitive enum names, and `[...]` lists must not contain spaces. `NoBrokenItems` has no effect; broken items are always refused unless an input sets `AllowDestroyedItem`.
- Use `tags[base:screwdriver]` for tool tags and `mode:keep` for tools. An input line can list items and tags together, `[Base.Glasses_Reading] tags[base:magnifier]`, and accepts any of them (`InputScript.OnPostWorldDictionaryInit`).
- An input of a drainable item counts uses: `item 1 [Base.Glue]` takes one of the tube's five uses. `flags[ItemCount]` takes whole items instead.
- Worn items count as inputs, and a worn `mode:keep` tool stays worn. `flags[IsNotWorn]` refuses worn and equipped items.
- `Tags = AnySurfaceCraft` needs a table or counter within 3 tiles (`HandcraftLogic`), and the craft walks the character to it. A tag other than `InHandCraft`, `AnySurfaceCraft`, `EntityRecipe`, and `Outdoors`, on a recipe without one of them, makes it need a crafting bench entity (`CraftRecipe.requiresSpecificWorkstation`). The `Electrical` tag does nothing else; `category = Electrical` sets the crafting window category.
- Every recipe needs light unless it has the `CanBeDoneInDark` tag (`CraftRecipeData`, `IsoPlayer.tooDarkToRead`).
- `xpAward = Electricity:10` and `SkillRequired = Electricity:2` replace Build 41 `OnGiveXP` and `SkillRequired:`.
- `OnCreate(craftRecipeData, character)` runs once, locally in single player and on the server in multiplayer, after the outputs were sent to the client. Call `result:syncItemFields()` after changing an output.
- `OnTest(item, character)` runs for every candidate input item, tools included.
- `OnTest` and `OnCreate` accept dotted Lua paths (`LuaManager.getFunctionObject`). `OnAddToMenu(params)` must be a plain global name, because the game reads it with a raw `_G` lookup.
- `craftRecipeData:getAllConsumedItems()` excludes `mode:keep` inputs, and `getFirstCreatedItem()` returns the output. No flag copies modData to the output, and vanilla adds per-input counter keys to the output's modData after OnCreate.
- Recipes can't be switched on and off at runtime. To gate one with a sandbox option, use OnTest, which blocks crafting on the server too, and OnAddToMenu, which hides the recipe.
- `CraftRecipe:clearRequiredSkills()` and `addRequiredSkill(perk, level)` change a recipe's skill requirement in place, and the can-craft check, craft time, and every crafting window read that list. Single player, the server, and each client hold their own recipe objects, rebuilt from the scripts whenever Lua reloads, so apply the change on every side. No event fires when an admin changes sandbox options mid-game (`GameServer.receiveSandboxOptions`).
- Build 41 `fixing` blocks still parse, but only with `=`: `Require = ...`, `Fixer = ...`.

### Sandbox options

`media/sandbox-options.txt` must start with `VERSION = 1,`. Option types are `boolean`, `integer`, `double`, `enum`, and `string`. The translation keys are `Sandbox_<translation>` and `Sandbox_<translation>_tooltip` for an option, `Sandbox_<valueTranslation>_option<N>` for enum values numbered from 1, and `Sandbox_<page>` for the page title.

`SandboxVars.<Table>.<Key>` holds every option of every active mod as soon as Lua loads (`shared/Sandbox/SandboxVars.lua` calls `initSandboxVars()`), and the setters reject values outside `min` and `max` (`DoubleConfigOption.setValue`). Read options without Lua defaults, which would hide a misspelled option name.

## Translations

The game loads only JSON translations, from `media/lua/shared/Translate/<LANG>/<File>.json`, and ignores `.txt` translation files. `<LANG>` is a folder name of the game's own `media/lua/shared/Translate`, such as `PTBR` or `ES_CL`.

- File names that load include `ItemName`, `Recipes`, `IG_UI`, `Tooltip`, `ContextMenu`, `Sandbox`, and `UI` (`Translator.BY_NAME`). `Mod.json` translates `mod.info`: its `name` and `description` keys replace the mod list's text (`Translator.readModTranslation`).
- Item keys are `"Module.Item"`, and craftRecipe keys are the bare recipe name. Prefixed keys go in the matching file: `IGUI_` keys in `IG_UI.json`, `Tooltip_` keys in `Tooltip.json`.
- The game loads English first and the chosen language over it (`Translator.forLanguageStack`), so a missing key shows English. No shipped language names a `base` in its `language.json`, so `ES_CL`, `ES_MX`, and `AR` fall back to English, not to `ES`. `STREW` (Strewberrie) is a placeholder language that replaces every word.
- Debug builds parse strict JSON, without comments or trailing commas. A file that doesn't parse throws from `Translator.loadFiles`, which runs when the game starts, a game loads, or the language changes.
- Values are Java format strings (`Translator.formatFixer`): `%1`, `%2` take `getText(key, a, b)`'s arguments, and `%%` is a literal percent sign. A whole Lua number formats without a decimal point (`Translator.fixupArgs`). Let translators place numbers and punctuation (`"%1%%"`, `"Battery:"`) instead of concatenating them in Lua: French writes `Pile :`, Danish `50 %`.
- Vanilla keys such as `ContextMenu_Turn_On`, `ContextMenu_AddBattery`, and `ContextMenu_Remove_Battery` are already translated into every language. For terms the mod shares with the game (traits, items, skills, the wristwatch's `ContextMenu_LeftWrist`), look up the vanilla key's value in the game's folder of that language. The `glossary.tbx` files there are nearly empty.
- `Translator.loadFiles` in a running game changes what `getText` returns, but items keep the names their scripts got when the game started. To see the mod in another language, set `language=` in `options.ini` of the debug client's cache (`$TMPDIR/pz-hearingaid-client`) before starting it.

## Lua runtime

### Who runs what

| Context | `isClient()` | `isServer()` | Lua that runs |
|---|---|---|---|
| Single player | false | false | Client, shared, and server Lua in one state |
| Multiplayer client | true | false | Client, shared, and server Lua; guard server handlers with `isClient()` |
| Dedicated server | false | true | Shared and server Lua; client Lua is only checksummed |

### State and syncing

- Traits use `player:hasTrait(CharacterTrait.HARD_OF_HEARING)` and `player:getCharacterTraits():add(...)` or `:remove(...)`; Build 41 `getTraits()` is gone. The server owns traits: a client without admin rights can't send them (`SyncXp` checks). Change traits on the server, then call `sendSyncPlayerFields(player, 2)` (`SyncPlayerFieldsPacket.PF_Traits`).
- Hearing effects read the trait flags directly: muffled audio (`ParameterHardOfHearing`), hearing distance, and detection range. An item's `HearingModifier` belongs to the item script, not the item, so it can't depend on the battery.
- `item:syncItemFields()` sends an item's modData, uses, and condition to the other side: from the server to the player whose inventory holds it, or from a client to the server. The global `syncItemFields(player, item)` does the same for that player. Both do nothing in single player.
- On the server, `Actions.addOrDropItem(character, item)` adds and syncs an item. To remove one, call `container:Remove(item)` and then `sendRemoveItemFromContainer(container, item)`; the send does nothing outside the server.
- A client sends its whole player modData to the server (`transmitModData`), and the server replaces its copy with it. ISHotbar does this after every clothing change, so anything the server writes to player modData can disappear.
- Create a battery with `instanceItem("Base.Battery")`; `InventoryItemFactory` isn't exposed to Lua. Its charge is `getCurrentUsesFloat()` and `setCurrentUsesFloat()`. `getUsedDelta()` no longer exists on drainable items, and `setUsedDelta` is a deprecated alias. A full battery has 142 uses, and `setCurrentUsesFloat()` rounds to the nearest whole use.

### Timed actions in multiplayer

- If an action class has `complete()`, the client runs `start()`, `update()`, and `perform()`, and the server runs `complete()`. Single player runs `perform()` and then `complete()` in the same tick (`IsoGameCharacter`'s action loop).
- The server rebuilds the action by calling `<Class>:new()` with the values of the fields named like `new()`'s parameters, in parameter order (`NetTimedAction`). Parameter names must equal field names, and every argument must be serializable. Items are sent as container plus id, so they must be in a container. An unsupported argument type is dropped and shifts the arguments after it.
- The server never calls `isValid()`, `update()`, or `perform()`, so check the action again in `complete()`; returning `false` rejects it.
- On the client, fetch items again by id in `start()`, as vanilla does, because server syncs can replace the item objects.
- The client's action waits for the server's `complete()` (`LuaTimedActionNew.setWaitForFinished`), and keeps calling `isValid()` meanwhile. What `complete()` removes, such as an inserted battery, reaches the client first, so an `isValid()` that checks it then fails; the client stops the action, skips `perform()`, and `ISBaseTimedAction:stop` empties the whole action queue. Check such items only until `self:isStarted()` on a client.
- The server decides an action's length: it rebuilds the action and calls `getDuration()` with its own copy of the character, whose instant-action cheat is the server's.
- The game deletes a drainable item whose uses run out (`DrainableComboItem.update`), so no empty battery ever stays in an inventory.

### Events

| Event | Where it fires |
|---|---|
| `EveryOneMinute` | Single player, multiplayer client, and server. It fires at most once per tick however much game time passed, so compute elapsed time from `getGameTime():getWorldAgeHours()`. |
| `OnPlayerUpdate` | Only for local players, so never on a dedicated server. |
| `OnClothingUpdated` | Vanilla Lua and Java fire it after clothing changes, but not always after the change. `ISWearClothing` fires it from `perform()`, which single player runs before `complete()` puts the item on, and a dedicated server never runs `perform()`. On the server, `ISUnequipAction:complete()`, transfers, and drops fire it; `setWornItem()` calls only the Java `OnClothingUpdated()` method. |
| `OnInitGlobalModData` | Single player, server, and multiplayer client, once per loaded game, after the sandbox options load. A client has received the server's options by then. |
| `OnServerCommand` | Multiplayer clients, for `sendServerCommand()` from the server. |

### UI

- To add inventory context menu options, handle `Events.OnFillInventoryObjectContextMenu(playerNum, context, items)` and pass `items` through `ISInventoryPane.getActualItems(items)`, which unpacks stacks.
- `ISToolTipInv` also shows things that aren't items, such as fluid containers and energy resources. Check `instanceof(x, "InventoryItem")` before calling item methods.
- `HaloTextHelper` draws only on the local client, so in multiplayer the server has to send a command to show halo text.

## Loot

`IsoWorld.init` fires `OnDistributionMerge` and `OnPostDistributionMerge`, then loads the save's sandbox options, then calls `ItemPickerJava.Parse()`, then fires `OnInitGlobalModData`. When a single player game is continued, the merge events therefore see the sandbox options of the default preset. Loot that depends on sandbox options has to be added in `OnInitGlobalModData`, followed by another `ItemPickerJava.Parse()`.

- The chance per roll is ⌈weight × 100 × loot category multiplier + zombie density bonus⌉ in 10,000, and a container rolls `rolls` times (`ItemPickerJava.getActualSpawnChance`). Every positive chance rounds up to at least 1 in 10,000, so at the default multiplier of 0.6 a weight below 1/60 spawns more often than it says. The multiplier is a float a little above 0.6, so a product that should come out whole rounds up too: a weight of 0.25 gives 16 in 10,000. The density bonus is added, not multiplied, so it's the same for every entry whatever its weight. The Lucky and Unlucky traits no longer affect loot.
- `items` lists are flat name and weight pairs, so always append both. Unknown item names are dropped, with a message only in debug logs.
- `junk` lists roll with the loot category multiplier fixed at 1.0 and weights × 1.4, so the loot rarity settings don't scale them. They are often shared by reference (`ClutterTables.*`), so don't add to them.
- A corpse rolls its loot when it's first opened or its square first loads: `SuburbsDistributions.all.Outfit_<outfit>`, and then `inventorymale` or `inventoryfemale` unless the outfit table sets `defaultInventoryLoot = false`. The comment in vanilla `Distributions.lua` that says outfit tables replace the gendered ones is wrong.
- A mod outfit in `clothing.xml` with a vanilla name replaces that outfit, and mod outfits can't reference vanilla clothing (`OutfitManager`), so corpse loot tables are the way to give an outfit items.
- Nothing records a character's age. The `Retiree` outfit is the only sign of it, common in nursing home, trailer park, rich neighborhood, golf course, and country club zones and rare elsewhere (`ZombiesZoneDefinition.lua`). Vanilla has no `Outfit_Retiree` loot table.
- No room is a nursing home, audiologist, or hearing aid shop.
- Zombies wear wristwatches only through their outfits in `clothing.xml`, and their worn items go into the corpse (`IsoZombie.DoZombieInventory`), so the corpse loot lists hold no wristwatches. Wristwatches have the `base:morewhennozombies` tag, which doubles their chance in every list when the Zombies option is None (`ItemPickerJava.getBaseChanceMultiplier`), as in the Hearing Aid debug scenario.

## Workshop page

- The description loads its images from `raw.githubusercontent.com/CalebFenton/PZ_HearingAid/master/art/promo/images/`, so pushing new images to master updates the page without an upload, and renaming one breaks it.
- The description is limited to 8000 bytes, BBCode included. `[table]` renders there.
- The in-game Workshop screen uploads `Contents/` and `preview.png`, which must be a square PNG of 256 or 512 pixels and at most 1 MB. The other files at the repository root aren't uploaded. Tags must come from the game's `media/WorkshopTags.txt`.

## Release checklist

1. `dev/validate-server.sh` and `dev/run-debug-client.sh --test` must pass. Then run what fits the change: `--art` for models, `--promo` and `compose.py` for art or the interface, `--loot` for loot.
2. Bump `modversion` in `42/mod.info`. Raise `versionMin` when the mod starts depending on a newer game version; lower it only after testing on the older version.
3. Update `workshop.txt` and `README.md`.
4. Upload from the in-game Workshop screen.
