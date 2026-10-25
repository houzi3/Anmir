#!/bin/sh
# All paths arrive as separate arguments; no release text is evaluated as code.
set -eu
parent="$1"
stage="$2"
target="$3"
work="$4"
backup="${target%.app}.previous-$(date +%Y%m%d-%H%M%S)-$$.app"
cleanup() { /bin/rm -rf "$stage" "$work"; }
trap cleanup EXIT
# If termination was cancelled, leave the running installation untouched.
attempt=0
while kill -0 "$parent" 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 60 ] || exit 1
    /bin/sleep 1
done
[ -d "$target" ] && [ -d "$stage/Anmir.app" ] || exit 1
/bin/mv "$target" "$backup" || exit 1
if ! /bin/mv "$stage/Anmir.app" "$target"; then
    /bin/mv "$backup" "$target"
    /usr/bin/open "$target"
    exit 1
fi
if ! /usr/bin/open "$target"; then
    /bin/mv "$target" "$stage/failed.app"
    /bin/mv "$backup" "$target"
    /usr/bin/open "$target"
    exit 1
fi
# Keep the backup for recovery even if a new process exits after launch.
