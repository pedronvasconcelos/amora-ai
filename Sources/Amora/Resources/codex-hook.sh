#!/bin/sh

# The case statement stays outside $(...) so macOS /bin/sh (Bash 3.2) can parse it.
read_project() {
    project_path=$(/usr/bin/awk '
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
    ')
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

project=$(read_project)

case "$1" in
    UserPromptSubmit) activity=thinking ;;
    PreToolUse) activity=working ;;
    PermissionRequest) activity=waiting ;;
    Stop) activity=finished; printf '{}\n' ;;
    *) exit 0 ;;
esac

socket="$HOME/Library/Application Support/Pet/pet.sock"
[ -S "$socket" ] || exit 0

if [ -n "$project" ]; then
    printf '{"v":1,"source":"codex","activity":"%s","project":"%s"}\n' "$activity" "$project" |
        /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1
else
    printf '{"v":1,"source":"codex","activity":"%s"}\n' "$activity" |
        /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1
fi

exit 0
