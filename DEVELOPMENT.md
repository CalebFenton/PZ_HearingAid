# Developer notes

Facts about Project Zomboid Build 42 that this mod depends on. Each was checked against the decompiled 42.21.0 Java and the vanilla Lua and scripts, and the in-game tests exercise them. Web docs and forum posts lag behind B42 changes, so when they disagree with the game files, the game files win. Re-check anything marked "42.21" after a game update.

## Ground truth

The game ships its Lua, scripts and assets unpacked, and the Java decompiles cleanly.

```sh
PZC="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents"
cat ~/Zomboid/version.txt                     # installed version, e.g. 42.21.0 4a0e9546ec
ln -sfn "$PZC/Java/media" /tmp/pzmedia        # vanilla lua/, scripts/generated/, clothing/, models_X/

# Decompile the zombie.* packages (~20 s) with the bundled Java 25
JAVA="$PZC/PlugIns/jre-aarch64/Contents/Home/bin/java"
mkdir -p /tmp/pztools /tmp/pzclasses /tmp/pzsrc && cd /tmp/pzclasses
curl -sSL -o /tmp/pztools/vineflower.jar https://repo1.maven.org/maven2/org/vineflower/vineflower/1.11.1/vineflower-1.11.1.jar
"$PZC/PlugIns/jre-aarch64/Contents/Home/bin/jar" xf "$PZC/Java/projectzomboid.jar" zombie
"$PZC/PlugIns/jre-aarch64/Contents/Home/bin/jar" cf /tmp/pztools/zombie.jar zombie
"$JAVA" -jar /tmp/pztools/vineflower.jar -dgs=1 -thr=8 -log=WARN "-e=$PZC/Java/projectzomboid.jar" /tmp/pztools/zombie.jar /tmp/pzsrc
```

Where to look:
- Lua globals: `zombie/Lua/LuaManager.java`, `@LuaMethod(name = ...)`. Exposed classes are the `setExposed(X.class)` calls.
- Lua events and where they fire: `zombie/Lua/LuaEventManager.java` lists them. Grep `triggerEvent("Name"` to see who fires each one and on which side.
- Script keys: `zombie/scripting/objects/Item.java` `DoParam`; `zombie/scripting/entity/components/crafting/CraftRecipe.java`, `InputScript.java`, `OutputScript.java`.
- Vanilla patterns: `/tmp/pzmedia/lua/shared/TimedActions/*.lua`, `/tmp/pzmedia/scripts/generated/**`.
- Installed Workshop mods, some already on B42: `~/Library/Application Support/Steam/steamapps/workshop/content/108600/`.

## Mod layout and loading

- B42 only lists a mod folder that has `common/mod.info` or `<versionDir>/mod.info`. Files at the mod root (our B41 release) are ignored by B42, and B41 ignores `common/` and `42/`.
- **Version folder.** The game picks the child folder with the highest numeric name that is ≥ 42.0 and ≤ the game version, comparing major·1000+minor and ignoring the patch number. `42` works for every 42.x.
- **Load order.** `common/media` loads first; the version dir overrides files at the same relative path. A mod Lua file at the same relative path as a vanilla file replaces the vanilla file, so give files unique names.
- **mod.info.** Keys are parsed by `startsWith`/`contains`: `name, id, author, description, poster, icon, modversion, versionMin, versionMax, require, url, pack, tiledef, ...`.
  - `versionMin`/`versionMax` are the only compatibility gate (`ChooseGameInfo.Mod.isAvailableSelf`). The mod list's info panel shows them as `min - max`, in red when unmet, and a mod outside the range isn't loaded.
  - The "unsupported mods" filter only hides mods built for versions before 42.0 (`Core.getBreakModGameVersion()`).
- **Where the game finds mods.**
  - With Steam: `~/Zomboid/mods/*` and `~/Zomboid/Workshop/*/Contents/mods/*` (staging), plus subscriptions.
  - With `-nosteam`: only `<cachedir>/mods`.
  - Two copies with the same `id` conflict.
- `media/registries.lua` (version dir, else common; only one runs) executes **before scripts load**, and again on every Lua reset. It's the only place to register namespaced ids such as `ItemBodyLocation.register("hearingaid:hearingaid")`. The `base:` namespace is rejected, and ids are lowercased.

## Scripts (`media/scripts/*.txt`)

- **Item type.** Use `ItemType = base:clothing` (or `base:normal`, `base:drainable`, ...). The B41 key `Type = Clothing` is stored as unknown modData and leaves the item with no class, which breaks it.
- **Names.** `DisplayName` is overwritten from `ItemName.json` (key `Module.Item`); vanilla items have no DisplayName at all.
- **Body location.** A new `BodyLocation` must be registered in registries.lua **and** added to the "Human" group from shared Lua (`BodyLocations.getGroup("Human"):getOrCreateLocation(loc)`). Otherwise wearing the item throws a NullPointerException in `WornItems.setItem`. Add it to `WearClothingAnimations` too. See `NPCs/HearingAid_BodyLocations.lua`.
- **Models.** A bare model name in `WorldStaticModel` resolves only in `module Base` (`ScriptBucketCollection.getScript`), so model scripts live in `module Base` with unique names.
- **Clothing XML.** The XML file name must equal the item's `ClothingItem`. `media/fileGuidTable.xml` maps its path to a GUID; that GUID is what the lookup uses. Keep it equal to the XML's `m_GUID`.
- **Comments.** Only `/* */` works in script files; `//` and `--` don't.
- **Item `OnCreate = Some.Lua.func`.**
  - Called as `func(item)` on **every** instantiation: loot, crafting outputs, debug spawns, save loading, and MP clients receiving the item.
  - `item:load()` then wipes modData and replaces it, **but only if the saved item had non-empty modData**, so always write at least one key (`HearingAid_v`).
  - Uses set on Drainables in OnCreate are overwritten afterwards.
- **Loot category.** `Medical = true` puts the item under the Medical loot rarity setting; otherwise clothing counts as Clothing. `Tags = base:ignorezombiedensity` keeps the zombie-density bonus (up to +0.8% per roll) from swamping small weights.
- **`ChanceToFall`.** Adds 40 when the head is hit (`IsoGameCharacter.helmetFallFromWornItems`), so even 5 means 45% on a head hit.

### craftRecipe

- Old `recipe` blocks are dead.
- **Silent failures:** lines without `=` (B41 `Time:30`) are skipped silently. Unknown keys log an error, and throw in debug.
- Input flags (`flags[...]`) are case-sensitive enum names. `[...]` lists must not contain spaces.
- Use `tags[base:screwdriver]` for tool tags and `mode:keep` for tools.
- `xpAward = Electricity:10` and `SkillRequired = Electricity:2` replace B41 `OnGiveXP` and `SkillRequired:`.
- **Callbacks** (resolve dotted Lua paths, except OnAddToMenu):
  - `OnCreate(craftRecipeData, character)` runs once: locally in SP, on the server in MP, **after** outputs were already sent to the client, so call `result:syncItemFields()` if you change them.
  - `OnTest(item, character)` runs for **every** candidate input item, tools included.
  - `OnAddToMenu(params)` must be a **plain global name**; it's fetched with a raw `_G` read.
- **CraftRecipeData API:**
  - `getAllConsumedItems()` excludes `mode:keep` inputs; `getFirstCreatedItem()` returns the output.
  - No flag copies modData; copy it yourself.
  - Vanilla adds per-input counter keys to the result's modData after OnCreate.
- **Sandbox gating.** Recipes can't be toggled at runtime. Gate with OnTest (blocks crafting, including on the server) plus OnAddToMenu (hides the recipe).
- B41 `fixing` blocks still parse, but only with `=` (`Require = ...`, `Fixer = ...`).

### sandbox-options.txt

`VERSION = 1,` is required. Types are `boolean, integer, double, enum, string`.

Translation keys:
- `Sandbox_<translation>` and `Sandbox_<translation>_tooltip`
- `Sandbox_<valueTranslation>_option<N>` for enum values (1-based)
- `Sandbox_<page>` for the page title

Read values in Lua as `SandboxVars.<Table>.<Key>`.

## Translations

- **JSON only.** Files: `media/lua/shared/Translate/<LANG>/<File>.json`. `.txt` translation files are ignored.
- **File names that load:** `ItemName, Recipes, IG_UI, Tooltip, ContextMenu, Sandbox, UI, ...` (`Translator.java`).
- **Keys:**
  - Items: `"Module.Item"`.
  - craftRecipes: the bare recipe name.
  - Prefixed keys go in the matching file, e.g. `IGUI_` → IG_UI, `Tooltip_` → Tooltip.
- **Syntax:** strict JSON in dev builds (no comments or trailing commas). Write `%%` for a literal percent.
- Reuse vanilla keys (`ContextMenu_Turn_On`, `ContextMenu_AddBattery`, `ContextMenu_Remove_Battery`, ...) to get every language for free.

## Lua runtime

### Who runs what

| Context | `isClient()` | `isServer()` | Notes |
|---|---|---|---|
| Single player | false | false | Client, shared and server Lua all run in one state |
| MP client | true | false | **Server Lua also loads on clients**; guard handlers with `if isClient() then return end` |
| Dedicated server | false | true | Client Lua is checksummed only, never run |

### State and syncing

- **Traits.**
  - API: `player:hasTrait(CharacterTrait.HARD_OF_HEARING)`, `player:getCharacterTraits():add/remove(CharacterTrait.X)`. B41's `getTraits()` is gone.
  - Traits are **server-authoritative**. A regular client can't push them (`SyncXp` needs admin rights). Change them on the server, then `sendSyncPlayerFields(player, 2)`.
  - Hearing effects read the trait flags directly: audio muffling (`ParameterHardOfHearing`), hear distance and detection range. An item's `HearingModifier` is per script, not per instance, so it can't follow the battery.
- **Item modData.** `syncItemFields(player, item)`, or `item:syncItemFields()`, from the server sends modData, uses and condition to the owner.
- **Adding and removing items on the server.** `Actions.addOrDropItem(character, item)` (adds and syncs), `container:Remove(item)` then `sendRemoveItemFromContainer(container, item)`. These no-op outside the server.
- **Player modData is not safe on the server.**
  - Clients send their whole player modData to the server (`transmitModData`), and it **replaces** the server's copy. ISHotbar does this right after every clothing change.
  - Anything the server writes there can vanish. `HearingAid.lua` keeps a server-side copy keyed by username and tied to the IsoPlayer object, and restores it.
- **Batteries.**
  - Create with `instanceItem("Base.Battery")`; `InventoryItemFactory` isn't exposed to Lua.
  - Charge is `getCurrentUsesFloat()` / `setCurrentUsesFloat()`. `getUsedDelta()` no longer exists on drainables; `setUsedDelta` is a deprecated alias.
  - A full Battery is 142 uses ≈ 0.994.

### Timed actions (MP)

- If the class has `complete()`, the client runs `start/update/perform` and the **server** runs `complete()`. In SP, `perform()` then `complete()` run back to back.
- **Rebuilding on the server:**
  - The server rebuilds the action by calling `<Class>.new` with the values of the fields **named like `new`'s parameters**, in order.
  - Parameter names must equal the field names, and every argument must be serializable. InventoryItems are sent as container + id and must be in a container.
  - Unsupported types are dropped and shift the remaining arguments.
- **Validation:** the server never calls `isValid`/`update`/`perform`, so re-validate in `complete()`. Returning `false` rejects the action.
- **Item references:** on the client, re-fetch items by id in `start()`, as vanilla does; server syncs can replace the objects.

### Events

| Event | Fires |
|---|---|
| `EveryOneMinute`, `EveryTenMinutes` | SP, MP client, server. At most once per tick even if more time passed, so use `getGameTime():getWorldAgeHours()` deltas. |
| `OnPlayerUpdate` | Local players only, **never** on a dedicated server |
| `OnClothingUpdated` | Client after wear/unwear. On the server only from unequip, transfer and drop, **not** from `ISWearClothing:complete()`. Relay with `sendClientCommand`. |
| `OnClientCommand` | Server (also SP via `SinglePlayerClient`) |
| `OnInitGlobalModData` | SP and server, after the save's sandbox options are loaded. Used for loot (see below). |
| `OnCharacterDeath` | `IsoGameCharacter.OnDeath`, for zombies, animals and players; `OnPlayerDeath` is local players only |

### UI

- **Inventory context menu:** `Events.OnFillInventoryObjectContextMenu(playerNum, context, items)`. Normalize `items` with `ISInventoryPane.getActualItems(items)`, which handles stacks.
- **Tooltips:** `ISToolTipInv` is also used for **non-items** (fluid containers, energy resources). Check `instanceof(x, "InventoryItem")` before calling item methods.
- **Halo text:** `HaloTextHelper` is client-local; send a server command to show it in MP.

## Loot

- **Timing.**
  - `OnPre/OnPost/DistributionMerge` fire **before** the save's sandbox options load when continuing a single-player game (`IsoWorld.init`). Sandbox-scaled weights inserted there use preset defaults.
  - Insert in `OnInitGlobalModData`, then call `ItemPickerJava.Parse()`.
- **Odds per roll:** `(weight × 100 × lootCategoryMultiplier + zombieDensityBonus) / 10000`, with `rolls` rolls per container. Lucky/Unlucky no longer affect loot.
- **Table formats.**
  - `items` lists are flat name/weight pairs; always append both.
  - `junk` tables are often shared by reference (`ClutterTables.*`); don't add to them.
  - Unknown item names are dropped silently, except in debug logs.
- **Corpses:** `SuburbsDistributions.all.Outfit_<outfit>` rolls in addition to `inventorymale/female` unless `defaultInventoryLoot = false`. `Outfit_Retiree` doesn't exist in vanilla; we create it.

## Testing

All of this is vanilla debug tooling; see the README for the commands.

- **Debug mode.** Client: the `-debug` argument (or `-Ddebug`). Server: only the JVM property `-Ddebug`; the server has no `-debug` argument.
- **Debug scenarios.**
  - Register them in the global `debugScenarios` table from client Lua. **`startLoc` is required** or world creation crashes.
  - Call `ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))` in `setSandbox`, or the new save won't record its mods.
  - `forceLaunch = true` only auto-starts when `DebugScenario.ForceLaunch=true` is in `<cachedir>/debug-options.ini`.
- **Unit tests.**
  - `TimedActionTests.getTests()` returns the live table; add `{ run = fn, validate = fn }` entries at file load.
  - The Unit Tests debug panel must be **open** before `TimedActionTests.runOne(name)`, or it errors on its result labels. `UnitTestsDebug.OnOpenPanel()` opens it.
  - The runner wipes inventory and worn items before each test, but **not** traits or player modData.
- **Crafting from a test:** `ISInventoryPaneContextMenu.OnNewCraft(selectedItem, getScriptManager():getCraftRecipe("Module.Name"), playerNum, false)` is the real right-click craft path.
- **Starting a fresh profile.**
  - "Click to start" after loading needs a **real mouse click** (`GameLoadingState` reads `Mouse.isButtonDown(0)`; there's no skip).
  - Synthetic macOS events need Accessibility permission, and `screencapture` needs Screen Recording.
  - A fresh `-cachedir` stops at the terms of service unless `options.ini` has `termsOfServiceVersion=1` (the client script copies your `options.ini`).
- **Screenshots without macOS permissions:** `getCore():TakeFullScreenshot("name.png")` writes to `<cachedir>/Screenshots/`.
- **Dedicated server:** boots in about 20 s with `-nosteam -cachedir=... -servername ... -adminpassword ...` and a `Server/<name>.ini` containing `Mods=`. Type `quit` on stdin to stop it.
- **Known debug-log noise:** a `NoSuchFileException` for `media/AnimSets` / `media/actiongroups` appears for every mod that lacks those folders, plus vanilla errors (fonts, `FluidContainerScript`, mannequin zone, missing tiles).
- **Loot rates:** the vanilla Generate Loot tool (debug right-click → UI → Generate Loot UI, `ISLootStressTestUI.lua`) simulates whole houses.

## Release checklist

1. `dev/validate-server.sh` and `dev/run-debug-client.sh --auto`: everything passes.
2. Bump `modversion` in `42/mod.info`. Raise `versionMin` when you depend on something new; lower it only after testing on that version.
3. Update `workshop.txt` (tags must come from `media/WorkshopTags.txt`) and README.
4. Upload from the in-game Workshop screen. It uploads `Contents/` and `preview.png` (square, 256 or 512 px, ≤ 1 MB); the repo root isn't uploaded.
