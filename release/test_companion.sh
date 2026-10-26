#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/anmir-companion-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SRC="$ROOT/companion/src/main/java/io/github/houzi3/anmir/connect"
javac -d "$WORK" "$SRC/RelaySession.java" "$SRC/LocalMdns.java" \
    "$SRC/ReconnectTarget.java" "$SRC/RelayHttp.java" "$ROOT"/companion/tests/*.java
for name in RelaySessionTest LocalMdnsTest ReconnectTest; do
    java -ea -cp "$WORK" "io.github.houzi3.anmir.connect.$name"
done
