# Developer notes

This document covers how to test the mod and the Project Zomboid Build 42 behavior that the code depends on. Each fact was checked against the decompiled 42.21.0 Java or the vanilla Lua and scripts, and the source is named where it helps you check it again after a game update. Published modding docs mostly describe Build 41, so when they disagree with the game files, trust the game files.

## Testing

Both scripts use the game from the macOS Steam install (set `PZ_APP` to another `Contents` folder) and their own cache directory under `$TMPDIR` (set `CACHE` to use another), so they never touch your saves, settings, or mod list. `dev/lib.sh` holds what they share.

`dev/validate-server.sh` boots a dedicated server with only this mod, waits for `SERVER STARTED`, stops it, and searches the log. It fails on a Lua error, whose stack trace names the mod as `(MOD:Hearing Aid)`; on a `WARN` or `ERROR` line that names the mod, such as an unknown item script key; and on the `HearingAid: missing` line that `HearingAidDistributions.lua` prints for a loot table that doesn't exist. It takes about 25 seconds and needs no clicks, so run it after every change.

`dev/run-debug-client.sh` starts the client in debug mode and copies your `options.ini`, so a fresh profile skips the first-run screens. Without arguments it stops at the main menu. With `--test` it also loads `dev/HearingAidDevHarness`, which starts the debug scenario, runs every `hearingaid_*` test, saves `hearingaid_tests.png` and `hearingaid_showcase.png` to `<cache>/Screenshots`, and quits the game. The script then prints the `HearingAidTest` lines from `<cache>/console.txt` and exits nonzero if a test failed or the mod logged a Lua error. A test run takes about 2 minutes and needs nobody at the computer: the script wakes the display and starts the game through `dev/ClickToStart.java`, which presses **Click to start**. Building that launcher needs a JDK's `javac`, any version from 8 on.

With `--art` the harness runs no tests. It dresses a bald male character and then a bald female one in every aid on each ear, and for each saves `art_<sex>_<item type>.png` to `<cache>/Screenshots`: the head from four sides, drawn by the character preview panel of the character creation screen, which renders worn models and textures the way the game does. Then it drops one aid of each tier next to the character at the closest default zoom and saves `art_ground.png`. A run takes about a minute.

Apart from pressing **Click to start**, the harness only automates vanilla debug tools, which you can also use by hand in any game started with `-debug` (add it to the Steam launch options for your normal game):

- The **Hearing Aid** debug scenario (`HearingAidDebugScenario.lua`) is listed under **Scenarios** on the main menu. It starts a zombie-free world with a Hard of Hearing character, Electrical 8, every tier, batteries, recipe materials, and a table to craft at.
- The tests (`HearingAidTests.lua`) register with the vanilla timed action test runner. Open the debug menu with the bug icon, choose **Dev**, then **Unit Tests**, then **Timed Actions**, and run any `hearingaid_*` test.

These facts about the runner and the client shape the tests and the harness:

- Before each test the runner empties the inventory and calls `clearWornItems()`, which fires no clothing event. Traits, player modData, and sandbox options carry over, so the `test()` helper resets the character's hearing with `HearingAid.setBaseLevel()` and sets the sandbox options a test lists, restores them after `validate()`, and applies the recipe skill levels after each change.
- `EveryOneMinute` keeps firing during tests. Drain tests call `HearingAid.update(now)` with explicit world ages, so their expected charges hold whether or not a real update runs in between. Tests that show an action drains the battery itself set `periodicUpdate = false`, which removes `HearingAid.update` from `EveryOneMinute` until `validate()` ends.
- The Unit Tests panel must be open before `TimedActionTests.runOne(name)`, or the runner fails on its result labels. `UnitTestsDebug.OnOpenPanel()` opens it.
- `ISInventoryPaneContextMenu.OnNewCraft(selectedItem, getScriptManager():getCraftRecipe("Module.Name"), playerNum, false)` crafts through the same path as a right-click. When the game refuses, it queues nothing and says nothing, so the tests' `craftTest()` helper asks `HandcraftLogic` for the reason: Electrical too low, no table in reach, too dark, or which input line no item matched.
- A table for `AnySurfaceCraft` recipes must come from `IsoObject.new(square, spriteName, name)`, which uses the tile's own sprite and its properties. `IsoObject.new(square, spriteName)` builds a new sprite from the texture alone, so the object looks like a table but has no `Surface` and no sprite name. `findCraftSurface` also skips squares the character can't reach, such as the far side of a wall.
- Debug scenarios go in the global `debugScenarios` table. Without a `startLoc`, world creation crashes. `setSandbox` must call `ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))`, or the new save doesn't record its mods. `forceLaunch = true` starts a scenario from the main menu only when `<cachedir>/debug-options.ini` contains `DebugScenario.ForceLaunch=true`.
- **Click to start** waits for a real left click, a joypad A press, or the private `forceDone` flag (`GameLoadingState.update`), and Lua can reach none of them. `ClickToStart.java` runs the game's `MainScreenState.main` and sets `forceDone` on the loading state in `GameWindow.states.current` once the prompt shows. It waits for the game's `MainThread` before reading `GameWindow`, because reading a static field of an uninitialized class initializes it on the reading thread. Posting a real click instead needs macOS Accessibility permission. The game's bundled Java has no compiler, so the script builds the launcher with a JDK. A fresh cache directory also stops at the terms of service unless `options.ini` has `termsOfServiceVersion=1`.
- GLFW lists no monitor while the display sleeps, so the client dies in `Display.init` with a `NullPointerException` from `glfwGetVideoMode`. `caffeinate -u` wakes the display, and `-d -i` keep the display and the computer awake for the run.
- The client empties `mods/default.txt` when it starts unless `<cachedir>/mods/reset-mods-42_00.txt` exists (`ZomboidFileSystem.resetDefaultModsForNewRelease`), so the first start in a new cache dir would load no mods and stop at the main menu. The script writes that file first.
- Single player pauses when the window loses focus if the `focusloss` option is on, which is the default (`IngameState.onDisplayFocusLost`), and a paused game doesn't fire `OnTick`. The harness calls `getCore():setOptionPauseOnFocusloss(false)` so the tests keep running in the background.
- `getCore():quitToDesktop()` closes the game cleanly, which lets the test script wait for the game process to exit.
- Restart the client after changing Lua. `reloadLuaFile()`, which the debug Lua file browser uses, runs the file again but ignores its `Events.*.Add` calls (`LuaCompiler.rewriteEvents`), so event handlers and wrapped vanilla functions from the first load keep running the old code.
- `getCore():TakeFullScreenshot("name.png")` writes to `<cachedir>/Screenshots/` and doesn't need macOS Screen Recording permission.
- `ISUI3DModel` shows `(25 - zoom) / sqrt(2048)` model units above and below its centre (`UI3DModel`, `AnimatedModel.UIModelCamera`), and its y offset moves the character down; the face preview of the character creation screen uses zoom 14 and y offset -0.85. Give the panel its character with `setCharacter()` before it first draws, or `AnimatedModel.updateInternal` throws a `NullPointerException` every frame.
- The client turns on debug mode with the `-debug` argument. The server has no such argument and reads only the JVM property `-Ddebug`.
- Every mod without `media/AnimSets` and `media/actiongroups` folders logs a `NoSuchFileException` for each in debug mode. Vanilla also logs errors about fonts, `FluidContainerScript` names, a mannequin zone, missing tiles, and missing icons. None of these come from this mod.
- `hearingaid_corpse_loot` fills a scratch `ItemContainer` from the corpse loot lists through `ItemPickerJava.doRollItem`, the engine's own roll, and prints the measured rates on a `HearingAidTest INFO` line. To see the rates of other lists, use the vanilla loot simulator: in a debug game, right-click the world and choose **UI**, then **Generate Loot UI** (`ISLootStressTestUI.lua`). The **LootZed** admin power estimates chances with a simpler formula that ignores rounding, the zombie density bonus, and the rolls multiplier (`SpawnRateChecker.lua`).

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

Build 42 lists a mod folder only if it has `common/mod.info` or `<version folder>/mod.info`. Build 42 ignores the files at the mod root, which hold the Build 41 release here, and Build 41 ignores `common/` and `42/`.

- The game uses the child folder with the highest numeric name that is at least 42.0 and at most the game version, comparing major × 1000 + minor and ignoring the patch number. A folder named `42` works for every 42.x release.
- `common/media` loads first, and the version folder overrides files at the same relative path. A mod Lua file at the same relative path as a vanilla file replaces the vanilla file, so every Lua file here has a `HearingAid` prefix in its folder or name.
- `versionMin` and `versionMax` in `mod.info` are the only compatibility check (`ChooseGameInfo.Mod.isAvailableSelf`). The mod list shows them as `min - max`, in red when the game is outside the range, and the game doesn't load such a mod. The "unsupported mods" filter only hides mods made for versions before 42.0 (`Core.getBreakModGameVersion()`).
- With Steam running, the game finds mods in `~/Zomboid/mods/*`, in Workshop staging folders (`~/Zomboid/Workshop/*/Contents/mods/*`), and in subscriptions. With `-nosteam` it reads only `<cachedir>/mods`. Two copies with the same `id` conflict.
- `media/registries.lua` runs before scripts load and again on every Lua reset; only the copy in the version folder runs if there is one, otherwise the copy in `common`. It's the only place to register namespaced ids such as `ItemBodyLocation.register("hearingaid:hearingaid")`. The game rejects the `base:` namespace and lowercases ids.
- Leaving a game re-initializes Lua (`IngameState.exit()` calls `LuaManager.init()`), so module-level Lua state starts fresh for every loaded game.

## Scripts

Item and recipe scripts are in `media/scripts/*.txt`. Only `/* */` comments work in them; `//` and `--` don't.

- Set `ItemType = base:clothing` (or `base:normal`, `base:drainable`, and so on). The Build 41 key `Type = Clothing` becomes an unknown parameter, and the item has no class.
- `ItemName.json` (key `Module.Item`) overwrites `DisplayName`, and vanilla items have no `DisplayName`.
- A new `BodyLocation` must be registered in `registries.lua` and added to the "Human" group from shared Lua with `BodyLocations.getGroup("Human"):getOrCreateLocation(location)`. Otherwise wearing the item throws a `NullPointerException` in `WornItems.setItem`. Also add it to `WearClothingAnimations`. `HearingAidBodyLocations.lua` does all three.
- A bare model name in `WorldStaticModel` resolves only in `module Base` (`ScriptBucketCollection.getScript`), so the ground model scripts are in `module Base` with unique names.
- A clothing XML file must have the item's `ClothingItem` name. `media/fileGuidTable.xml` maps its path to a GUID, which is what the lookup uses, so keep the GUID equal to the XML's `m_GUID`.
- A choice of how to wear an item, such as which ear, is a pair of item types. Each sets `ClothingExtraSubmenu` to its own option and `ClothingItemExtra` and `ClothingItemExtraOption` to its twin, as vanilla wristwatches do, and the Wear submenu lists `ContextMenu_<option>` for both (`ISInventoryPaneContextMenu.doClothingItemExtraMenu`). Picking the twin's option runs `ISClothingExtraAction`, which replaces the item with a new one of the twin type and copies its modData, condition, and visuals; `copyModData` wipes the new item's modData first, so its OnCreate state doesn't survive. The action's `complete()` fires `OnClothingUpdated` once the new item is worn, and doesn't go through `ISWearClothing`.
- The item `OnCreate = Some.Lua.func` calls `func(item)` on every instantiation: loot, crafting outputs, debug spawns, loading a save, and a multiplayer client receiving the item. When loading, `item:load()` then replaces the modData, but only if the saved modData isn't empty, so the mod always writes `HearingAid_v`. Uses set on a drainable item in OnCreate are overwritten afterwards.
- `Medical = true` puts the item under the Medical loot rarity setting; clothing otherwise counts as Clothing. `Tags = base:ignorezombiedensity` keeps the zombie density bonus, up to 0.8% per roll, from swamping small weights.
- `ChanceToFall` gets 40 added when the head is hit (`IsoGameCharacter.helmetFallFromWornItems`), so a value of 5 means a 45% chance per head hit. The aids don't set it.

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

Lua reads options as `SandboxVars.<Table>.<Key>`. The table holds every option of every active mod as soon as Lua loads (`shared/Sandbox/SandboxVars.lua` calls `initSandboxVars()`), and the option setters reject values outside `min` and `max` (`DoubleConfigOption.setValue`). The mod therefore reads options without Lua defaults, which would hide a misspelled option name.

## Translations

The game loads only JSON translations, from `media/lua/shared/Translate/<LANG>/<File>.json`, and ignores `.txt` translation files.

- File names that load include `ItemName`, `Recipes`, `IG_UI`, `Tooltip`, `ContextMenu`, `Sandbox`, and `UI` (`Translator.java`).
- Item keys are `"Module.Item"`, and craftRecipe keys are the bare recipe name. Prefixed keys go in the matching file: `IGUI_` keys in `IG_UI.json`, `Tooltip_` keys in `Tooltip.json`.
- Debug builds parse strict JSON, without comments or trailing commas. Write `%%` for a literal percent sign.
- Vanilla keys such as `ContextMenu_Turn_On`, `ContextMenu_AddBattery`, and `ContextMenu_Remove_Battery` are already translated into every language.

## Lua runtime

### Who runs what

The table shows what `isClient()` and `isServer()` return in each context:

| Context | `isClient()` | `isServer()` | Lua that runs |
|---|---|---|---|
| Single player | false | false | Client, shared, and server Lua in one state |
| Multiplayer client | true | false | Client, shared, and server Lua; guard server handlers with `isClient()` |
| Dedicated server | false | true | Shared and server Lua; client Lua is only checksummed |

### State and syncing

- Traits use `player:hasTrait(CharacterTrait.HARD_OF_HEARING)` and `player:getCharacterTraits():add(...)` or `:remove(...)`; Build 41 `getTraits()` is gone. The server owns traits: a client without admin rights can't send them (`SyncXp` checks). Change traits on the server, then call `sendSyncPlayerFields(player, 2)` (`SyncPlayerFieldsPacket.PF_Traits`).
- Hearing effects read the trait flags directly: muffled audio (`ParameterHardOfHearing`), hearing distance, and detection range. An item's `HearingModifier` belongs to the item script, not the item, so it can't depend on the battery.
- `item:syncItemFields()` sends an item's modData, uses, and condition to the other side: from the server to the player whose inventory holds it, or from a client to the server. The global `syncItemFields(player, item)` does the same for that player. Both do nothing in single player. The mod calls them only where its state changes, on the authority.
- On the server, `Actions.addOrDropItem(character, item)` adds and syncs an item. To remove one, call `container:Remove(item)` and then `sendRemoveItemFromContainer(container, item)`; the send does nothing outside the server.
- A client sends its whole player modData to the server (`transmitModData`), and the server replaces its copy with it. ISHotbar does this after every clothing change, so anything the server writes to player modData can disappear. `HearingAid.lua` keeps the server's values in memory, keyed by username, and writes them back.
- Create a battery with `instanceItem("Base.Battery")`; `InventoryItemFactory` isn't exposed to Lua. Its charge is `getCurrentUsesFloat()` and `setCurrentUsesFloat()`. `getUsedDelta()` no longer exists on drainable items, and `setUsedDelta` is a deprecated alias. A full battery has 142 uses, and `setCurrentUsesFloat()` rounds to the nearest whole use.

### Timed actions in multiplayer

- If an action class has `complete()`, the client runs `start()`, `update()`, and `perform()`, and the server runs `complete()`. Single player runs `perform()` and then `complete()` in the same tick (`IsoGameCharacter`'s action loop).
- The server rebuilds the action by calling `<Class>:new()` with the values of the fields named like `new()`'s parameters, in parameter order (`NetTimedAction`). Parameter names must equal field names, and every argument must be serializable. Items are sent as container plus id, so they must be in a container. An unsupported argument type is dropped and shifts the arguments after it.
- The server never calls `isValid()`, `update()`, or `perform()`, so check the action again in `complete()`; returning `false` rejects it.
- On the client, fetch items again by id in `start()`, as vanilla does, because server syncs can replace the item objects.

### Events

The table lists where the events the mod handles fire. Battery drain runs on `EveryOneMinute` because `OnPlayerUpdate` fires only for local players, never on a dedicated server.

| Event | Where it fires |
|---|---|
| `EveryOneMinute` | Single player, multiplayer client, and server. It fires at most once per tick however much game time passed, so compute elapsed time from `getGameTime():getWorldAgeHours()`. |
| `OnClothingUpdated` | Vanilla Lua and Java fire it after clothing changes, but not always after the change. `ISWearClothing` fires it from `perform()`, which single player runs before `complete()` puts the item on, and a dedicated server never runs `perform()`. On the server, `ISUnequipAction:complete()`, transfers, and drops fire it; `setWornItem()` calls only the Java `OnClothingUpdated()` method. `HearingAidServer.lua` therefore also wraps `ISWearClothing:complete()`. |
| `OnInitGlobalModData` | Single player, server, and multiplayer client, once per loaded game, after the sandbox options load. A client has received the server's options by then. |
| `OnServerCommand` | Multiplayer clients, for `sendServerCommand()` from the server. |

### UI

- To add inventory context menu options, handle `Events.OnFillInventoryObjectContextMenu(playerNum, context, items)` and pass `items` through `ISInventoryPane.getActualItems(items)`, which unpacks stacks.
- `ISToolTipInv` also shows things that aren't items, such as fluid containers and energy resources. Check `instanceof(x, "InventoryItem")` before calling item methods.
- `HaloTextHelper` draws only on the local client, so the server sends a command to show halo text in multiplayer.

## Loot

`IsoWorld.init` fires `OnDistributionMerge` and `OnPostDistributionMerge`, then loads the save's sandbox options, then calls `ItemPickerJava.Parse()`, then fires `OnInitGlobalModData`. When a single player game is continued, the merge events therefore see the sandbox options of the default preset. The mod adds its loot in `OnInitGlobalModData` and calls `ItemPickerJava.Parse()` again.

- The chance per roll is ⌈weight × 100 × loot category multiplier + zombie density bonus⌉ in 10,000, and a container rolls `rolls` times (`ItemPickerJava.getActualSpawnChance`). Every positive chance rounds up to at least 1 in 10,000, so at the default multiplier of 0.6 a weight below 1/60 spawns more often than it says. The density bonus is added, not multiplied, so it's the same for every entry whatever its weight. The Lucky and Unlucky traits no longer affect loot.
- `items` lists are flat name and weight pairs, so always append both. Unknown item names are dropped, with a message only in debug logs.
- `junk` lists roll with the loot category multiplier fixed at 1.0 and weights × 1.4, so the loot rarity settings don't scale them. They are often shared by reference (`ClutterTables.*`), so don't add to them.
- A corpse rolls its loot when it's first opened or its square first loads: `SuburbsDistributions.all.Outfit_<outfit>`, and then `inventorymale` or `inventoryfemale` unless the outfit table sets `defaultInventoryLoot = false`. The comment in vanilla `Distributions.lua` that says outfit tables replace the gendered ones is wrong.
- A mod outfit in `clothing.xml` with a vanilla name replaces that outfit, and mod outfits can't reference vanilla clothing (`OutfitManager`), so corpse loot tables are the way to give an outfit items.
- Nothing records a character's age. The `Retiree` outfit is the only sign of it: about 1 in 5 zombies in nursing home, trailer park, rich neighborhood, and golf course zones wear it, and under 1 in 100 elsewhere (`ZombiesZoneDefinition.lua`). Vanilla has no `Outfit_Retiree` table, so the mod creates one.
- No room is a nursing home, audiologist, or hearing aid shop. `MedicalClinicTools` also fills dentist and vet containers, and `KitchenRandom` fills only about 1 kitchen counter in 27.
- Randomized houses also put story clutter on bedside tables from `StoryClutter.SidetableClutter`, an unweighted list that no loot setting scales, so the mod doesn't add to it.

## Art

`art/drawings` holds the GIMP drawings that the item icons, `poster.png`, and `preview.png` come from. Icons are 32×32 pixels, the size of the vanilla icons in `UI2.pack`.

`art/models` builds the 3D models with Blender (made with 5.2). `art/models/make.sh` runs its three scripts in about 5 seconds:

- `build.py` models one behind-the-ear aid for the right ear of the male head, saves it in `hearing_aid.blend`, and paints the four tier textures in `common/media/textures/clothes`, coloured from the icons. The Export collection of the .blend holds linked duplicates of that mesh, named after the files they become: `M_HearingAid_Right`, `M_HearingAid_Left`, `F_HearingAid_Right`, `F_HearingAid_Left`, and `HearingAid_Ground`.
- `export.py` writes those objects to `common/media/models_X`. To keep edits you make by hand in the .blend, run `make.sh --export`, which skips `build.py`; running `build.py` replaces the .blend. The textures are painted from the UV layout that `build.py` creates, so if you change the UVs by hand, repaint the textures too.
- `preview.py` renders each exported object, the worn ones on the matching vanilla head, to `$TMPDIR/hearing-aid-previews`. The heads come from the game install through `vanilla_heads.py`. To model against them, open the .blend with `blender art/models/hearing_aid.blend -P art/models/vanilla_heads.py`; saving leaves the heads out, because they're the game's art.

Then look at the result in the game with `dev/run-debug-client.sh --art`.

- A worn aid is static clothing: its clothing XML sets `m_Static` and attaches the mesh to `Bip01_Head`, so the mesh is modelled in the head bone's frame, where the head is about 0.16 units tall. The female ear sits about 0.004 units further in and further forward than the male one, with its top 0.005 lower, so `m_MaleModel` and `m_FemaleModel` get different meshes, as vanilla earrings do (`M_Earring_Stud_Both.X` and `F_Earring_Stud_Both.X`).
- The game loads meshes through assimp with `MakeLeftHanded` (`FileTask_LoadMesh`) and multiplies a static mesh by its node transforms (`ProcessedAiScene.initMeshTransform`). As an FBX file sees the head bone's frame, x is up, y is the character's left, and z points backward, the opposite of the vanilla `.X` heads read as text. `export.py` turns the mesh into that frame and exports with `bake_space_transform` and `FBX_SCALE_ALL`, which leaves every node transform at the identity. In the front view of the `--art` close-ups, the right ear is on the left of the picture.
- With the 3D ground items option on, which is the default (`3DGroundItem` in `Core`), the game draws an item on the ground from its `WorldStaticModel`. That model rests on y = 0 with y up. The ground model is twice the size of the worn one, so that it's about as long as the vanilla battery's.

## Release checklist

1. Run `dev/validate-server.sh` and `dev/run-debug-client.sh --test`; both must pass. After changing art, also run `dev/run-debug-client.sh --art` and look at the close-ups.
2. Bump `modversion` in `42/mod.info`. Raise `versionMin` when the mod starts depending on a newer game version; lower it only after testing on the older version.
3. Update `workshop.txt` and `README.md`. Workshop tags must come from the game's `media/WorkshopTags.txt`.
4. Upload from the in-game Workshop screen. It uploads `Contents/` and `preview.png`, which must be a square PNG of 256 or 512 pixels and at most 1 MB; the other files at the repository root aren't uploaded.
