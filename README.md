# Amora

![Amora app icon](assets/icon.png)

Amora is an early macOS menu bar prototype that displays the latest activity reported by Codex, Cursor, and Claude Code. It receives local lifecycle hooks over a Unix socket and shows the activity in a small menu bar popover and on a floating desktop pet.

Amora does not yet include research features.

## Install

Download the Apple Silicon disk image from the [latest GitHub release](https://github.com/pedronvasconcelos/amora-ai/releases/latest). Open it and drag Amora into Applications.

Amora is unsigned. The first time you open it, Control-click Amora in Applications, choose **Open**, then choose **Open** again. After that, the paw icon appears in the menu bar.

The packaged app needs macOS 14 or later on Apple Silicon. It does not need Swift or Xcode.

Click the paw icon to see the latest activity. Each agent that has reported shows what it is doing and the folder name of the project it is working in. Choose **Pets…** to open the Pets window, where you add pets to the desktop (up to six). A pet can follow all agents or only Cursor, Codex, or Claude Code. The built-in collies are Amora (blue merle, all agents), Luna (black and white, Cursor), Storm (slate merle, Codex), and Duna (brown and white, Claude Code). You can still pick a registered model for any of them. Show or hide a pet, make it active, or remove it. Each pet keeps its own model, size, and position on this Mac. Drag a pet to move it, or drag its edges and corners to resize it. Choose **Settings…** to open the Settings window. Quit Amora from that menu.

### Pet models

Amora accepts pet models in the same format as Codex custom pets: a folder with a `pet.json` manifest and a transparent `spritesheet.webp` (or PNG). In the Pets window, choose **Register model…**, then drag `pet.json` and the spritesheet, or the folder that contains them, onto the drop zone. Amora validates the package, shows a preview of each animation, and copies it to `~/Library/Application Support/Amora/pets/<id>/`. Registering a model with an existing `id` replaces it.

Pets already installed for Codex in `~/.codex/pets` (or `$CODEX_HOME/pets`) also appear in the Pets window automatically, labeled **From Codex**. Amora reads them in place and never changes that folder. If a registered model has the same `id`, Amora uses the registered copy.

```json
{
  "id": "codie",
  "displayName": "Codie",
  "description": "A tiny robot companion.",
  "spritesheetPath": "spritesheet.webp"
}
```

The spritesheet has 8 columns of 192×208 cells: 1536×1872 with 9 rows for version 1, or 1536×2288 with 11 rows when `pet.json` declares `"spriteVersionNumber": 2`. Rows follow the Codex order: `idle`, `running-right`, `running-left`, `waving`, `jumping`, `failed`, `waiting`, `running`, `review`. Each row plays its consecutive non-empty frames from the first column. Amora shows `idle` while resting, `review` while thinking, `running` while working, `waiting` while waiting, and `jumping` when finished.

Settings lists Codex, Cursor, and Claude Code. Each row shows **Installed** or **Not installed**, with **Install** or **Remove**. **Launch at login** is under General. The choice is saved on this Mac. macOS opens Amora at login when Amora is in Applications; `swift run` only stores the preference.

Installing hooks keeps your existing settings and any hooks you or another tool already configured. Each hook sends the activity and the project folder name. It does not send the prompt, files, or tool results. If Amora is not running, the hook exits without interrupting the agent. Choose **Install** again to update hook scripts from an earlier version; other hooks stay in place.

To enable Codex activity, choose **Install** next to Codex, then review and trust Amora's hooks in Codex settings or with `/hooks` in the Codex CLI.

To enable Cursor activity, choose **Install** next to Cursor, then review and trust Amora's hooks in Cursor Hooks settings.

To enable Claude Code activity, choose **Install** next to Claude Code, then review and trust Amora's hooks in Claude Code settings.

## Run from source

```sh
git clone https://github.com/pedronvasconcelos/amora-ai.git
cd amora-ai
swift run Amora
```

`swift run` stays open while the menu bar app is running. Quit Amora from the menu or press `Ctrl+C` in the Terminal.

Requires Swift 6.2 or later.

## Test

```sh
swift test
```

## Package

```sh
sh scripts/package.sh
```

Writes `dist/Amora.app` and `dist/Amora-<version>-arm64.dmg`. Push a version tag (`0.1.2` or `v0.1.2`) or create a release in the GitHub UI to build the disk image and attach it to the release. To backfill an existing tag, run the Release workflow manually with that tag.

## Project status

This is an early, work-in-progress prototype. You can install the macOS app, open Settings, connect Codex, Cursor, and Claude Code activity, and watch that activity on desktop pets. Contributions and focused bug reports are welcome.

## License

Amora is available under the [MIT License](LICENSE).
