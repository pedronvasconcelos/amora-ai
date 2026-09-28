#!/bin/sh

case "$1" in
    UserPromptSubmit) activity=thinking ;;
    PreToolUse) activity=working ;;
    PermissionRequest) activity=waiting ;;
    Stop) activity=finished; printf '{}\n' ;;
    *) exit 0 ;;
esac

socket="$HOME/Library/Application Support/Pet/pet.sock"
[ -S "$socket" ] || exit 0

printf '{"v":1,"source":"claude","activity":"%s"}\n' "$activity" |
    /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1

exit 0
