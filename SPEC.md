# Pet v0.1

Open-source Mac app. A single floating pet sits on the desktop and shows what Cursor and Claude Code are doing. Both hosts feed the same pet. Pet does not run inside either host. Each host notifies Pet through a shell hook.

## What the pet shows

One pet, one current activity. The latest event sets the activity.

| Activity | Meaning |
| --- | --- |
| Thinking | A turn just started |
| Working | The agent is using a tool or editing a file |
| Waiting | The agent is waiting for a response |
| Finished | The turn ended |

## Who sends what

Cursor, via `~/.cursor/hooks.json`:

| Hook | Activity |
| --- | --- |
| `beforeSubmitPrompt` | Thinking |
| `preToolUse` | Working |
| `afterFileEdit` | Working |
| `stop` | Finished |

Claude Code, via `~/.claude/settings.json`:

| Hook | Activity |
| --- | --- |
| `UserPromptSubmit` | Thinking |
| `PreToolUse` | Working |
| `PermissionRequest` | Waiting |
| `Stop` | Finished |

Hooks are observers. They exit 0, return no permission decision, and do not block or alter the host. If Pet is not running, the hook exits 0 and drops the event.

A hook sends only the activity. Prompt text, file contents, tool input, and tool output stay on stdin and are not forwarded.

## How a host reaches the pet

Each hook is a shell script. It writes one JSON object, terminated by a newline, to a Unix socket:

`~/Library/Application Support/Pet/pet.sock`

```json
{"v":1,"source":"cursor","activity":"thinking"}
```

`source` is `cursor` or `claude`. `activity` is `thinking`, `working`, `waiting`, or `finished`.

## App

- Swift.
- Menu bar item is an `NSStatusItem`. Its menu is SwiftUI: show or hide the pet, open Settings, quit.
- Settings is a SwiftUI window: install or remove the hooks, and turn launch-at-login on or off.
- Launch at login uses `SMAppService`.
- The pet window is an AppKit `NSPanel`: transparent, non-activating, always above other windows, visible on every Space.
- The pet is a SpriteKit scene. Each activity has its own animation.

Installing hooks merges Pet’s command entries into the existing user files and leaves every other entry in place. Removing hooks deletes only Pet’s entries.

## Out of scope for v0.1

Quick search, classification, and any other assistant feature.
