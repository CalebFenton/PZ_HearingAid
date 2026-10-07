# Hearing Aid

![Hearing Aid poster](preview.png)

Battery-powered hearing aids for Project Zomboid. Deaf and Hard of Hearing characters can find one, fix it up, and hear better while it's switched on.

**Status**: Requires Build 42.21 or newer. Tested in single player on 42.21.0. Multiplayer is untested: the server owns battery drain and hearing traits, and the mod loads on a dedicated server, but nobody has played it with clients connected.

## Install

Subscribe on the [Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2931424725) and enable **Hearing Aid** in the mod list. Build 41 loads the original release, which this repository keeps unchanged in `Contents/mods/HearingAid/media`.

## How it works

Most hearing aids lying around are broken. Repair one with a screwdriver and electronics scrap, or get lucky and find one that still works. A working aid needs a battery and only helps while it's worn, switched on, and charged, which is also the only time it drains. Taking it off, switching it off, or running the battery flat gives the character their own hearing trait back. Right-click an aid to add or remove a battery or to switch it on or off; its tooltip shows the charge.

The tiers differ in how you get them, what they do, and their default battery life:

| Item | How you get it | Effect | Battery life |
|---|---|---|---|
| Broken Hearing Aid | Most found aids | None | None |
| Hearing Aid | About 1 in 5 found aids, or repair a broken one (Electrical 2) | Hard of Hearing becomes normal hearing; Deaf becomes Hard of Hearing | 48 hours |
| Efficient Hearing Aid | About 1 in 20 found aids, or optimize a hearing aid (Electrical 4) | Same as Hearing Aid | 144 hours |
| Boosted Hearing Aid | Upgrade an efficient aid (Electrical 8) | Keen Hearing; Deaf becomes normal hearing | 96 hours |

Upgrades keep the battery, and dismantling an aid gives it back.

People wore their hearing aids, so most turn up on corpses. At default settings about 1 in 65 ordinary zombies carries one, against the 1 in 7 that wear a digital watch, and so do 1 in 10 retirees and 1 in 20 hospital patients. These rates follow a 1994 US survey in which 1 in 60 people used a hearing aid, and 1 in 10 people over 65. Off the ear, aids lie on nightstands and in bathroom cabinets, and less often in dressers, living room side tables, and boxes of old electronics. Hospital bedside tables, waiting room desks, and lost and found boxes hold aids that patients left behind, and doctors' desks hold new ones. Pharmacies, optical stores, and electronics stores didn't sell hearing aids in 1993, so they have none. Hearing aids count as Medical loot for the loot rarity setting.

The **Hearing Aid** sandbox page sets the battery life of each tier, the chance that a found aid still holds a battery, separate loot multipliers for broken and working aids, the Electrical level each recipe needs and how aids help Deaf characters (the table shows the defaults), and whether boosted aids can be crafted.

## Development

Clone the repository to `~/Zomboid/Workshop/HearingAid`. With Steam running, the game lists Workshop staging folders as local mods. Unsubscribe from the Workshop copy while you develop, because two copies with the same mod id conflict. The scripts assume the macOS Steam install; set `PZ_APP` to the game's `Contents` folder if yours differs.

```sh
dev/validate-server.sh           # boots a headless dedicated server; fails if the mod logs an error
dev/run-debug-client.sh --test   # runs every in-game test; click "Click to start" once
```

Read [DEVELOPMENT.md](DEVELOPMENT.md) for the testing tools, the Build 42 behavior this mod depends on, and the release checklist.
