#!/bin/sh

# The case statements stay outside $(...) so macOS /bin/sh (Bash 3.2) can parse them.
# Prints four lines: the project path, the session id, the subagent id, and the subagent type.
# Ids come only from the part of the payload before its first nested object, so text inside
# tool input can never pass for one. Every agent sends them ahead of tool input.
read_payload() {
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
        function field(text, key) {
            if (match(text, "\"" key "\"[[:space:]]*:[[:space:]]*\"")) {
                return capture(substr(text, RSTART + RLENGTH))
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
            head = substr(buf, index(buf, "{") + 1)
            nested = index(head, "{")
            if (nested > 0) head = substr(head, 1, nested - 1)
            session = field(head, "conversation_id")
            if (session == "") session = field(head, "session_id")
            printf "%s\n%s\n%s\n%s\n", path, session, field(head, "agent_id"), field(head, "agent_type")
        }
    '
}

project_name() {
    project_path=$1
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

# Session and subagent ids are opaque tokens; anything else is dropped.
accepted_id() {
    case "$1" in
        ""|*[![:alnum:]._:-]*) return 0 ;;
    esac
    if [ "${#1}" -le "$2" ]; then
        printf '%s' "$1"
    fi
}

payload=$(read_payload)
{
    IFS= read -r project_path
    IFS= read -r session
    IFS= read -r subagent
    IFS= read -r subagent_type
} <<EOF
$payload
EOF
project=$(project_name "$project_path")
session=$(accepted_id "$session" 128)
subagent=$(accepted_id "$subagent" 128)
subagent_type=$(accepted_id "$subagent_type" 64)
ended=""

case "$1" in
    UserPromptSubmit) activity=thinking ;;
    PreToolUse) activity=working ;;
    PermissionRequest) activity=waiting ;;
    Stop) activity=finished; printf '{}\n' ;;
    SubagentStart) activity=working ;;
    SubagentStop) activity=finished; ended=1; printf '{}\n' ;;
    SessionEnd) activity=finished; ended=1 ;;
    *) exit 0 ;;
esac

# A subagent event without its id would otherwise be read as news of the whole session.
case "$1" in
    SubagentStart|SubagentStop) [ -n "$subagent" ] || exit 0 ;;
esac

socket="$HOME/Library/Application Support/Pet/pet.sock"
[ -S "$socket" ] || exit 0

line='{"v":1,"source":"claude","activity":"'"$activity"'"'
[ -n "$project" ] && line="$line"',"project":"'"$project"'"'
[ -n "$session" ] && line="$line"',"session":"'"$session"'"'
[ -n "$subagent" ] && line="$line"',"subagent":"'"$subagent"'"'
[ -n "$subagent" ] && [ -n "$subagent_type" ] && line="$line"',"subagentType":"'"$subagent_type"'"'
[ -n "$ended" ] && line="$line"',"ended":true'
printf '%s}\n' "$line" | /usr/bin/nc -U -w 1 "$socket" >/dev/null 2>&1

exit 0
