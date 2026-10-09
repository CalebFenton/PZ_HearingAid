# ![Hearing Aid: battery-powered hearing aids for Project Zomboid Build 42](art/promo/images/banner.png)

Battery-powered hearing aids for Project Zomboid. Wear a working aid and switch it on, and a Hard of Hearing character hears normally while a Deaf one hears a little. A boosted aid gives Keen Hearing to anyone who isn't Deaf.

**Status**: Requires Build 42.21 or newer. Tested in single player on 42.21.0. Multiplayer is untested: the server owns battery drain and hearing traits, and the mod loads on a dedicated server, but nobody has played it with clients connected.

## Install

Subscribe on the [Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2931424725) and enable **Hearing Aid** in the mod list. Build 41 loads the original release, which this repository keeps unchanged in `Contents/mods/HearingAid/media`.

## The aids

<p align="center"><img src="art/promo/images/tiers.png" alt="Each of the four aids as a 3D model, worn behind a right ear, and as an inventory icon" width="100%"></p>

| Aid | Hard of Hearing becomes | Deaf becomes | A battery lasts | How you get one |
|---|---|---|---|---|
| Broken Hearing Aid | no change | no change | | Most aids you find are broken |
| Hearing Aid | Normal hearing | Hard of Hearing | 2 days | Find one, or repair a broken one |
| Efficient Hearing Aid | Normal hearing | Hard of Hearing | 6 days | A lucky find, or optimize a hearing aid |
| Boosted Hearing Aid | Keen Hearing | Normal hearing | 4 days | Boost an efficient aid |

A boosted aid also gives Keen Hearing to a character whose hearing is normal.

## Wearing one

<p align="center"><img src="art/promo/images/ears.png" alt="A man wearing a hearing aid on his right ear and a woman wearing one on her left, above the Wear menu with its on Right Ear and on Left Ear options" width="100%"></p>

To hear better, you need a working aid with a charged battery, on your ear and switched on:

1. Find a working aid, or find a broken one and [repair it](#crafting).
2. Right-click the aid and choose **Add Battery**. It takes the same Battery as a flashlight, and the menu lists yours by charge.
3. Right-click the aid, choose **Wear**, and pick **on Right Ear** or **on Left Ear**. Then right-click it again and choose **Turn On**. The same menu moves a worn aid to your other ear.

<p align="center"><img src="art/promo/images/interface.png" alt="Tooltips of a switched-off Hearing Aid with 40% battery, a switched-on Boosted Hearing Aid with 73%, and a Broken Hearing Aid" width="100%"></p>

The battery drains only while the aid is worn and switched on, so switch it off when you don't need it. The tooltip shows the charge and whether the aid is on. Take the aid off, switch it off, or let the battery run flat, and you hear as you did before. **Remove Battery** gives the battery back with whatever charge it has left.

## Finding one

<p align="center"><img src="art/promo/images/corpse.png" alt="A grey-haired survivor next to a corpse whose loot window lists a Hearing Aid" width="100%"></p>

Most hearing aids in Knox County are still in their owners' ears, and the owners won't mind if you take them. Roughly 1 in 5 zombies carries one, and 1 in 14 carries one that works. Retirees carry them most. They crowd nursing homes, trailer parks, golf courses, country clubs, and rich neighborhoods, where about 1 in 5 zombies is dressed as one. Hospital patients come next.

| Corpse | Any hearing aid | A working one | A wristwatch |
| --- | --- | --- | --- |
| Most zombies | 1 in 5.5 | 1 in 14 | 1 in 3.4 |
| Zombies dressed as retirees | 1 in 1.8 | 1 in 4 | 1 in 3.3 |
| Hospital patients | 1 in 2.7 | 1 in 6.8 | none |
| Any zombie in a nursing home | 1 in 3.6 | 1 in 8.6 | 1 in 5 |
| Any zombie in a trailer park | 1 in 3.9 | 1 in 9.3 | 1 in 3.2 |
| Any zombie on a golf course | 1 in 3.8 | 1 in 9.3 | 1 in 3.2 |
| Any zombie at a country club | 1 in 4 | 1 in 9.4 | 1 in 3.3 |
| Any zombie in a rich neighborhood | 1 in 4 | 1 in 10 | 1 in 3.3 |
| Any zombie in a hospital room | 1 in 3.9 | 1 in 10 | 1 in 6.2 |

Off the ear, hospital bedside wardrobes hold the most, then doctors' desks, which hold only working aids, lost and found boxes, and waiting room desks. In houses, look in bedside tables, dressers, living room side tables, and bathrooms, and in boxes of old electronics. Pharmacies, optical stores, and electronics stores didn't sell hearing aids in 1993, so they have none.

| Container | Any hearing aid | A working one | A wristwatch |
| --- | --- | --- | --- |
| Hospital bedside wardrobe | 1 in 15 | 1 in 33 | 1 in 800 |
| Doctor's desk | 1 in 45 | 1 in 45 | 1 in 51 |
| Lost and found box | 1 in 45 | 1 in 121 | none |
| Waiting room desk | 1 in 77 | 1 in 182 | 1 in 73 |
| Bedside table | 1 in 83 | 1 in 211 | 1 in 55 |
| Dresser | 1 in 85 | 1 in 200 | 1 in 51 |
| Living room side table | 1 in 111 | 1 in 308 | 1 in 59 |
| Bathroom counter | 1 in 190 | 1 in 444 | none |
| Bathroom cabinet | 1 in 167 | 1 in 308 | none |
| Box of electronics | 1 in 174 | none | none |

The tables give the chance for a single corpse or container at the default sandbox settings, measured over 4,000 of each with the game's own loot rolls, so the rarer numbers are rough. Wristwatches are there for scale. About 3 in 5 aids you find are broken, and about 1 in 90 is efficient. Half the working ones still hold a partly used battery. Hearing aids count as Medical loot, so the Medical loot rarity setting scales them too.

## Crafting

<p align="center"><img src="art/promo/images/recipes.png" alt="The tools every recipe needs, and the inputs and result of the Repair, Optimize and Boost recipes" width="100%"></p>

Repairs and upgrades are fiddly work. You need a table or counter within reach, enough light to see by, a screwdriver, tweezers, and reading glasses or a magnifier (a Loupe or a Magnifying Glass). You can wear the glasses while you work, but the aid has to come off your ear. The new aid keeps the old one's battery, and stays switched on if it was on.

| Recipe | Electrical | Makes | Uses up |
|---|---|---|---|
| Repair Hearing Aid | 2 | Hearing Aid from a Broken Hearing Aid | Earbuds, 1 use of Alcohol Wipes or Cotton Balls Doused in Alcohol, 1 use of Glue |
| Optimize Hearing Aid | 4 | Efficient Hearing Aid from a Hearing Aid | a Digital Watch, Electrical Wire, 1 use of Glue |
| Boost Hearing Aid | 8 | Boosted Hearing Aid from an Efficient Hearing Aid | Amplifier, Microphone, 2 Electrical Wire, 1 use of Epoxy |

Boosting also needs a Scalpel, which you keep.

The parts make sense if you squint: the earbuds give up their tiny speaker, the alcohol cleans the corroded battery contacts, and the watch donates its low-power chip. Everything a repair needs turns up in ordinary houses. A boost takes more hunting: dismantle a Speaker for its Amplifier, and look for a Microphone in music stores, band practice rooms, and electronics stores.

**Dismantle Hearing Aid** needs only a screwdriver and no table. It turns any aid into Scrap Electronics and gives its battery back.

## Sandbox options

The **Hearing Aid** page of the sandbox options sets the battery life of each tier, the Electrical level each recipe needs, separate loot multipliers for broken and working aids, the chance that a found aid holds a battery, how aids help Deaf characters, and whether boosted aids can be crafted. Everything above describes the defaults.

## Development

Clone the repository to `~/Zomboid/Workshop/HearingAid`. With Steam running, the game lists Workshop staging folders as local mods. Unsubscribe from the Workshop copy while you develop, because two copies with the same mod id conflict. The scripts assume the macOS Steam install; set `PZ_APP` to the game's `Contents` folder if yours differs. The in-game tests also need a JDK (any version from 8 on) for `javac`.

The source art lives in `art/`: GIMP drawings for the icons and the poster in `art/drawings`, and in `art/models` the Blender file and the Python scripts that build the 3D models and their textures. Rebuilding the models needs [Blender](https://www.blender.org/). `art/promo` holds the art for this README and the Workshop page: raw captures from the game in `captures`, and the images that `compose.py` lays out from them in `images`. Its scripts run with [uv](https://docs.astral.sh/uv/).

```sh
dev/validate-server.sh            # boots a headless dedicated server; fails if the mod logs an error
dev/run-debug-client.sh --test    # runs every in-game test unattended in about 2 minutes
dev/run-debug-client.sh --art     # saves in-game close-ups of the worn and dropped aids
dev/run-debug-client.sh --promo   # captures the art for this README and measures the loot
art/promo/compose.py              # lays out the images and prints the loot tables
art/models/make.sh                # rebuilds the models and textures with Blender
```

Read [DEVELOPMENT.md](DEVELOPMENT.md) for the testing tools, the Build 42 behavior this mod depends on, and the release checklist.
