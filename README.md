# Hearing Aid

![Hearing Aid poster](preview.png)

Battery-powered hearing aids for Project Zomboid. While you wear a working aid that's switched on, a Hard of Hearing character hears normally and a Deaf one hears a little. A boosted aid gives anyone Keen Hearing.

**Status**: Requires Build 42.21 or newer. Tested in single player on 42.21.0. Multiplayer is untested: the server owns battery drain and hearing traits, and the mod loads on a dedicated server, but nobody has played it with clients connected.

## Install

Subscribe on the [Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2931424725) and enable **Hearing Aid** in the mod list. Build 41 loads the original release, which this repository keeps unchanged in `Contents/mods/HearingAid/media`.

## How it works

An aid changes your hearing only while it works, holds a charged battery, sits on your ear, and is switched on:

1. Find a working aid, or find a broken one and [repair it](#crafting).
2. Right-click the aid and choose **Add Battery**. It takes the same Battery as a flashlight, and the menu lists yours by charge.
3. Wear the aid, right-click it, and choose **Turn On**.

The battery drains only while the aid is worn and switched on, so switch it off when you don't need it. The tooltip shows the charge and whether the aid is on. When you take the aid off, switch it off, or the battery runs flat, you hear as you did before. **Remove Battery** gives the battery back with whatever charge it has left.

| Aid | Hard of Hearing becomes | Deaf becomes | A battery lasts |
|---|---|---|---|
| Hearing Aid | Normal hearing | Hard of Hearing | 2 days |
| Efficient Hearing Aid | Normal hearing | Hard of Hearing | 6 days |
| Boosted Hearing Aid | Keen Hearing | Normal hearing | 4 days |

Battery life counts in-game time spent worn and switched on. A boosted aid also gives Keen Hearing to a character whose hearing is normal. A Broken Hearing Aid does nothing until you repair it.

### Finding one

Most hearing aids in Knox County are still in their owners' ears, and the owners won't mind if you take them. About 1 in 65 zombies carries one. So do 1 in 10 zombies dressed as retirees, who crowd nursing homes, trailer parks, golf courses, and rich neighborhoods, and 1 in 20 hospital patients. These rates follow a [1994 US survey](https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Publications/DVD/DVD_1/Advance_Data/ad292.pdf) in which 1 in 60 Americans used a hearing aid, and 1 in 10 of those over 65.

Off the ear, search nightstands and bathroom cabinets first, then dressers, living room side tables, boxes of old electronics, hospital bedside tables, waiting room desks, lost and found boxes, and doctors' desks. Pharmacies, optical stores, and electronics stores didn't sell hearing aids in 1993, so they have none.

Four in five aids you find are broken, and only about 1 in 150 is efficient. A working aid may still hold a partly used battery. Hearing aids count as Medical loot, so the Medical loot rarity setting scales them too.

### Crafting

Every recipe needs a screwdriver, light, and an aid you aren't wearing. Repaired and upgraded aids keep the battery and the switch of the aid they came from, and dismantling an aid gives its battery back.

| Recipe | Electrical | Turns | Also uses |
|---|---|---|---|
| Repair Hearing Aid | 2 | a Broken Hearing Aid into a Hearing Aid | 2 Scrap Electronics |
| Optimize Hearing Aid | 4 | a Hearing Aid into an Efficient Hearing Aid | 2 Scrap Electronics, Aluminum Foil or Aluminum Fragments |
| Boost Hearing Aid | 8 | an Efficient Hearing Aid into a Boosted Hearing Aid | 4 Scrap Electronics, Earbuds, an Amplifier, Electrical Wire, and a Scalpel, which it keeps |
| Dismantle Hearing Aid | None | any hearing aid into Scrap Electronics | Nothing else |

Dismantling a Speaker gives an Amplifier.

### Sandbox options

The **Hearing Aid** page of the sandbox options sets the battery life of each tier, the Electrical level each recipe needs, separate loot multipliers for broken and working aids, the chance that a found aid holds a battery, how aids help Deaf characters, and whether boosted aids can be crafted. Everything above describes the defaults.

## Development

Clone the repository to `~/Zomboid/Workshop/HearingAid`. With Steam running, the game lists Workshop staging folders as local mods. Unsubscribe from the Workshop copy while you develop, because two copies with the same mod id conflict. The scripts assume the macOS Steam install; set `PZ_APP` to the game's `Contents` folder if yours differs.

```sh
dev/validate-server.sh           # boots a headless dedicated server; fails if the mod logs an error
dev/run-debug-client.sh --test   # runs every in-game test; click "Click to start" once
```

Read [DEVELOPMENT.md](DEVELOPMENT.md) for the testing tools, the Build 42 behavior this mod depends on, and the release checklist.
