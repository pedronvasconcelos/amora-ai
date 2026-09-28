#!/bin/sh

case "$1" in
    beforeSubmitPrompt) activity=thinking ;;
    preToolUse|afterFileEdit) activity=working ;;
    stop) activity=finished; printf '{}\n' ;;
    *) exit 0 ;;
esac

socket="$HOME/Library/Application Support/Pet/pet.sock"
[ -S "$socket" ] || exit 0

printf '{"v":1,"source":"cursor","activity":"%s"}\n' "$activity" |
    /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1

exit 0
