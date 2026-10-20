# Tower Defence (Roblox)

A hard, real-time-strategy tower defence game with random wave events, walking builders, controllable units with Q/E/R abilities, and a dungeon portal that opens after wave 1. Clear four dungeon floors and beat the Overlord to win.

This folder holds all of the game's code. [Rojo](https://rojo.space) syncs it into Roblox Studio.

## What's where

| File | In Studio | What it does |
|---|---|---|
| `src/shared/Config.luau` | ReplicatedStorage > Shared > Config | All numbers: costs, HP, damage, waves, events, abilities |
| `src/shared/Models.luau` | ReplicatedStorage > Shared > Models | Builds every 3D model and effect |
| `src/shared/SelectBox.luau` | ReplicatedStorage > Shared > SelectBox | Drag-a-rectangle unit selection |
| `src/shared/AbilityBar.luau` | ReplicatedStorage > Shared > AbilityBar | The Q / E / R ability buttons |
| `src/server/GameServer.server.luau` | ServerScriptService > GameServer | Main game: map, waves, enemies, builders, events, trade truck |
| `src/server/Dungeon.luau` | ServerScriptService > Dungeon | Dungeon floors, rooms, loot, graves, bosses |
| `src/client/BuildClient.client.luau` | StarterPlayerScripts > BuildClient | Build bar, placing, selecting and moving units, HUD |
| `src/client/DungeonClient.client.luau` | StarterPlayerScripts > DungeonClient | Dungeon camera and controls, upgrade shop |
| `src/client/MinimapClient.client.luau` | StarterPlayerScripts > MinimapClient | Minimap (press M for the full view) |
| `src/client/DevConsole.client.luau` | StarterPlayerScripts > DevConsole | Test console (F2, Studio/owner only) |

File endings decide the script type: `.server.luau` = Script, `.client.luau` = LocalScript, `.luau` = ModuleScript.

## Live sync with Studio (one-time setup, Windows + VS Code)

1. **Get the code onto your PC.** In VS Code, press `Ctrl+Shift+P`, type **Git: Clone**, pick **Clone from GitHub**, sign in, and choose this repo. Save it somewhere easy, like `Documents\tower-defence`. When VS Code asks, click **Open**.
   - If VS Code says Git is missing, install it from https://git-scm.com/download/win (keep all the default options), then restart VS Code.
2. **Install the Rojo extension.** In VS Code, open Extensions (`Ctrl+Shift+X`), search for **Rojo** (by evaera), and click **Install**.
3. **Start Rojo.** Click the Rojo icon in the left sidebar, then click `default.project.json`. If it offers to install Rojo or the Roblox Studio plugin, say **yes** to both. The server starts on port 34872.
4. **Connect Studio.** Open the place in Roblox Studio. On the **Plugins** tab, click **Rojo**, then **Connect**.

Now any file you save in VS Code updates the scripts in Studio right away.

### Important: the files are the boss

While Rojo is connected, the files in this folder **overwrite** the scripts in Studio. Make code changes in the files, not in Studio's script editor, or Rojo will replace your Studio edits.

Rojo only manages the scripts listed above. Anything else you add in Studio (parts, models, sounds) is left alone, so keep saving and publishing the place from Studio as usual.

## Saving to GitHub

In VS Code, open Source Control (`Ctrl+Shift+G`). Type a short message about what changed, then click **Commit** and **Sync Changes**.

## Command line (optional)

`rokit.toml` pins the Rojo version. If you use [Rokit](https://github.com/rojo-rbx/rokit), run `rokit install` and then `rojo serve`.
