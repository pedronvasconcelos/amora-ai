# Amora

![Amora app icon](assets/icon.png)

Amora is an early macOS menu bar prototype that displays the latest activity reported by Codex. It receives local Codex lifecycle hooks over a Unix socket and shows the activity in a small menu bar popover.

Amora currently supports Codex activity only. It does not yet include the floating pet, Cursor or Claude Code integrations, research features, Settings, launch at login, or a downloadable app installer.

## Requirements

- macOS 14 or later
- Swift 6.2 or later

## Run from source

```sh
git clone https://github.com/pedronvasconcelos/amora-ai.git
cd amora-ai
swift run Amora
```

`swift run` stays open while the menu bar app is running. Click the paw icon in the menu bar to see the latest activity and install or remove Codex hooks. Quit Amora from that menu or press `Ctrl+C` in the Terminal.

To enable Codex activity, choose **Install Codex Hooks** in the Amora menu, then review and trust its hooks in Codex settings or with `/hooks` in the Codex CLI. The hook sends only a fixed activity value to Amora; it does not forward prompts, files, or tool input and output. If Amora is not running, the hook exits without interrupting Codex.

## Test

```sh
swift test
```

## Project status

This is an early, work-in-progress prototype. You can run it from source and connect Codex activity, but there is no packaged `.app` or `.dmg` release yet. Contributions and focused bug reports are welcome.

## License

Amora is available under the [MIT License](LICENSE).
