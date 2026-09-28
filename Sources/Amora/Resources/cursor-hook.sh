#!/bin/sh

project=$(
    /usr/bin/awk '
        function capture(rest,    i, c, out, esc) {
            out = ""
            esc = 0
            for (i = 1; i <= length(rest); i++) {
                c = substr(rest, i, 1)
                if (esc) {
                    if (c == "n" || c == "r" || c == "t") return ""
                    out = out c
                    esc = 0
                } else if (c == "\\") {
                    esc = 1
                } else if (c == "\"") {
                    return out
                } else {
                    out = out c
                }
            }
            return ""
        }
        { buf = buf $0 }
        END {
            path = ""
            if (match(buf, /"workspace_roots"[[:space:]]*:[[:space:]]*\[[[:space:]]*"/)) {
                path = capture(substr(buf, RSTART + RLENGTH))
            }
            if (path == "" && match(buf, /"cwd"[[:space:]]*:[[:space:]]*"/)) {
                path = capture(substr(buf, RSTART + RLENGTH))
            }
            printf "%s", path
        }
    ' | {
        IFS= read -r project_path || true
        while :; do
            case "$project_path" in
                */) project_path=${project_path%/} ;;
                *) break ;;
            esac
        done
        project=${project_path##*/}
        project=$(printf '%s' "$project" | /usr/bin/sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        quote='"'
        backslash='\'
        case "$project" in
            ""|"."|"..") project="" ;;
            *"/"*|*"$backslash"*|*"$quote"*|*\'*|*[[:cntrl:]]*) project="" ;;
        esac
        if [ "${#project}" -gt 120 ]; then
            project=""
        fi
        printf '%s' "$project"
    }
)

case "$1" in
    beforeSubmitPrompt) activity=thinking ;;
    preToolUse|afterFileEdit) activity=working ;;
    stop) activity=finished; printf '{}\n' ;;
    *) exit 0 ;;
esac

socket="$HOME/Library/Application Support/Pet/pet.sock"
[ -S "$socket" ] || exit 0

if [ -n "$project" ]; then
    printf '{"v":1,"source":"cursor","activity":"%s","project":"%s"}\n' "$activity" "$project" |
        /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1
else
    printf '{"v":1,"source":"cursor","activity":"%s"}\n' "$activity" |
        /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1
fi

exit 0
