# Amora

![Amora app icon](assets/icon.png)

Amora is an early macOS menu bar prototype that displays the latest activity reported by Codex, Cursor, and Claude Code. It receives local lifecycle hooks over a Unix socket and shows the activity in a small menu bar popover.

Amora does not yet include the floating pet, research features, Settings, launch at login, or a downloadable app installer.

## Requirements

- macOS 14 or later
- Swift 6.2 or later

## Run from source

```sh
git clone https://github.com/pedronvasconcelos/amora-ai.git
cd amora-ai
swift run Amora
```

`swift run` stays open while the menu bar app is running. Click the paw icon in the menu bar to see the latest activity and install or remove hooks. Quit Amora from that menu or press `Ctrl+C` in the Terminal.

Installing hooks keeps your existing settings and any hooks you or another tool already configured. Each hook sends only a fixed activity value to Amora; it does not forward prompts, files, or tool input and output. If Amora is not running, the hook exits without interrupting the agent.

To enable Codex activity, choose **Install Codex Hooks**, then review and trust its hooks in Codex settings or with `/hooks` in the Codex CLI.

To enable Cursor activity, choose **Install Cursor Hooks**, then review and trust its hooks in Cursor Hooks settings.

To enable Claude Code activity, choose **Install Claude Code Hooks**, then review and trust its hooks in Claude Code settings.

## Test

```sh
swift test
```

## Project status

This is an early, work-in-progress prototype. You can run it from source and connect Codex, Cursor, and Claude Code activity, but there is no packaged `.app` or `.dmg` release yet. Contributions and focused bug reports are welcome.

## License

Amora is available under the [MIT License](LICENSE).
