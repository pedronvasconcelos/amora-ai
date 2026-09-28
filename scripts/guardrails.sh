#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

fail() {
    printf 'guardrail: %s\n' "$1" >&2
    exit 1
}

ok() {
    printf 'ok: %s\n' "$1"
}

[ -s LICENSE ] || fail "LICENSE is missing or empty"
ok "license present"

grep -qx '.build/' .gitignore || fail ".build/ must stay gitignored"
grep -qx 'dist/' .gitignore || fail "dist/ must stay gitignored"
ok "build output is gitignored"

if git ls-files | grep -q '^\.build/'; then
    fail ".build is tracked"
fi
if git ls-files | grep -q '^dist/'; then
    fail "dist is tracked"
fi
ok "build output is not tracked"

forbidden=$(git ls-files | grep -E '(^|/)\.env($|\.)|(^|/)[^/]+\.(pem|p12|pfx)$|(^|/)id_(rsa|ed25519|ecdsa)($|\.)' || true)
[ -z "$forbidden" ] || fail "tracked secret material: $forbidden"
ok "no tracked secret files"

if git grep -I -n -E 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-|sk_live_[A-Za-z0-9]{10,}' >/dev/null; then
    git grep -I -n -E 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-|sk_live_[A-Za-z0-9]{10,}' || true
    fail "possible secret in a tracked file"
fi
ok "no secret-shaped content"

find . -name '*.sh' -not -path './.git/*' -not -path './.build/*' > "$tmp"
while IFS= read -r script; do
    [ -n "$script" ] || continue
    sh -n "$script" || fail "$script has a syntax error"
    ok "syntax $script"
done < "$tmp"

git ls-files > "$tmp"
while IFS= read -r file; do
    [ -n "$file" ] || continue
    size=$(wc -c < "$file" | tr -d ' ')
    if [ "$size" -gt 2000000 ]; then
        fail "$file is ${size} bytes; tracked files must stay under 2MB"
    fi
done < "$tmp"
ok "tracked files are under 2MB"

find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) > "$tmp"
while IFS= read -r workflow; do
    [ -n "$workflow" ] || continue
    if grep -n 'pull_request_target' "$workflow"; then
        fail "pull_request_target is not allowed"
    fi
    if grep -E 'write-all' "$workflow" >/dev/null; then
        fail "workflow token must not use write-all"
    fi
    case "$workflow" in
        .github/workflows/release.yml)
            grep -q 'contents: write' "$workflow" || fail "release workflow must request contents: write"
            grep -q 'tags:' "$workflow" || fail "release workflow must be tag-triggered"
            if grep -E 'pull_request:' "$workflow" >/dev/null; then
                fail "release workflow must not run on pull requests"
            fi
            ;;
        *)
            if grep -E 'contents: write' "$workflow" >/dev/null; then
                fail "workflow token must stay read-only"
            fi
            ;;
    esac
done < "$tmp"
grep -q 'contents: read' .github/workflows/ci.yml || fail "CI token must be read-only"
ok "workflow tokens are constrained"
