# [REAL] STEEL

**Tanks, aircraft and infantry fighting over a war-torn town.** A free, low-poly combined-arms
shooter for Windows, made in the Godot engine, with bots and online play with friends.

![A soldier watches an Apache chase a MiG while an ADATS fires at them](resume-shots/trailer/01-air-defence.png)

| | |
|---|---|
| ![Tank column in town](resume-shots/trailer/02-armour-column.png) | ![Tank firing at dusk](resume-shots/trailer/03-dusk-gun.png) |
| ![Gepard firing at a diving plane](resume-shots/trailer/04-gepard.png) | ![RPG ambush](resume-shots/trailer/06-ambush.png) |

---

## What is it?

Two teams, Blue and Red, fight over one detailed town set in open country. You choose how to fight
each time you deploy:

- **Drive a tank.** Ten vehicles, from heavy tanks and tank destroyers to artillery, a repair vehicle
  and two anti-aircraft vehicles (the Gepard gun tank and the ADATS missile carrier). Armour,
  penetration, ricochets, modules that break (tracks, gun, engine, ammo) and a gunner's sight.
- **Fly.** Two helicopters (Apache, Mi-8), two jets (Sabre, MiG-15) and two propeller attack planes
  (Skyraider, Il-10), with rockets, bombs, heat-seeking missiles, flares and cockpits.
- **Fight on foot.** Five classes (assault, machine gunner, medic, RPG gunner, engineer) in first or
  third person, with a squad that follows you.

Game modes: **Push** (escort the robot), **Team Deathmatch** and **Domination** (hold three points),
plus a shooting range. There are bots for both teams, a garage with camo and loadouts, levels and XP.

---

## Quick start (for people who know their way round a PC)

1. Go to the **[Releases page](../../releases/latest)** and download **`REAL-STEEL-Setup.exe`**
   (about 80 MB). It contains everything, the Godot engine included: there is **nothing else to
   install**. (The code on this page is for people who want to change the game; see "For developers".)
2. Run it. If SmartScreen says "Windows protected your PC": **More info** > **Run anyway**
   (see [Is this safe?](#is-this-safe) below for why it says that).
3. Click through the installer (no administrator password needed). It adds a desktop and a Start
   menu shortcut. Play from either.
4. **F11** (or Alt+Enter) for full screen. For online play, have Steam running, then
   **MULTIPLAYER** > **FIND LOBBIES** (or **OPEN LOBBY** to host).
5. To remove it: Windows **Settings** > **Apps** > **Installed apps** > **[REAL] STEEL** > **Uninstall**.

Prefer no installer? Download `SteelPush-for-friends.zip` instead, Extract All, and run
`REAL STEEL` from the `game` folder. Delete the folder to remove it.

Windows 10 or 11, 64-bit, with a graphics card from roughly the last ten years.

---

## Step-by-step (if you have never used a PC for much more than Google and memes)

Don't worry, nothing here can break your computer, and you can remove the game again in a few
clicks (step 8). Take it one step at a time.

**1. Download the game**

- On this page, click the link that says **Releases page** in the Quick start above.
  (Or look on the right-hand side of the repository's main page for **Releases**.)
- You will see a heading like "v1.0" and a list called **Assets** under it.
- Click **REAL-STEEL-Setup.exe**. Your browser downloads it. It is about 80 MB, so give it a
  minute. (If your browser asks whether to keep the file, choose **Keep**.)

**2. Start the installer**

- When the download finishes, click it in your browser's download list (usually a small arrow or
  list at the top right of the browser). Or press the **Windows key** and **E** together to open
  File Explorer, click **Downloads** on the left, and double-click **REAL-STEEL-Setup**.

**3. Get past the blue warning (only the first time)**

- Windows may show a blue box saying **"Windows protected your PC"**. That just means Windows
  has not seen this game many times yet (see [Is this safe?](#is-this-safe)).
- Click the small words **More info**, then the button **Run anyway**.

**4. Install**

- A window called **Setup - [REAL] STEEL** opens. Leave the tick on
  **"Put a REAL STEEL shortcut on the desktop"** and click **Next**, then **Install**.
- When it says it has finished, leave **"Play REAL STEEL now"** ticked and click **Finish**.
- From now on, just double-click **REAL STEEL** on your desktop to play.

**5. Play**

- The game opens in a window. Press **F11** on your keyboard to make it fill the whole screen
  (press F11 again to go back to a window).
- Click **SINGLE PLAYER** to play against bots straight away.
- Pick what you want to be (tank, aircraft or soldier) on the deploy screen and click **DEPLOY**.
- Press **Esc** at any time for the pause menu (settings, redeploy, quit).

**6. Play with friends online**

- Everyone needs **Steam** installed, open and signed in (it's free from store.steampowered.com).
- Everyone needs the **same version** of the game, so everyone installs the same release.
- One person clicks **MULTIPLAYER** > **OPEN LOBBY**. Everyone else clicks **MULTIPLAYER** >
  **FIND LOBBIES** and clicks that lobby.
- Steam will say you are playing "Spacewar". That's normal: it is Steam's free test app, which the
  game borrows until it has a Steam page of its own.

**7. Getting a newer version later**

- Download the new `REAL-STEEL-Setup.exe` from the Releases page and run it. It updates the game
  in place. Your settings and progress are kept.

**8. Uninstalling (removing the game)**

- Click the **Start** button (the Windows logo), then **Settings** (the gear).
- Click **Apps**, then **Installed apps**.
- Find **[REAL] STEEL** in the list, click the **three dots** next to it, and click **Uninstall**.
  The game, its shortcuts and its entry in the list are all removed.
- (Your settings and progress stay in a small folder in case you reinstall. To remove those too,
  press Windows key + R, type `%APPDATA%\Godot\app_userdata` and press Enter, then delete the
  **[REAL] STEEL** folder.)

---

## Is this safe?

Being careful about running programs from the internet is exactly right. Here is what you can check:

- **All of the game's code is on this page.** Nothing is hidden: the installer is built from these
  files plus the official, unmodified Godot 4.7.2 engine (renamed to `REAL STEEL.exe`).
- **The installer only touches its own folder.** It installs for your Windows user only (no
  administrator password), into `%LOCALAPPDATA%\Programs\REAL STEEL`, and uninstalls cleanly.
- **Check the file is the real one.** Each release lists the file's SHA-256 fingerprint. In File
  Explorer, Shift + right-click the downloaded file > **Open in Terminal**, type
  `Get-FileHash .\REAL-STEEL-Setup.exe` and compare the long code with the one on the release page.
- **Scan it yourself.** Upload the file to [virustotal.com](https://www.virustotal.com), which checks
  it with about 70 antivirus programs at once.
- **Why the blue Windows warning?** Windows shows it for programs that are not "code signed" with a
  paid certificate, or that few people have downloaded yet. It is not a virus warning. The game may
  be signed in future.

---

## Controls

All keys can be changed on the **CONTROLS** page of the menu.

| In a tank | | On foot | | In the air | |
|---|---|---|---|---|---|
| W A S D | drive | W A S D | move | Mouse | steer / aim |
| Mouse | aim the turret | Left mouse | fire | W / S | throttle (planes), move (helicopters) |
| Left mouse | fire main gun | Right mouse | aim down sights | Space / Ctrl | climb / descend (helicopters) |
| Right mouse | gunner's sight | Shift | sprint | Left mouse | guns |
| Space | machine gun | Ctrl | crouch | Right mouse | rockets (jets: hold to lock a missile) |
| R | set the range | Z | lie down | F | drop a bomb |
| E | vehicle ability | Space | jump / vault | G | flares |
| C | free look | R | reload | V | cockpit view |
| G | radar on / off (AA) | G | grenade | C | free look |
| T | emotes | 1 2 3 | rifle, pistol, RPG | Z | zoom |
| Middle mouse | ping | V | first / third person | | |

Everywhere: **M** big map, **Tab** scores, **Esc** pause, **F11** full screen.

Leave the battle area (the edge of the map, or far out for aircraft) and a **RETURN TO COMBAT**
countdown starts: get back within 10 seconds.

---

## Trouble?

- **"Windows protected your PC"**: click **More info**, then **Run anyway**.
- **The installer will not start**: right-click the downloaded file > **Properties** > tick
  **Unblock** at the bottom > OK, then try again.
- **Nothing happens when I double-click** (zip version): make sure you used **Extract All** first and
  are running REAL STEEL from inside the unpacked `game` folder, not from inside the zip.
- **It runs slowly**: on the GRAPHICS page, turn off "Haze that catches the light", then lower
  the sharpness, then set shadows to "near only".
- **Can't see my friend's lobby**: check you both have Steam open and signed in, and both have the
  same version of the game.

---

## For developers

The game is a Godot 4.7.2 project (GDScript, everything built in code from one scene, `main.tscn`).

- Install Godot **4.7.2** (the standard version, not .NET): download it from the
  [Godot archive](https://godotengine.org/download/archive/) or the main
  [download page](https://godotengine.org/download). Run it, click **Import**, choose this
  repository's `project.godot`, then press **F5** (or the play button) to run the game.
- `CLAUDE.md` is the technical log: where everything is, test switches (`--selftest`, `--shot=...`,
  network tests), and a dated history of changes.
- Design data lives in `data/*.json`; models, maps and weapons are generated by the scripts.
- The installer (`REAL-STEEL-Setup.exe`, made with [Inno Setup](https://jrsoftware.org/isinfo.php))
  and the ready-to-play zip on the Releases page are built by the owner's packaging scripts.

## Credits

Made by Mason, built with the help of Claude (Anthropic). Engine: [Godot](https://godotengine.org).
Steam networking: [GodotSteam](https://godotsteam.com). Soldier model: "Soldier" by KolosStudios
(Poly Pizza). Sound credits and licences are listed in `sfx_pack/CREDITS.txt`; some placeholder
sounds there are still to be replaced.
