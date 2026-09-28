# Amora

![Amora app icon](assets/icon.png)

Amora is an early macOS menu bar prototype that displays the latest activity reported by Codex, Cursor, and Claude Code. It receives local lifecycle hooks over a Unix socket and shows the activity in a small menu bar popover and on a floating desktop pet.

Amora does not yet include research features or a downloadable app installer.

## Requirements

- macOS 14 or later
- Swift 6.2 or later

## Run from source

```sh
git clone https://github.com/pedronvasconcelos/amora-ai.git
cd amora-ai
swift run Amora
```

`swift run` stays open while the menu bar app is running. The pet appears on the desktop, stays visible across Spaces, and does not take focus. Click the paw icon in the menu bar to see the latest activity. Choose **Hide pet** or **Show pet** in that menu to change the pet. Choose **Settings…** to open the Settings window. Quit Amora from that menu or press `Ctrl+C` in the Terminal.

Settings lists Codex, Cursor, and Claude Code. Each row shows **Installed** or **Not installed**, with **Install** or **Remove**. **Launch at login** is under General. The choice is saved on this Mac. macOS opens Amora at login when Amora is running as an installed app; `swift run` only stores the preference.

Installing hooks keeps your existing settings and any hooks you or another tool already configured. Each hook sends only a fixed activity value to Amora; it does not forward prompts, files, or tool input and output. If Amora is not running, the hook exits without interrupting the agent.

To enable Codex activity, choose **Install** next to Codex, then review and trust Amora's hooks in Codex settings or with `/hooks` in the Codex CLI.

To enable Cursor activity, choose **Install** next to Cursor, then review and trust Amora's hooks in Cursor Hooks settings.

To enable Claude Code activity, choose **Install** next to Claude Code, then review and trust Amora's hooks in Claude Code settings.

## Test

```sh
swift test
```

## Project status

This is an early, work-in-progress prototype. You can run it from source, open Settings, connect Codex, Cursor, and Claude Code activity, and watch that activity on the desktop pet. There is no packaged `.app` or `.dmg` release yet. Contributions and focused bug reports are welcome.

## License

Amora is available under the [MIT License](LICENSE).
